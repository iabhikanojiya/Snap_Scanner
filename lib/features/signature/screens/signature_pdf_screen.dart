import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:snap_scanner/core/services/analytics_service.dart';
import '../services/signature_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tool_ui.dart';

class _PlacedSignature {
  int pageIndex;
  double x;
  double y;
  double width;

  /// Clockwise rotation in radians around the centre.
  double rotation = 0;

  _PlacedSignature({
    required this.pageIndex,
    required this.x,
    required this.y,
    this.width = 200,
  });
}

class SignaturePdfScreen extends StatefulWidget {
  final Uint8List signaturePngBytes;
  final String pdfPath;
  final String outputName;
  final List<Map<String, dynamic>>? strokeData;

  const SignaturePdfScreen({
    super.key,
    required this.signaturePngBytes,
    required this.pdfPath,
    required this.outputName,
    this.strokeData,
  });

  @override
  State<SignaturePdfScreen> createState() => _SignaturePdfScreenState();
}

class _SignaturePdfScreenState extends State<SignaturePdfScreen> {
  px.PdfDocument? _document;
  late PageController _pageController;
  int _pageCount = 0;
  int _currentPage = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _navigatedAway = false;
  String? _loadError;

  final List<_PlacedSignature> _placements = [];
  int _selectedLocalIndex = -1;
  double _defaultWidth = 200;
  double _signatureAspectRatio = 3.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadDocument();
    _loadSignatureAspectRatio();
  }

  Future<void> _loadSignatureAspectRatio() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(widget.signaturePngBytes, (image) => completer.complete(image));
    final image = await completer.future;
    _signatureAspectRatio = image.width / image.height;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _closeDocument();
    super.dispose();
  }

  Future<void> _closeDocument() async {
    final doc = _document;
    if (doc != null) {
      _document = null;
      await doc.close();
    }
  }

  Future<void> _loadDocument() async {
    try {
      final doc = await px.PdfDocument.openFile(widget.pdfPath);
      if (mounted) {
        setState(() {
          _document = doc;
          _pageCount = doc.pagesCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load PDF: $e')),
        );
      }
    }
  }

  void _addSignatureAt(double x, double y) {
    _selectedLocalIndex = -1;
    setState(() {
      _placements.add(_PlacedSignature(
        pageIndex: _currentPage,
        x: x.clamp(0.05, 0.95),
        y: y.clamp(0.05, 0.95),
        width: _defaultWidth,
      ));
    });
  }

  void _addSignatureCentered() {
    _addSignatureAt(0.5, 0.7);
  }

  void _removeSignature(int index) {
    if (_selectedLocalIndex >= 0) {
      final gIndex = _placementIndexOnCurrentPage(_selectedLocalIndex);
      if (gIndex == index) _selectedLocalIndex = -1;
    }
    setState(() {
      _placements.removeAt(index);
    });
  }

  void _movePlacement(int index, double x, double y) {
    setState(() {
      _placements[index].x = x.clamp(0.05, 0.95);
      _placements[index].y = y.clamp(0.05, 0.95);
    });
  }

  void _selectPlacement(int localIndex) {
    setState(() {
      _selectedLocalIndex = _selectedLocalIndex == localIndex ? -1 : localIndex;
    });
  }

  /// Resizes a placement from its corner handles. New signatures reuse the
  /// last size the user picked.
  void _resizePlacement(int index, double newWidth) {
    setState(() {
      final width = newWidth.clamp(60.0, 500.0);
      _placements[index].width = width;
      _defaultWidth = width;
    });
  }

  void _rotatePlacement(int index, double radians) {
    setState(() => _placements[index].rotation = radians);
  }

  int _placementIndexOnCurrentPage(int listIndex) {
    int count = -1;
    for (int i = 0; i < _placements.length; i++) {
      if (_placements[i].pageIndex == _currentPage) {
        count++;
        if (count == listIndex) return i;
      }
    }
    return -1;
  }

  Future<void> _savePdf() async {
    if (_placements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one signature before saving.')),
      );
      return;
    }

    if (_document == null) return;

    setState(() => _isSaving = true);

    try {
      await _closeDocument();

      final placements = _placements.map((p) => SignaturePlacement(
        pageIndex: p.pageIndex,
        x: p.x,
        y: p.y,
        width: p.width,
        rotation: p.rotation * 180 / math.pi,
      )).toList();

      final File file;
      if (widget.strokeData != null) {
        file = await SignatureService.addSignaturesToPdfWithStrokes(
          sourcePdfPath: widget.pdfPath,
          strokeData: widget.strokeData!,
          placements: placements,
          outputName: widget.outputName,
        );
      } else {
        final completer = Completer<ui.Image>();
        ui.decodeImageFromList(widget.signaturePngBytes, (image) => completer.complete(image));
        final transparentImage = await completer.future;

        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xFFFFFFFF), BlendMode.src);
        canvas.drawImage(transparentImage, Offset.zero, Paint());
        final whiteBgImage = await recorder.endRecording().toImage(
          transparentImage.width,
          transparentImage.height,
        );

        file = await SignatureService.addSignaturesToPdf(
          sourcePdfPath: widget.pdfPath,
          signatureImage: whiteBgImage,
          placements: placements,
          outputName: widget.outputName,
        );
      }

      AnalyticsService.instance.logPdfSaved();
      AnalyticsService.instance.logSignatureUsed();

      if (mounted) {
        _navigatedAway = true;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: file,
              title: 'PDF Signed Successfully!',
              shortcuts: const [
                SuccessShortcut.lockPdf,
                SuccessShortcut.splitPdf,
                SuccessShortcut.compressPdf,
              ],
              subtitle: '${placements.length} signature${placements.length > 1 ? 's' : ''} added',
            ),
          ),
        );
      }
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'signature_pdf_save_failed',
        message: e.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted && !_navigatedAway) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_isSaving && !_isLoading && _loadError == null && _document != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Sign PDF'),
      body: _isSaving
          ? const ToolProcessingView(message: 'Adding signatures to PDF...')
          : _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.brandRed))
              : !ready
                  ? _buildLoadError()
                  : Column(
                      children: [
                        _buildInfoBar(),
                        Expanded(
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: _pageCount,
                            onPageChanged: (index) {
                              setState(() {
                                _currentPage = index;
                                _selectedLocalIndex = -1;
                              });
                            },
                            itemBuilder: (context, index) {
                              return _PdfPageWidget(
                                document: _document!,
                                pageNumber: index + 1,
                                signaturePngBytes: widget.signaturePngBytes,
                                signatureAspectRatio: _signatureAspectRatio,
                                placements: _placements
                                    .where((p) => p.pageIndex == index)
                                    .toList(),
                                selectedLocalIndex: _selectedLocalIndex,
                                onTap: (x, y) => _addSignatureAt(x, y),
                                onSelect: (localIndex) => _selectPlacement(localIndex),
                                onDeletePlacement: (localIndex) {
                                  final globalIndex = _placementIndexOnCurrentPage(localIndex);
                                  if (globalIndex >= 0) _removeSignature(globalIndex);
                                },
                                onMovePlacement: (localIndex, x, y) {
                                  final globalIndex = _placementIndexOnCurrentPage(localIndex);
                                  if (globalIndex >= 0) _movePlacement(globalIndex, x, y);
                                },
                                onResizePlacement: (localIndex, width) {
                                  final globalIndex = _placementIndexOnCurrentPage(localIndex);
                                  if (globalIndex >= 0) _resizePlacement(globalIndex, width);
                                },
                                onRotatePlacement: (localIndex, radians) {
                                  final globalIndex = _placementIndexOnCurrentPage(localIndex);
                                  if (globalIndex >= 0) _rotatePlacement(globalIndex, radians);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
      bottomNavigationBar: ready
          ? ToolBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _addSignatureCentered,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandRed,
                          side: const BorderSide(color: AppColors.brandRed, width: 1.5),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add Signature'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ToolPrimaryButton(
                      label: 'Save PDF',
                      icon: Icons.check_rounded,
                      onPressed: _placements.isEmpty ? null : _savePdf,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildInfoBar() {
    final multiPage = _pageCount > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              if (multiPage)
                _PageArrow(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous page',
                  onTap: _currentPage > 0
                      ? () => _pageController.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          )
                      : null,
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Page ${_currentPage + 1} of $_pageCount',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              if (multiPage)
                _PageArrow(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Next page',
                  onTap: _currentPage < _pageCount - 1
                      ? () => _pageController.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          )
                      : null,
                ),
              const Spacer(),
              if (_placements.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.brandRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.draw_rounded, size: 14, color: AppColors.brandRed),
                      const SizedBox(width: 5),
                      Text(
                        '${_placements.length} placed',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandRed),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _placements.isEmpty
                ? 'Tap anywhere on the page to place your signature'
                : 'Drag to move · corners resize · ↻ rotates · ✕ removes',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: Color(0xFFF1F2F4), shape: BoxShape.circle),
              child: const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFFA0A6B1)),
            ),
            const SizedBox(height: 18),
            Text(
              _loadError != null ? 'Failed to load PDF' : 'PDF not available',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              _loadError ?? 'An unexpected error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 180,
              child: ToolPrimaryButton(label: 'Go Back', onPressed: () => Navigator.pop(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageArrow extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _PageArrow({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: onTap == null ? const Color(0xFFCBD0D8) : AppColors.textPrimary),
    );
  }
}

class _PdfPageWidget extends StatefulWidget {
  final px.PdfDocument document;
  final int pageNumber;
  final Uint8List signaturePngBytes;
  final double signatureAspectRatio;
  final List<_PlacedSignature> placements;
  final int selectedLocalIndex;
  final void Function(double x, double y) onTap;
  final void Function(int index) onSelect;
  final void Function(int index) onDeletePlacement;
  final void Function(int index, double x, double y) onMovePlacement;
  final void Function(int index, double widthPt) onResizePlacement;
  final void Function(int index, double radians) onRotatePlacement;

  const _PdfPageWidget({
    required this.document,
    required this.pageNumber,
    required this.signaturePngBytes,
    required this.signatureAspectRatio,
    required this.placements,
    required this.selectedLocalIndex,
    required this.onTap,
    required this.onSelect,
    required this.onDeletePlacement,
    required this.onMovePlacement,
    required this.onResizePlacement,
    required this.onRotatePlacement,
  });

  @override
  State<_PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<_PdfPageWidget> {
  Uint8List? _imageBytes;
  bool _isLoadingPage = true;
  double _aspectRatio = 1.0;
  double _displayW = 0;
  double _displayH = 0;
  double _pageWidthPt = 595;

  final Map<int, Offset> _dragRelDeltas = {};

  /// Finger position (page-local) while dragging a rotate handle.
  final Map<int, Offset> _rotateDragPos = {};

  static const double _rotateStem = 26;

  @override
  void initState() {
    super.initState();
    _renderPage();
  }

  @override
  void didUpdateWidget(_PdfPageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageNumber != widget.pageNumber) {
      _imageBytes = null;
      _isLoadingPage = true;
      _dragRelDeltas.clear();
      _renderPage();
    }
  }

  Future<void> _renderPage() async {
    try {
      final page = await widget.document.getPage(widget.pageNumber);
      _pageWidthPt = page.width;
      _aspectRatio = page.width / page.height;

      final renderWidth = 600.0;
      final pageImage = await page.render(
        width: renderWidth,
        height: renderWidth / _aspectRatio,
        format: px.PdfPageImageFormat.jpeg,
        quality: 90,
      );
      await page.close();

      if (mounted) {
        setState(() {
          _imageBytes = pageImage?.bytes;
          _isLoadingPage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPage = false);
      }
    }
  }

  /// Normalises [a] to (-π, π]; snaps to the nearest quarter turn when within
  /// 6° (or always, with [force]).
  static double _snap(double a, {bool force = false}) {
    const quarter = math.pi / 2;
    final nearest = (a / quarter).round() * quarter;
    if (force || (a - nearest).abs() < 6 * math.pi / 180) a = nearest;
    a = a % (2 * math.pi);
    if (a > math.pi) a -= 2 * math.pi;
    return a.abs() < 1e-9 ? 0 : a;
  }

  static int _degrees(double radians) {
    final d = (radians * 180 / math.pi).round() % 360;
    return d < 0 ? d + 360 : d;
  }

  /// Places a corner control with a 36px touch target centred on [center],
  /// kept inside the page.
  Widget _cornerControl({required Offset center, required Widget child}) {
    const hit = 36.0;
    return Positioned(
      left: (center.dx - hit / 2).clamp(0.0, _displayW - hit),
      top: (center.dy - hit / 2).clamp(0.0, _displayH - hit),
      width: hit,
      height: hit,
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;
    if (_isLoadingPage || bytes == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth - 32;
        final maxH = constraints.maxHeight - 16;
        final imageW = maxW;
        final imageH = imageW / _aspectRatio;

        _displayH = imageH > maxH ? maxH : imageH;
        _displayW = _displayH == maxH ? maxH * _aspectRatio : imageW;

        return Center(
          child: GestureDetector(
            onTapUp: (details) {
              final renderBox = context.findRenderObject() as RenderBox;
              final localPos = renderBox.globalToLocal(details.globalPosition);
              final containerOffset = (renderBox.size.width - _displayW) / 2;
              final relativeX = (localPos.dx - containerOffset) / _displayW;
              final relativeY = (localPos.dy - (renderBox.size.height - _displayH) / 2) / _displayH;
              if (relativeX >= 0 && relativeX <= 1 && relativeY >= 0 && relativeY <= 1) {
                widget.onTap(relativeX, relativeY);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: _displayW,
                  height: _displayH,
                  child: Stack(
                    children: [
                      Image.memory(bytes, fit: BoxFit.contain, width: _displayW, height: _displayH),
                      ...() {
                        final widgets = <Widget>[];
                        for (int index = 0; index < widget.placements.length; index++) {
                          final placement = widget.placements[index];
                          final isSelected = widget.selectedLocalIndex == index;

                          final relDelta = _dragRelDeltas[index] ?? Offset.zero;
                          final visualX = placement.x + relDelta.dx;
                          final visualY = placement.y + relDelta.dy;

                          final sigWidthPx = _displayW * (placement.width / _pageWidthPt);
                          final sigHeightPx = sigWidthPx / widget.signatureAspectRatio;

                          final left = visualX * _displayW - sigWidthPx / 2;
                          final top = visualY * _displayH - sigHeightPx / 2;

                          final clampedLeft = left.clamp(0.0, _displayW - sigWidthPx);
                          final clampedTop = top.clamp(0.0, _displayH - sigHeightPx);

                          // Marker
                          widgets.add(Positioned(
                            left: clampedLeft,
                            top: clampedTop,
                            child: _EagerPan(
                              onTap: () => widget.onSelect(index),
                              onPanStart: (_) {
                                _dragRelDeltas[index] = Offset.zero;
                              },
                              onPanUpdate: (details) {
                                setState(() {
                                  _dragRelDeltas[index] = (_dragRelDeltas[index] ?? Offset.zero) + Offset(
                                    details.delta.dx / _displayW,
                                    details.delta.dy / _displayH,
                                  );
                                });
                              },
                              onPanEnd: (_) {
                                final finalDelta = _dragRelDeltas.remove(index) ?? Offset.zero;
                                widget.onMovePlacement(
                                  index,
                                  (placement.x + finalDelta.dx).clamp(0.05, 0.95),
                                  (placement.y + finalDelta.dy).clamp(0.05, 0.95),
                                );
                                setState(() {});
                              },
                              child: Transform.rotate(
                                angle: placement.rotation,
                                child: SizedBox(
                                  width: sigWidthPx.clamp(30, _displayW),
                                  height: sigHeightPx.clamp(10, _displayH),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Stem to the rotate handle (visual only).
                                      Positioned(
                                        top: -_rotateStem,
                                        left: sigWidthPx.clamp(30, _displayW) / 2 - 1,
                                        width: 2,
                                        height: _rotateStem,
                                        child: ColoredBox(
                                          color: AppColors.brandRed.withValues(alpha: 0.7),
                                        ),
                                      ),
                                      Container(
                                        width: sigWidthPx.clamp(30, _displayW),
                                        height: sigHeightPx.clamp(10, _displayH),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: isSelected
                                                ? AppColors.brandRed
                                                : AppColors.brandRed.withValues(alpha: 0.55),
                                            width: isSelected ? 2 : 1.2,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(3),
                                          child: Image.memory(
                                            widget.signaturePngBytes,
                                            fit: BoxFit.contain,
                                            width: sigWidthPx.clamp(30, _displayW),
                                            height: sigHeightPx.clamp(10, _displayH),
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          bottom: -14,
                                          left: 0,
                                          right: 0,
                                          child: Center(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.brandRed,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                placement.rotation == 0
                                                    ? '${placement.width.round()}pt'
                                                    : '${placement.width.round()}pt · ${_degrees(placement.rotation)}°',
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ));

                          final boxW = sigWidthPx.clamp(30.0, _displayW);
                          final boxH = sigHeightPx.clamp(10.0, _displayH);
                          final angle = placement.rotation;
                          final cosA = math.cos(angle), sinA = math.sin(angle);
                          final centre = Offset(clampedLeft + boxW / 2, clampedTop + boxH / 2);
                          // Point at [o] from the centre, rotated with the signature.
                          Offset rotated(Offset o) =>
                              centre + Offset(o.dx * cosA - o.dy * sinA, o.dx * sinA + o.dy * cosA);

                          // Delete button on the top-right corner (sibling, not
                          // nested — no gesture conflict with the drag).
                          widgets.add(_cornerControl(
                            center: rotated(Offset(boxW / 2, -boxH / 2)),
                            child: GestureDetector(
                              onTap: () => widget.onDeletePlacement(index),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: const BoxDecoration(
                                  color: AppColors.brandRed,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                              ),
                            ),
                          ));

                          // Resize handles on the other three corners. Width
                          // grows symmetrically because the placement is
                          // anchored at its centre.
                          for (final (corner, sx, sy) in [
                            (rotated(Offset(-boxW / 2, -boxH / 2)), -1.0, -1.0),
                            (rotated(Offset(-boxW / 2, boxH / 2)), -1.0, 1.0),
                            (rotated(Offset(boxW / 2, boxH / 2)), 1.0, 1.0),
                          ]) {
                            widgets.add(_cornerControl(
                              center: corner,
                              child: _EagerPan(
                                onPanUpdate: (details) {
                                  // Each side mirrors the drag (×2), averaged
                                  // over the horizontal and vertical axes (÷2).
                                  // Drag in the signature's own (rotated) axes.
                                  final d = details.delta;
                                  final localDx = d.dx * cosA + d.dy * sinA;
                                  final localDy = -d.dx * sinA + d.dy * cosA;
                                  final growPx = sx * localDx +
                                      sy * localDy * widget.signatureAspectRatio;
                                  final newWidthPt =
                                      placement.width + growPx * (_pageWidthPt / _displayW);
                                  widget.onResizePlacement(index, newWidthPt);
                                },
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.brandRed, width: 2.5),
                                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                                  ),
                                ),
                              ),
                            ));
                          }

                          // Rotate handle above the top edge: drag to rotate
                          // freely (snaps near 0/90/180/270°), tap for +90°.
                          final rotateCenter = rotated(Offset(0, -boxH / 2 - _rotateStem));
                          widgets.add(_cornerControl(
                            center: rotateCenter,
                            child: _EagerPan(
                              onTap: () => widget.onRotatePlacement(index, _snap(angle + math.pi / 2, force: true)),
                              onPanStart: (_) => _rotateDragPos[index] = rotateCenter,
                              onPanUpdate: (details) {
                                final pos = (_rotateDragPos[index] ?? rotateCenter) + details.delta;
                                _rotateDragPos[index] = pos;
                                final a = math.atan2(pos.dy - centre.dy, pos.dx - centre.dx) + math.pi / 2;
                                widget.onRotatePlacement(index, _snap(a));
                              },
                              onPanEnd: (_) => _rotateDragPos.remove(index),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.brandRed, width: 2),
                                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                                ),
                                child: const Icon(Icons.rotate_right_rounded, size: 15, color: AppColors.brandRed),
                              ),
                            ),
                          ));
                        }
                        return widgets;
                      }(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tap + pan detector whose drag wins the gesture arena on touch-down, so
/// dragging a signature or its resize handles never swipes the PageView.
class _EagerPan extends StatelessWidget {
  final VoidCallback? onTap;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final Widget child;

  const _EagerPan({
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        if (onTap != null)
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            TapGestureRecognizer.new,
            (r) => r.onTap = onTap,
          ),
        _EagerPanRecognizer: GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
          _EagerPanRecognizer.new,
          (r) => r
            ..onStart = onPanStart
            ..onUpdate = onPanUpdate
            ..onEnd = onPanEnd,
        ),
      },
      child: child,
    );
  }
}

class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    // Accept as soon as the finger moves at all, before the PageView's
    // horizontal drag recognizer (which needs the full touch slop).
    return globalDistanceMoved.abs() > 1;
  }
}

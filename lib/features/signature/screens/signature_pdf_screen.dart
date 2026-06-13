import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;
import '../services/signature_service.dart';
import '../../pdf/screens/success_screen.dart';

class _PlacedSignature {
  int pageIndex;
  double x;
  double y;
  double width;

  _PlacedSignature({
    required this.pageIndex,
    required this.x,
    required this.y,
    this.width = 200,
  });
}

class SignaturePdfScreen extends StatefulWidget {
  final ui.Image signatureImage;
  final String pdfPath;
  final String outputName;

  const SignaturePdfScreen({
    super.key,
    required this.signatureImage,
    required this.pdfPath,
    required this.outputName,
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
  Uint8List? _signaturePngBytes;

  final List<_PlacedSignature> _placements = [];
  int _selectedLocalIndex = -1;
  double _defaultWidth = 200;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _initSignatureBytes();
    _loadDocument();
  }

  Future<void> _initSignatureBytes() async {
    final byteData = await widget.signatureImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      _signaturePngBytes = byteData.buffer.asUint8List();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _closeDocument();
    super.dispose();
  }

  Future<void> _closeDocument() async {
    if (_document != null) {
      await _document!.close();
      _document = null;
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
        setState(() => _isLoading = false);
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

  void _resizeSelectedWidth(double newWidth) {
    if (_selectedLocalIndex < 0) return;
    final gIndex = _placementIndexOnCurrentPage(_selectedLocalIndex);
    if (gIndex < 0) return;
    setState(() {
      _placements[gIndex].width = newWidth.clamp(60, 500);
    });
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
      )).toList();

      final file = await SignatureService.addSignaturesToPdf(
        sourcePdfPath: widget.pdfPath,
        signatureImage: widget.signatureImage,
        placements: placements,
        outputName: widget.outputName,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: file,
              title: 'PDF Signed Successfully!',
              subtitle: '${placements.length} signature${placements.length > 1 ? 's' : ''} added',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Sign PDF', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _isSaving || _placements.isEmpty ? null : _savePdf,
            icon: Icon(
              Icons.check_circle,
              color: _isSaving || _placements.isEmpty ? Colors.grey : Colors.green,
            ),
            label: Text(
              'Save',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: _isSaving || _placements.isEmpty ? Colors.grey : Colors.green,
              ),
            ),
          ),
        ],
      ),
      body: _isSaving
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(height: 16),
                  Text(
                    'Adding signatures to PDF...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ],
              ),
            )
          : _isLoading || _signaturePngBytes == null
              ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
              : Column(
                  children: [
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
                            signaturePngBytes: _signaturePngBytes!,
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
                          );
                        },
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_placements.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(
                                  _selectedLocalIndex >= 0 ? Icons.touch_app : Icons.zoom_out_map,
                                  size: 16,
                                  color: Colors.deepPurpleAccent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _selectedLocalIndex >= 0 ? 'Selected' : 'Default Size',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: () {
                                      if (_selectedLocalIndex >= 0) {
                                        final gIdx = _placementIndexOnCurrentPage(_selectedLocalIndex);
                                        return gIdx >= 0 ? _placements[gIdx].width : _defaultWidth;
                                      }
                                      return _defaultWidth;
                                    }(),
                                    min: 60,
                                    max: 500,
                                    divisions: 44,
                                    activeColor: Colors.deepPurpleAccent,
                                    onChanged: (v) {
                                      if (_selectedLocalIndex >= 0) {
                                        _resizeSelectedWidth(v);
                                      } else {
                                        setState(() => _defaultWidth = v);
                                      }
                                    },
                                  ),
                                ),
                                Text(
                                  '${() {
                                    if (_selectedLocalIndex >= 0) {
                                      final gIdx = _placementIndexOnCurrentPage(_selectedLocalIndex);
                                      return gIdx >= 0 ? _placements[gIdx].width.round() : _defaultWidth.round();
                                    }
                                    return _defaultWidth.round();
                                  }()}pt',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                              ],
                            ),
                            if (_selectedLocalIndex < 0)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  'Tap a signature on the page to select & resize it',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Page ${_currentPage + 1} of $_pageCount',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                              if (_placements.isNotEmpty) ...[
                                const SizedBox(width: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurpleAccent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_placements.length} sig${_placements.length > 1 ? 's' : ''}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurpleAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 2,
                            ),
                            onPressed: _addSignatureCentered,
                            icon: const Icon(Icons.add),
                            label: const Text(
                              'Add Signature',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _PdfPageWidget extends StatefulWidget {
  final px.PdfDocument document;
  final int pageNumber;
  final Uint8List signaturePngBytes;
  final List<_PlacedSignature> placements;
  final int selectedLocalIndex;
  final void Function(double x, double y) onTap;
  final void Function(int index) onSelect;
  final void Function(int index) onDeletePlacement;
  final void Function(int index, double x, double y) onMovePlacement;

  const _PdfPageWidget({
    required this.document,
    required this.pageNumber,
    required this.signaturePngBytes,
    required this.placements,
    required this.selectedLocalIndex,
    required this.onTap,
    required this.onSelect,
    required this.onDeletePlacement,
    required this.onMovePlacement,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPage || _imageBytes == null) {
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
                    color: Colors.black.withOpacity(0.08),
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
                      Image.memory(_imageBytes!, fit: BoxFit.contain, width: _displayW, height: _displayH),
                      ...() {
                        final widgets = <Widget>[];
                        for (int index = 0; index < widget.placements.length; index++) {
                          final placement = widget.placements[index];
                          final isSelected = widget.selectedLocalIndex == index;

                          final relDelta = _dragRelDeltas[index] ?? Offset.zero;
                          final visualX = placement.x + relDelta.dx;
                          final visualY = placement.y + relDelta.dy;

                          final sigWidthPx = _displayW * (placement.width / _pageWidthPt);
                          final sigHeightPx = sigWidthPx * 0.3;

                          final left = visualX * _displayW - sigWidthPx / 2;
                          final top = visualY * _displayH - sigHeightPx / 2;

                          final clampedLeft = left.clamp(0.0, _displayW - sigWidthPx);
                          final clampedTop = top.clamp(0.0, _displayH - sigHeightPx);

                          // Marker
                          widgets.add(Positioned(
                            left: clampedLeft,
                            top: clampedTop,
                            child: GestureDetector(
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
                              child: SizedBox(
                                width: sigWidthPx.clamp(30, _displayW),
                                height: sigHeightPx.clamp(10, _displayH),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      width: sigWidthPx.clamp(30, _displayW),
                                      height: sigHeightPx.clamp(10, _displayH),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isSelected ? Colors.deepPurpleAccent : Colors.deepPurpleAccent.withOpacity(0.6),
                                          width: isSelected ? 2.5 : 1.5,
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
                                              color: Colors.deepPurpleAccent,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${placement.width.round()}pt',
                                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ));

                          // Delete button (sibling, not nested — no gesture conflict)
                          widgets.add(Positioned(
                            left: (clampedLeft + sigWidthPx - 12).clamp(0.0, _displayW - 24),
                            top: (clampedTop - 10).clamp(0.0, _displayH - 24),
                            child: GestureDetector(
                              onTap: () => widget.onDeletePlacement(index),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 14),
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

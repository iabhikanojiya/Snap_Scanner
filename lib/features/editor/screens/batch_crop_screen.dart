import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/models/scanned_page.dart';
import 'package:snap_scanner/core/theme/app_colors.dart';
import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/editor/screens/batch_filter_screen.dart';
import 'package:snap_scanner/core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/app_dialog.dart';
import '../widgets/page_counter.dart';

/// Crop & rotate every page in place. Edits are kept per page while the user
/// moves between pages and are written to disk in one go on "Next".
class BatchCropScreen extends StatefulWidget {
  const BatchCropScreen({super.key});

  @override
  State<BatchCropScreen> createState() => _BatchCropScreenState();
}

class _BatchCropScreenState extends State<BatchCropScreen> {
  static const Rect _fullRect = Rect.fromLTRB(0, 0, 1, 1);

  int _currentIndex = 0;
  bool _isApplying = false;
  int _appliedCount = 0;
  int _pendingCount = 0;

  /// Clockwise quarter turns per page id.
  final Map<String, int> _turns = {};

  /// Normalised crop rect (0..1, in rotated image space) per page id.
  final Map<String, Rect> _rects = {};

  /// Pixel size of each displayed image, keyed by path.
  final Map<String, Size> _imageSizes = {};

  final ScrollController _thumbController = ScrollController();

  @override
  void dispose() {
    _thumbController.dispose();
    super.dispose();
  }

  int _turnsFor(ScannedPage page) => _turns[page.id] ?? 0;
  Rect _rectFor(ScannedPage page) => _rects[page.id] ?? _fullRect;
  bool _hasEdits(ScannedPage page) => _turnsFor(page) != 0 || _rectFor(page) != _fullRect;

  final Set<String> _loadingSizes = {};

  /// Resolves the pixel size of [file] once and rebuilds when it is known.
  void _ensureSize(File file) {
    if (_imageSizes.containsKey(file.path) || !_loadingSizes.add(file.path)) return;
    final stream = FileImage(file).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        _loadingSizes.remove(file.path);
        if (!mounted) return;
        setState(() {
          _imageSizes[file.path] =
              Size(info.image.width.toDouble(), info.image.height.toDouble());
        });
      },
      onError: (_, _) {
        stream.removeListener(listener);
        _loadingSizes.remove(file.path);
      },
    );
    stream.addListener(listener);
  }

  void _goTo(int index, int total) {
    if (index < 0 || index >= total) return;
    setState(() => _currentIndex = index);
    if (_thumbController.hasClients) {
      const itemExtent = 58.0;
      final target = (index * itemExtent) -
          (_thumbController.position.viewportDimension / 2) +
          itemExtent / 2;
      _thumbController.animateTo(
        target.clamp(0, _thumbController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _rotate(ScannedPage page) {
    setState(() {
      _turns[page.id] = (_turnsFor(page) + 1) % 4;
      // The rect is expressed in rotated space; start fresh after a turn.
      _rects.remove(page.id);
    });
  }

  bool _isDetecting = false;

  Future<void> _autoCrop(ScannedPage page) async {
    if (_isDetecting) return;
    setState(() => _isDetecting = true);
    try {
      final bounds = await ImageUtils.detectDocumentBounds(
        page.displayFile,
        quarterTurns: _turnsFor(page),
      );
      if (!mounted) return;
      if (bounds == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't find the document edges. Adjust the frame manually."),
          ),
        );
        return;
      }
      final (l, t, r, b) = bounds;
      setState(() => _rects[page.id] = Rect.fromLTRB(l, t, r, b));
    } catch (e) {
      debugPrint('Auto crop failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto crop failed. Adjust the frame manually.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  void _reset(ScannedPage page) {
    setState(() {
      _turns.remove(page.id);
      _rects.remove(page.id);
    });
  }

  Future<void> _applyEditsAndContinue() async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (_isApplying) return;
    final edited = provider.pages.where(_hasEdits).toList();

    if (edited.isNotEmpty) {
      setState(() {
        _isApplying = true;
        _appliedCount = 0;
        _pendingCount = edited.length;
      });
      try {
        for (final page in edited) {
          final rect = _rectFor(page);
          final file = await ImageUtils.cropAndRotate(
            page.displayFile,
            quarterTurns: _turnsFor(page),
            left: rect.left,
            top: rect.top,
            right: rect.right,
            bottom: rect.bottom,
          );
          provider.updatePageProcessedFile(page.id, file);
          _turns.remove(page.id);
          _rects.remove(page.id);
          if (mounted) setState(() => _appliedCount++);
        }
      } catch (e) {
        debugPrint('Crop failed: $e');
        if (mounted) {
          setState(() => _isApplying = false);
          _showErrorDialog(context, 'Could not crop the image.\n\nPlease try again.');
        }
        return;
      }
      if (!mounted) return;
      setState(() => _isApplying = false);
    }

    final returnedIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (context) => BatchFilterScreen(initialIndex: _currentIndex),
      ),
    );
    if (returnedIndex != null && mounted) {
      _goTo(returnedIndex, provider.pages.length);
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showAppDialog(
      context: context,
      builder: (ctx) => AppDialog(
        tone: AppDialogTone.error,
        icon: Icons.error_outline_rounded,
        title: 'Image Missing',
        description: message,
        primaryLabel: 'OK',
        onPrimary: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScanProvider>(
      builder: (context, provider, child) {
        if (provider.pages.isEmpty) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text("No images to crop", style: TextStyle(color: Colors.white))),
          );
        }

        final totalPages = provider.pages.length;
        if (_currentIndex >= totalPages) _currentIndex = totalPages - 1;
        final page = provider.pages[_currentIndex];

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            iconTheme: const IconThemeData(color: Colors.white),
            title: PageCounter(current: _currentIndex + 1, total: totalPages),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: _isApplying ? null : _applyEditsAndContinue,
                child: const Text('Next', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    final size = _imageSizes[page.displayFile.path];
                    if (size == null) {
                      _ensureSize(page.displayFile);
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }
                    return _CropEditor(
                      file: page.displayFile,
                      imageSize: size,
                      quarterTurns: _turnsFor(page),
                      rect: _rectFor(page),
                      onChanged: (rect) => setState(() => _rects[page.id] = rect),
                    );
                  },
                ),
              ),
              if (_isDetecting)
                const Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                  ),
                ),
              if (_isApplying)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          'Applying edits $_appliedCount / $_pendingCount',
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1, totalPages) : null,
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            color: _currentIndex > 0 ? Colors.white : Colors.white24),
                      ),
                      Expanded(
                        child: _ToolButton(
                          icon: Icons.auto_fix_high_rounded,
                          label: 'Auto',
                          onTap: _isApplying || _isDetecting ? null : () => _autoCrop(page),
                        ),
                      ),
                      Expanded(
                        child: _ToolButton(
                          icon: Icons.rotate_right_rounded,
                          label: 'Rotate',
                          onTap: _isApplying ? null : () => _rotate(page),
                        ),
                      ),
                      Expanded(
                        child: _ToolButton(
                          icon: Icons.restart_alt_rounded,
                          label: 'Reset',
                          onTap: _isApplying || !_hasEdits(page) ? null : () => _reset(page),
                        ),
                      ),
                      IconButton(
                        onPressed: _currentIndex < totalPages - 1
                            ? () => _goTo(_currentIndex + 1, totalPages)
                            : null,
                        icon: Icon(Icons.arrow_forward_ios_rounded,
                            color: _currentIndex < totalPages - 1 ? Colors.white : Colors.white24),
                      ),
                    ],
                  ),
                ),
                if (totalPages > 1)
                  SizedBox(
                    height: 76,
                    child: ListView.builder(
                      controller: _thumbController,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      itemExtent: 58,
                      itemCount: totalPages,
                      itemBuilder: (context, index) {
                        final p = provider.pages[index];
                        return _PageThumb(
                          file: p.displayFile,
                          quarterTurns: _turnsFor(p),
                          number: index + 1,
                          selected: index == _currentIndex,
                          edited: _hasEdits(p),
                          onTap: () => _goTo(index, totalPages),
                        );
                      },
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: BannerAdWidget(compact: true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? Colors.white38 : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PageThumb extends StatelessWidget {
  final File file;
  final int quarterTurns;
  final int number;
  final bool selected;
  final bool edited;
  final VoidCallback onTap;

  const _PageThumb({
    required this.file,
    required this.quarterTurns,
    required this.number,
    required this.selected,
    required this.edited,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.brandRed : Colors.white24,
                  width: selected ? 2.5 : 1,
                ),
              ),
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: RotatedBox(
                  quarterTurns: quarterTurns,
                  child: Image.file(file, fit: BoxFit.cover, cacheWidth: 120, gaplessPlayback: true),
                ),
              ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$number',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (edited)
              const Positioned(
                right: 4,
                top: 4,
                child: Icon(Icons.edit_rounded, size: 12, color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

/// Image with a draggable crop frame (corners, edges and body).
class _CropEditor extends StatelessWidget {
  final File file;
  final Size imageSize;
  final int quarterTurns;
  final Rect rect;
  final ValueChanged<Rect> onChanged;

  const _CropEditor({
    required this.file,
    required this.imageSize,
    required this.quarterTurns,
    required this.rect,
    required this.onChanged,
  });

  static const double _pad = 28;
  static const double _minSize = 0.1;
  static const double _handle = 44;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rotated = quarterTurns.isOdd
            ? Size(imageSize.height, imageSize.width)
            : imageSize;
        final availW = constraints.maxWidth - _pad * 2;
        final availH = constraints.maxHeight - _pad * 2;
        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();
        final scaleW = availW / rotated.width;
        final scaleH = availH / rotated.height;
        final scale = scaleW < scaleH ? scaleW : scaleH;
        final dw = rotated.width * scale;
        final dh = rotated.height * scale;
        final ox = (constraints.maxWidth - dw) / 2;
        final oy = (constraints.maxHeight - dh) / 2;

        final crop = Rect.fromLTRB(
          ox + rect.left * dw,
          oy + rect.top * dh,
          ox + rect.right * dw,
          oy + rect.bottom * dh,
        );

        void drag(DragUpdateDetails d, {bool l = false, bool t = false, bool r = false, bool b = false}) {
          final dx = d.delta.dx / dw;
          final dy = d.delta.dy / dh;
          var left = rect.left, top = rect.top, right = rect.right, bottom = rect.bottom;
          if (l && t && r && b) {
            final w = right - left, h = bottom - top;
            left = (left + dx).clamp(0.0, 1.0 - w);
            top = (top + dy).clamp(0.0, 1.0 - h);
            right = left + w;
            bottom = top + h;
          } else {
            if (l) left = (left + dx).clamp(0.0, right - _minSize);
            if (r) right = (right + dx).clamp(left + _minSize, 1.0);
            if (t) top = (top + dy).clamp(0.0, bottom - _minSize);
            if (b) bottom = (bottom + dy).clamp(top + _minSize, 1.0);
          }
          onChanged(Rect.fromLTRB(left, top, right, bottom));
        }

        Widget handleAt(Offset center, {bool l = false, bool t = false, bool r = false, bool b = false}) {
          return Positioned(
            left: center.dx - _handle / 2,
            top: center.dy - _handle / 2,
            width: _handle,
            height: _handle,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => drag(d, l: l, t: t, r: r, b: b),
            ),
          );
        }

        return Stack(
          children: [
            Positioned(
              left: ox,
              top: oy,
              width: dw,
              height: dh,
              child: RotatedBox(
                quarterTurns: quarterTurns,
                child: Image.file(file, fit: BoxFit.fill, gaplessPlayback: true),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _CropPainter(crop)),
              ),
            ),
            Positioned.fromRect(
              rect: crop,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) => drag(d, l: true, t: true, r: true, b: true),
              ),
            ),
            handleAt(crop.centerLeft, l: true),
            handleAt(crop.centerRight, r: true),
            handleAt(crop.topCenter, t: true),
            handleAt(crop.bottomCenter, b: true),
            handleAt(crop.topLeft, l: true, t: true),
            handleAt(crop.topRight, r: true, t: true),
            handleAt(crop.bottomLeft, l: true, b: true),
            handleAt(crop.bottomRight, r: true, b: true),
          ],
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect crop;

  _CropPainter(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(crop);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.55));

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3;
      final y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }

    canvas.drawRect(
      crop,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final handle = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const len = 18.0;
    final c = crop;
    // Corner brackets.
    for (final (p, sx, sy) in [
      (c.topLeft, 1.0, 1.0),
      (c.topRight, -1.0, 1.0),
      (c.bottomLeft, 1.0, -1.0),
      (c.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(p, p + Offset(len * sx, 0), handle);
      canvas.drawLine(p, p + Offset(0, len * sy), handle);
    }
    // Edge bars.
    const half = 10.0;
    canvas.drawLine(c.topCenter - const Offset(half, 0), c.topCenter + const Offset(half, 0), handle);
    canvas.drawLine(c.bottomCenter - const Offset(half, 0), c.bottomCenter + const Offset(half, 0), handle);
    canvas.drawLine(c.centerLeft - const Offset(0, half), c.centerLeft + const Offset(0, half), handle);
    canvas.drawLine(c.centerRight - const Offset(0, half), c.centerRight + const Offset(0, half), handle);
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => oldDelegate.crop != crop;
}

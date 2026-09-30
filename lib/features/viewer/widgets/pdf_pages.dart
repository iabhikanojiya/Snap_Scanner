import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;

import '../../../core/theme/app_colors.dart';
import '../services/pdf_annotate_service.dart';

/// Opens a PDF once and renders its pages on demand (each page once).
class PdfPageSource {
  final px.PdfDocument _doc;
  final List<Size> sizes;
  final Map<int, Future<Uint8List?>> _renders = {};

  PdfPageSource._(this._doc, this.sizes);

  static Future<PdfPageSource> open(String path) async {
    final doc = await px.PdfDocument.openFile(path);
    final sizes = <Size>[];
    for (var i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      sizes.add(Size(page.width, page.height));
      await page.close();
    }
    return PdfPageSource._(doc, sizes);
  }

  int get pageCount => sizes.length;

  Future<Uint8List?> render(int index, double width) {
    return _renders.putIfAbsent(index, () async {
      final page = await _doc.getPage(index + 1);
      try {
        final size = sizes[index];
        final image = await page.render(
          width: width,
          height: width * size.height / size.width,
          format: px.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 90,
        );
        return image?.bytes;
      } finally {
        await page.close();
      }
    });
  }

  void dispose() => _doc.close();
}

/// Vertical page list geometry shared by the reader and the editor.
class PdfPagesLayout {
  static const double gap = 12;
  static const double side = 12;

  final List<Size> sizes;
  final double viewportWidth;

  const PdfPagesLayout(this.sizes, this.viewportWidth);

  double get pageWidth => viewportWidth - side * 2;

  double pageHeight(int index) => pageWidth * sizes[index].height / sizes[index].width;

  double offsetOf(int index) {
    var y = gap;
    for (var i = 0; i < index; i++) {
      y += pageHeight(i) + gap;
    }
    return y;
  }

  /// Page under a point [fraction] of the way down the viewport.
  int pageAt(double scrollOffset, double viewportHeight, {double fraction = 0.35}) {
    final probe = scrollOffset + viewportHeight * fraction;
    var y = gap;
    for (var i = 0; i < sizes.length; i++) {
      y += pageHeight(i) + gap;
      if (probe < y) return i;
    }
    return sizes.length - 1;
  }

  double renderWidth(BuildContext context) =>
      (pageWidth * MediaQuery.devicePixelRatioOf(context)).clamp(300.0, 1600.0);
}

/// One rendered page with search-match boxes and highlight strokes on top.
class PdfPageTile extends StatelessWidget {
  final Future<Uint8List?> image;
  final double aspectRatio;
  final List<HighlightStroke> strokes;
  final List<(Rect, bool)> matches;

  /// Text highlights (normalised rect and colour).
  final List<(Rect, Color)> boxes;

  /// Outline around the selected highlight, if any.
  final Rect? outline;

  const PdfPageTile({
    super.key,
    required this.image,
    required this.aspectRatio,
    this.strokes = const [],
    this.matches = const [],
    this.boxes = const [],
    this.outline,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: image,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandRed),
                    ),
                  );
                }
                return Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true);
              },
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: PdfOverlayPainter(strokes: strokes, matches: matches, boxes: boxes, outline: outline),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfOverlayPainter extends CustomPainter {
  final List<HighlightStroke> strokes;
  final List<(Rect, bool)> matches;
  final List<(Rect, Color)> boxes;
  final Rect? outline;

  PdfOverlayPainter({
    required this.strokes,
    required this.matches,
    this.boxes = const [],
    this.outline,
  });

  Rect _scale(Rect r, Size size) =>
      Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    for (final (rect, color) in boxes) {
      canvas.drawRect(
        _scale(rect, size),
        Paint()
          ..color = color.withValues(alpha: PdfAnnotateService.highlightOpacity)
          ..blendMode = BlendMode.multiply,
      );
    }
    for (final (rect, current) in matches) {
      canvas.drawRect(
        Rect.fromLTRB(
          rect.left * size.width - 1,
          rect.top * size.height - 1,
          rect.right * size.width + 1,
          rect.bottom * size.height + 1,
        ),
        Paint()
          ..color = (current ? const Color(0xFFFF8F00) : const Color(0xFFFFD54F))
              .withValues(alpha: current ? 0.55 : 0.4),
      );
    }
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color.withValues(alpha: PdfAnnotateService.highlightOpacity)
        ..strokeWidth = stroke.width * size.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.multiply;
      Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
      if (stroke.points.length == 1) {
        canvas.drawCircle(at(stroke.points.first), paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final first = at(stroke.points.first);
      final path = Path()..moveTo(first.dx, first.dy);
      for (final p in stroke.points.skip(1)) {
        final o = at(p);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, paint..style = PaintingStyle.stroke);
    }
    final outline = this.outline;
    if (outline != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(_scale(outline, size).inflate(4), const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.brandRed,
      );
    }
  }

  @override
  bool shouldRepaint(PdfOverlayPainter oldDelegate) => true;
}

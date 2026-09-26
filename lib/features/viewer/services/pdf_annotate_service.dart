import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// A text match, in normalised page coordinates (0..1, top-left origin).
class PdfTextMatch {
  final int pageIndex;
  final Rect rect;

  const PdfTextMatch(this.pageIndex, this.rect);
}

/// A freehand highlighter stroke on one page, in normalised coordinates.
/// [width] is a fraction of the page width.
class HighlightStroke {
  final int pageIndex;
  final Color color;
  final double width;
  final List<Offset> points;

  HighlightStroke({
    required this.pageIndex,
    required this.color,
    required this.width,
    List<Offset>? points,
  }) : points = points ?? [];
}

/// Text search and highlight burn-in for the in-app viewer (off the UI
/// thread, using the Syncfusion PDF library the app already ships).
class PdfAnnotateService {
  PdfAnnotateService._();

  /// Opacity used both on screen and in the saved PDF.
  static const double highlightOpacity = 0.4;

  static Future<List<PdfTextMatch>> findText(String path, String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final bytes = await File(path).readAsBytes();
    final raw = await compute(_findIsolate, (bytes, q));
    return [for (final m in raw) PdfTextMatch(m.$1, Rect.fromLTRB(m.$2, m.$3, m.$4, m.$5))];
  }

  static List<(int, double, double, double, double)> _findIsolate((Uint8List, String) job) {
    final doc = sf.PdfDocument(inputBytes: job.$1);
    try {
      final items = sf.PdfTextExtractor(doc).findText([job.$2]);
      return [
        for (final item in items)
          () {
            final size = doc.pages[item.pageIndex].size;
            final b = item.bounds;
            return (
              item.pageIndex,
              b.left / size.width,
              b.top / size.height,
              b.right / size.width,
              b.bottom / size.height,
            );
          }(),
      ];
    } finally {
      doc.dispose();
    }
  }

  /// Returns the PDF at [path] with [strokes] drawn in as translucent
  /// highlighter ink.
  static Future<List<int>> applyHighlights(String path, List<HighlightStroke> strokes) async {
    final bytes = await File(path).readAsBytes();
    final data = [
      for (final s in strokes)
        if (s.points.isNotEmpty)
          {
            'page': s.pageIndex,
            'color': s.color.toARGB32(),
            'width': s.width,
            'points': [for (final p in s.points) [p.dx, p.dy]],
          },
    ];
    return compute(_highlightIsolate, (bytes, data));
  }

  static List<int> _highlightIsolate((Uint8List, List<Map<String, Object>>) job) {
    final doc = sf.PdfDocument(inputBytes: job.$1);
    try {
      for (final stroke in job.$2) {
        final pageIndex = (stroke['page']! as int).clamp(0, doc.pages.count - 1);
        final page = doc.pages[pageIndex];
        final size = page.size;
        final argb = stroke['color']! as int;
        final points = (stroke['points']! as List).cast<List<double>>();
        final pen = sf.PdfPen(
          sf.PdfColor((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF),
          width: (stroke['width']! as double) * size.width,
          lineCap: sf.PdfLineCap.round,
          lineJoin: sf.PdfLineJoin.round,
        );
        Offset at(List<double> p) => Offset(p[0] * size.width, p[1] * size.height);

        final graphics = page.graphics;
        final state = graphics.save();
        graphics.setTransparency(highlightOpacity, mode: sf.PdfBlendMode.multiply);
        if (points.length == 1) {
          final c = at(points.first);
          final r = pen.width / 2;
          graphics.drawEllipse(
            Rect.fromCircle(center: c, radius: r),
            brush: sf.PdfSolidBrush(pen.color),
          );
        } else {
          final pdfPath = sf.PdfPath();
          for (var i = 1; i < points.length; i++) {
            pdfPath.addLine(at(points[i - 1]), at(points[i]));
          }
          graphics.drawPath(pdfPath, pen: pen);
        }
        graphics.restore(state);
      }
      return doc.saveSync();
    } finally {
      doc.dispose();
    }
  }
}

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

/// A highlight over text: one box per line, in normalised coordinates.
class HighlightBox {
  final int pageIndex;
  final Color color;
  final Rect rect;

  const HighlightBox({required this.pageIndex, required this.color, required this.rect});
}

/// A word on a page, in normalised coordinates; [line] orders words into
/// lines (reading order), for text-snapped highlighting.
class PdfWord {
  final Rect rect;
  final int line;

  const PdfWord(this.rect, this.line);
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

  /// Words of every page, in reading order (index = page index). Pages
  /// without a text layer (e.g. scans) get an empty list.
  static Future<List<List<PdfWord>>> extractWords(String path, int pageCount) async {
    final bytes = await File(path).readAsBytes();
    final raw = await compute(_wordsIsolate, bytes);
    final pages = List.generate(pageCount, (_) => <PdfWord>[]);
    for (final w in raw) {
      if (w.$1 < pageCount) pages[w.$1].add(PdfWord(Rect.fromLTRB(w.$3, w.$4, w.$5, w.$6), w.$2));
    }
    return pages;
  }

  static List<(int, int, double, double, double, double)> _wordsIsolate(Uint8List bytes) {
    final doc = sf.PdfDocument(inputBytes: bytes);
    try {
      final result = <(int, int, double, double, double, double)>[];
      final lines = sf.PdfTextExtractor(doc).extractTextLines();
      for (var l = 0; l < lines.length; l++) {
        final line = lines[l];
        final size = doc.pages[line.pageIndex].size;
        for (final word in line.wordCollection) {
          if (word.text.trim().isEmpty) continue;
          final b = word.bounds;
          result.add((
            line.pageIndex,
            l,
            b.left / size.width,
            b.top / size.height,
            b.right / size.width,
            b.bottom / size.height,
          ));
        }
      }
      return result;
    } finally {
      doc.dispose();
    }
  }

  /// Returns the PDF at [path] with [strokes] and [boxes] drawn in as
  /// translucent highlighter ink.
  static Future<List<int>> applyHighlights(
    String path,
    List<HighlightStroke> strokes, {
    List<HighlightBox> boxes = const [],
  }) async {
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
      for (final b in boxes)
        {
          'page': b.pageIndex,
          'color': b.color.toARGB32(),
          'rect': [b.rect.left, b.rect.top, b.rect.right, b.rect.bottom],
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
        final box = stroke['rect'] as List<double>?;
        if (box != null) {
          final graphics = page.graphics;
          final state = graphics.save();
          graphics.setTransparency(highlightOpacity, mode: sf.PdfBlendMode.multiply);
          graphics.drawRectangle(
            brush: sf.PdfSolidBrush(sf.PdfColor((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)),
            bounds: Rect.fromLTRB(
              box[0] * size.width,
              box[1] * size.height,
              box[2] * size.width,
              box[3] * size.height,
            ),
          );
          graphics.restore(state);
          continue;
        }
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

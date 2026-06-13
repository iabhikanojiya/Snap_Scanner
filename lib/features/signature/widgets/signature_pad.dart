import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePad extends StatefulWidget {
  final double strokeWidth;
  final Color strokeColor;

  const SignaturePad({
    super.key,
    this.strokeWidth = 3.0,
    this.strokeColor = Colors.black,
  });

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final List<_SignatureStroke> _strokes = [];
  _SignatureStroke? _currentStroke;
  final GlobalKey _boundaryKey = GlobalKey();

  void clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = null;
    });
  }

  bool get hasContent => _strokes.isNotEmpty;

  Future<ui.Image> toImage({double pixelRatio = 3.0}) async {
    final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: pixelRatio);
  }

  Future<ui.Image> renderSignatureOnly({double scale = 3.0}) async {
    final allStrokes = [..._strokes, if (_currentStroke != null) _currentStroke!];
    if (allStrokes.isEmpty) throw Exception('No signature strokes');

    double minX = double.infinity, minY = double.infinity;
    double maxX = 0, maxY = 0;
    for (final stroke in allStrokes) {
      for (final point in stroke.points) {
        if (point.dx < minX) minX = point.dx;
        if (point.dy < minY) minY = point.dy;
        if (point.dx > maxX) maxX = point.dx;
        if (point.dy > maxY) maxY = point.dy;
      }
    }

    const padding = 15.0;
    final w = ((maxX - minX + padding * 2) * scale).ceil();
    final h = ((maxY - minY + padding * 2) * scale).ceil();
    if (w <= 0 || h <= 0) throw Exception('Invalid signature bounds');

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.save();
    canvas.translate(padding * scale, padding * scale);
    canvas.scale(scale);
    canvas.translate(-minX, -minY);

    for (final stroke in allStrokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2, paint);
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    canvas.restore();
    final picture = recorder.endRecording();
    return picture.toImage(w, h);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 250,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(16),
          ),
          child: GestureDetector(
            onPanStart: (details) {
              final stroke = _SignatureStroke(
                points: [details.localPosition],
                color: widget.strokeColor,
                width: widget.strokeWidth,
              );
              setState(() {
                _currentStroke = stroke;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _currentStroke?.points.add(details.localPosition);
              });
            },
            onPanEnd: (_) {
              setState(() {
                if (_currentStroke != null) {
                  _strokes.add(_currentStroke!);
                  _currentStroke = null;
                }
              });
            },
            child: CustomPaint(
              painter: _SignaturePainter(
                strokes: _strokes,
                currentStroke: _currentStroke,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _SignatureStroke {
  final List<Offset> points;
  final Color color;
  final double width;

  _SignatureStroke({
    required this.points,
    required this.color,
    required this.width,
  });
}

class _SignaturePainter extends CustomPainter {
  final List<_SignatureStroke> strokes;
  final _SignatureStroke? currentStroke;

  _SignaturePainter({required this.strokes, this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, _SignatureStroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (stroke.points.length == 1) {
      canvas.drawCircle(stroke.points.first, stroke.width / 2, paint);
      return;
    }

    final path = Path();
    path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
    for (int i = 1; i < stroke.points.length; i++) {
      path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SignaturePainter oldDelegate) => true;
}

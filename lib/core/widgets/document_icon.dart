import 'package:flutter/material.dart';

/// Flat document-style icon: a solid page with a folded corner and a white
/// glyph, sitting on a soft tinted rounded square. Used for tool icons on the
/// Tools screen and the tool screens' "Select PDF" states.
class DocumentIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  /// Outer tile size; every other dimension scales from it.
  final double size;

  /// Draws the soft tinted square behind the page. Turn off when the parent
  /// already uses the tint as its background.
  final bool showBackground;

  const DocumentIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 48,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final scale = size / 48;
    final pageWidth = 26 * scale;
    final pageHeight = 32 * scale;
    return Container(
      width: size,
      height: size,
      decoration: showBackground
          ? BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14 * scale),
            )
          : null,
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(pageWidth, pageHeight),
        painter: _DocumentPainter(color, scale),
        child: SizedBox(
          width: pageWidth,
          height: pageHeight,
          child: Padding(
            padding: EdgeInsets.only(top: 6 * scale),
            child: Icon(icon, color: Colors.white, size: 15 * scale),
          ),
        ),
      ),
    );
  }
}

class _DocumentPainter extends CustomPainter {
  final Color color;
  final double scale;

  const _DocumentPainter(this.color, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fold = 8 * scale;
    final radius = 3 * scale;
    final curl = 1.5 * scale;

    final page = Path()
      ..moveTo(radius, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h - radius)
      ..quadraticBezierTo(w, h, w - radius, h)
      ..lineTo(radius, h)
      ..quadraticBezierTo(0, h, 0, h - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();
    canvas.drawPath(page, Paint()..color = color);

    final corner = Path()
      ..moveTo(w - fold, 0)
      ..lineTo(w - fold, fold - curl)
      ..quadraticBezierTo(w - fold, fold, w - fold + curl, fold)
      ..lineTo(w, fold)
      ..close();
    canvas.drawPath(corner, Paint()..color = Colors.white.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(_DocumentPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.scale != scale;
}

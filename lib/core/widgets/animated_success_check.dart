import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated success badge: a ring draws in, the disc fills with a soft green
/// gradient and pops, a white check mark strokes in, then a ripple and a
/// small burst of dots fade out. After the first run it repeats every
/// [repeatDelay] with the badge staying visible (pop, check, burst).
class AnimatedSuccessCheck extends StatefulWidget {
  final double size;
  final Color color;

  /// Pause between loops; null plays once.
  final Duration? repeatDelay;

  const AnimatedSuccessCheck({
    super.key,
    this.size = 96,
    this.color = const Color(0xFF16A34A),
    this.repeatDelay = const Duration(milliseconds: 1500),
  });

  @override
  State<AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  /// Where replays start: ring already drawn, disc mid-pop, check not yet
  /// drawn (see the phase windows in the painter).
  static const double _replayFrom = 0.45;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )
    ..addStatusListener(_onStatus)
    ..forward();

  Timer? _repeatTimer;

  void _onStatus(AnimationStatus status) {
    final delay = widget.repeatDelay;
    if (status != AnimationStatus.completed || delay == null) return;
    _repeatTimer?.cancel();
    _repeatTimer = Timer(delay, () {
      if (mounted) _controller.forward(from: _replayFrom);
    });
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Success',
      child: SizedBox(
        // Extra room around the badge for the ripple and dot burst.
        width: widget.size * 1.6,
        height: widget.size * 1.6,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SuccessCheckPainter(
              t: _controller.value,
              color: widget.color,
              radius: widget.size / 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessCheckPainter extends CustomPainter {
  final double t;
  final Color color;
  final double radius;

  _SuccessCheckPainter({required this.t, required this.color, required this.radius});

  /// Maps [t] into 0..1 over the [start, end] window.
  double _phase(double start, double end, [Curve curve = Curves.linear]) {
    final v = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);

    // 1. Ring sweeps in.
    final ring = _phase(0.0, 0.35, Curves.easeInOut);
    // 2. Disc fills and pops (slight overshoot).
    final fill = _phase(0.25, 0.55, Curves.easeOutBack);
    // 3. Check mark strokes in.
    final check = _phase(0.5, 0.8, Curves.easeOutCubic);
    // 4. Ripple + dot burst.
    final burst = _phase(0.6, 1.0, Curves.easeOut);

    // Ripple ring.
    if (burst > 0 && burst < 1) {
      canvas.drawCircle(
        center,
        radius * (1 + 0.45 * burst),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - burst)
          ..color = color.withValues(alpha: 0.35 * (1 - burst)),
      );
    }

    // Dot burst.
    if (burst > 0 && burst < 1) {
      final dotPaint = Paint()..color = color.withValues(alpha: 1 - burst);
      for (var i = 0; i < 8; i++) {
        final angle = -math.pi / 2 + i * math.pi / 4;
        final dist = radius * (1.05 + 0.4 * burst);
        final dotRadius = (i.isEven ? 3.5 : 2.5) * (1 - burst * 0.6);
        canvas.drawCircle(
          center + Offset(math.cos(angle), math.sin(angle)) * dist,
          dotRadius,
          dotPaint,
        );
      }
    }

    // Soft halo behind the disc.
    canvas.drawCircle(
      center,
      radius * 1.12,
      // Mint halo (tint over white) so it stays fresh on any background.
      Paint()
        ..color = Color.alphaBlend(color.withValues(alpha: 0.14), Colors.white)
            .withValues(alpha: 0.9 * ring),
    );

    // Ring stroke.
    if (ring > 0 && fill < 1) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 2),
        -math.pi / 2,
        2 * math.pi * ring,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }

    // Filled disc with a gentle top-left highlight.
    if (fill > 0) {
      final r = radius * fill;
      final light = Color.lerp(color, Colors.white, 0.25)!;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [light, color],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }

    // Check mark.
    if (check > 0) {
      final path = Path()
        ..moveTo(center.dx - radius * 0.38, center.dy + radius * 0.02)
        ..lineTo(center.dx - radius * 0.1, center.dy + radius * 0.3)
        ..lineTo(center.dx + radius * 0.42, center.dy - radius * 0.28);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * check),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_SuccessCheckPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color || oldDelegate.radius != radius;
}

import 'package:flutter/material.dart';

/// Docked tool capsule shared by the PDF viewer and editor: a rounded dark
/// pill on a black bar, respecting the bottom safe area. Scrolls
/// horizontally when the items don't fit (narrow phones).
class PdfToolCapsule extends StatelessWidget {
  final List<Widget> children;

  const PdfToolCapsule({super.key, required this.children});

  /// Equal item width for [count] items; shrinks a little on narrow phones.
  static double itemWidth(BuildContext context, int count) =>
      ((MediaQuery.sizeOf(context).width - 56) / count).clamp(58.0, 74.0);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Center(
            // heightFactor: 1 keeps the bar as tall as the capsule; a plain
            // Center here would fill the whole screen height.
            heightFactor: 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF26282D),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-width item in the docked tool capsule.
class PdfCapsuleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? activeColor;
  final VoidCallback onTap;
  final double width;

  const PdfCapsuleItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.width,
    this.active = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: active,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: Colors.white),
                  if (active && activeColor != null)
                    Positioned(
                      right: -6,
                      bottom: -3,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: activeColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF26282D), width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

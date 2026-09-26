import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'document_icon.dart';

/// Compact tool shortcut (tinted card + document icon + label), used in rows
/// of 2–3 shortcuts, e.g. the PDF actions popup and the success screen.
/// Place inside a Row; it expands to share the width.
class ToolShortcutCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const ToolShortcutCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DocumentIcon(icon: icon, color: color, size: 40, showBackground: false),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/pdf_file_model.dart';
import '../../../core/theme/app_colors.dart';
import '../pdf_file_actions.dart';
import 'pdf_thumbnail.dart';

class PdfListItem extends StatelessWidget {
  final PdfFileModel file;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Null outside selection mode; otherwise whether this file is selected.
  final bool? selected;

  const PdfListItem({
    super.key,
    required this.file,
    required this.onTap,
    this.onLongPress,
    this.selected,
  });

  static String _toolLabel(String toolType) {
    for (final option in PdfFileActions.filterOptions) {
      if (option.$2 == toolType) return option.$1;
    }
    return 'SnapScanner';
  }

  @override
  Widget build(BuildContext context) {
    final selected = this.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected == true ? AppColors.brandRed.withValues(alpha: 0.06) : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: selected == true
              ? const BorderSide(color: AppColors.brandRed, width: 1.5)
              : const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                PdfThumbnail(file: file),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _toolLabel(file.toolType),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${PdfFileActions.formatSize(file.size)} • ${DateFormat('MMM dd, yyyy').format(file.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected == null)
                  IconButton(
                    tooltip: 'More',
                    onPressed: onTap,
                    icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                  )
                else
                  IconButton(
                    tooltip: selected ? 'Deselect' : 'Select',
                    onPressed: onTap,
                    icon: Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? AppColors.brandRed : AppColors.textSecondary,
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

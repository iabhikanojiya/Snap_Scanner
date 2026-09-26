import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/models/pdf_file_model.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/database_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/tool_shortcut_card.dart';
import '../compress/screens/pdf_compress_screen.dart';
import '../home/tool_actions.dart';
import '../lock/screens/pdf_lock_screen.dart';

class PdfFileExtraAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const PdfFileExtraAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

/// File actions and labels shared by History, My PDFs and folder views
/// (moved out of HistoryScreen so every list behaves the same way).
class PdfFileActions {
  PdfFileActions._();

  static const filterOptions = [
    ('All', 'all'),
    ('Scan PDF', 'scan_pdf'),
    ('Image to PDF', 'image_to_pdf'),
    ('Merge PDF', 'merge_pdf'),
    ('Split PDF', 'split_pdf'),
    ('Compress PDF', 'compress_pdf'),
    ('Lock PDF', 'lock_pdf'),
    ('Signature', 'signature_pdf'),
    ('Resize Image', 'resize_image'),
  ];

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String formatToolType(String toolType) {
    switch (toolType) {
      case 'scan_pdf':
        return 'Created with Scan PDF';
      case 'image_to_pdf':
        return 'Created with Image to PDF';
      case 'merge_pdf':
        return 'Created with Merge PDF';
      case 'split_pdf':
        return 'Created with Split PDF';
      case 'compress_pdf':
        return 'Created with Compress PDF';
      case 'lock_pdf':
        return 'Created with Lock PDF';
      case 'signature_pdf':
        return 'Created with Signature';
      case 'resize_image':
        return 'Created with Resize Image';
      case 'imported':
        return 'Imported';
      case 'highlight_pdf':
        return 'Highlighted';
      default:
        return 'Created with SnapScanner';
    }
  }

  static void showFileActions(
    BuildContext context,
    PdfFileModel file, {
    required VoidCallback onChanged,
    List<PdfFileExtraAction> extraActions = const [],
  }) {
    showAppDialog(
      context: context,
      builder: (sheetContext) => AppDialog(
        title: file.name,
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(sheetContext),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ToolShortcutCard(
                  icon: Icons.draw_outlined,
                  color: AppColors.toolSignature,
                  label: 'Add Sign',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ToolActions.openSignature(context, pdfPath: file.path);
                  },
                ),
                const SizedBox(width: 8),
                ToolShortcutCard(
                  icon: Icons.compress_rounded,
                  color: AppColors.toolCompress,
                  label: 'Compress PDF',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfCompressScreen(initialPdfPath: file.path),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                ToolShortcutCard(
                  icon: Icons.lock_outline_rounded,
                  color: AppColors.toolLock,
                  label: 'Lock PDF',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfLockScreen(initialPdfPath: file.path),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppDialogOption(
              icon: Icons.open_in_new,
              label: 'Open',
              onTap: () async {
                Navigator.pop(sheetContext);
                await OpenFilex.open(file.path);
              },
            ),
            AppDialogOption(
              icon: Icons.share,
              label: 'Share',
              onTap: () async {
                Navigator.pop(sheetContext);
                AnalyticsService.instance.logPdfShared();
                await Share.shareXFiles([XFile(file.path)]);
              },
            ),
            AppDialogOption(
              icon: Icons.download,
              label: 'Download',
              onTap: () async {
                Navigator.pop(sheetContext);
                try {
                  final sourceFile = File(file.path);
                  final bytes = await sourceFile.readAsBytes();
                  final outputPath = await FilePicker.saveFile(
                    dialogTitle: 'Download PDF',
                    fileName: file.name,
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    bytes: bytes,
                  );
                  if (outputPath != null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File downloaded successfully!')),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error downloading file: $e')),
                    );
                  }
                }
              },
            ),
            AppDialogOption(
              icon: Icons.edit,
              label: 'Rename',
              onTap: () async {
                Navigator.pop(sheetContext);
                showRenameDialog(context, file, onChanged: onChanged);
              },
            ),
            for (final action in extraActions)
              AppDialogOption(
                icon: action.icon,
                label: action.label,
                onTap: () {
                  Navigator.pop(sheetContext);
                  action.onTap();
                },
              ),
            AppDialogOption(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
              onTap: () async {
                Navigator.pop(sheetContext);
                showDeleteConfirmation(context, file, onChanged: onChanged);
              },
            ),
          ],
        ),
      ),
    );
  }

  static void showRenameDialog(
    BuildContext context,
    PdfFileModel file, {
    required VoidCallback onChanged,
  }) {
    final controller = TextEditingController(text: file.name.replaceAll('.pdf', ''));
    showAppDialog(
      context: context,
      builder: (dialogContext) => AppDialog(
        icon: Icons.edit_outlined,
        title: 'Rename File',
        content: TextField(
          controller: controller,
          decoration: AppDialog.inputDecoration(suffixText: '.pdf'),
          autofocus: true,
        ),
        primaryLabel: 'Rename',
        onPrimary: () async {
          final newName = controller.text.trim();
          if (newName.isNotEmpty) {
            final newPath = await StorageService.renameFile(file.path, newName);
            await DatabaseService.updateFileMetadata(file.id, newName, newPath);
            if (dialogContext.mounted) {
              Navigator.pop(dialogContext);
              onChanged();
            }
          }
        },
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(dialogContext),
      ),
    );
  }

  static void showDeleteConfirmation(
    BuildContext context,
    PdfFileModel file, {
    required VoidCallback onChanged,
  }) {
    showAppDialog(
      context: context,
      builder: (dialogContext) => AppDialog(
        tone: AppDialogTone.destructive,
        icon: Icons.delete_outline_rounded,
        title: 'Delete File',
        description: 'Are you sure you want to delete "${file.name}"?',
        primaryLabel: 'Delete',
        onPrimary: () async {
          await StorageService.deleteFile(file.path);
          await DatabaseService.deleteFile(file.id);
          AnalyticsService.instance.logPdfDeleted();
          if (dialogContext.mounted) {
            Navigator.pop(dialogContext);
            onChanged();
          }
        },
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(dialogContext),
      ),
    );
  }
}

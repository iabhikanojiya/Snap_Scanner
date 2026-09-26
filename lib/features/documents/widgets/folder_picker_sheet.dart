import 'package:flutter/material.dart';

import '../../../core/models/folder_model.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/folder_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';

/// Asks for a folder name and creates it. Returns null if cancelled.
Future<FolderModel?> showCreateFolderDialog(BuildContext context) {
  return showAppDialog<FolderModel>(
    context: context,
    builder: (_) => const _CreateFolderDialog(),
  );
}

/// Lets the user pick (or create) a folder, then adds or moves [file] there.
Future<void> showFolderPicker(
  BuildContext context, {
  required PdfFileModel file,
  required bool move,
  required VoidCallback onDone,
}) async {
  final folder = await showAppDialog<FolderModel>(
    context: context,
    builder: (_) => _FolderPickerSheet(file: file, move: move),
  );
  if (folder == null) return;
  try {
    if (move) {
      await FolderService.moveFileToFolder(file.id, folder.id);
    } else {
      await FolderService.addFileToFolder(file.id, folder.id);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${move ? 'Moved' : 'Added'} to "${folder.name}"')),
      );
    }
  } catch (e) {
    debugPrint('[Folders] ${move ? 'move' : 'add'} failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update folder. Please try again.')),
      );
    }
  }
  onDone();
}

class _FolderPickerSheet extends StatefulWidget {
  final PdfFileModel file;
  final bool move;

  const _FolderPickerSheet({required this.file, required this.move});

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  late final Future<List<FolderModel>> _foldersFuture = FolderService.getFolders();

  Future<void> _createFolder() async {
    final folder = await showCreateFolderDialog(context);
    if (folder != null && mounted) Navigator.pop(context, folder);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.folder_outlined,
      title: widget.move ? 'Move to folder' : 'Add to folder',
      description: widget.file.name,
      content: FutureBuilder<List<FolderModel>>(
        future: _foldersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final folders = snapshot.data ?? const <FolderModel>[];
          if (folders.isEmpty) {
            return const Text(
              'No folders yet. Create one below.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final folder in folders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0xFFF6F7F9),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      leading: _leadingIcon(Icons.folder_rounded),
                      title: Text(
                        folder.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        folder.fileCount == 1 ? '1 file' : '${folder.fileCount} files',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.textSecondary),
                      onTap: () => Navigator.pop(context, folder),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      primaryLabel: 'Create folder',
      onPrimary: _createFolder,
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.pop(context),
    );
  }

  Widget _leadingIcon(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.brandRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.brandRed, size: 22),
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a folder name');
      return;
    }
    setState(() => _saving = true);
    try {
      final folder = await FolderService.createFolder(name);
      if (!mounted) return;
      if (folder == null) {
        setState(() {
          _saving = false;
          _error = 'A folder with this name already exists';
        });
        return;
      }
      Navigator.pop(context, folder);
    } catch (e) {
      debugPrint('[Folders] create failed: $e');
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not create folder. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.create_new_folder_outlined,
      title: 'New Folder',
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: AppDialog.inputDecoration(
          hintText: 'Folder name',
          errorText: _error,
        ),
      ),
      primaryLabel: 'Create',
      onPrimary: _saving ? null : _submit,
      secondaryLabel: 'Cancel',
      onSecondary: _saving ? null : () => Navigator.pop(context),
    );
  }
}

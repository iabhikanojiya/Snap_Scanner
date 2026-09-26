import 'package:flutter/material.dart';

import '../../../core/models/folder_model.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/folder_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/blue_header.dart';
import '../pdf_file_actions.dart';
import '../widgets/folder_picker_sheet.dart';
import '../widgets/pdf_list_item.dart';

/// PDFs in one folder. A null [folder] shows every PDF ("All PDFs").
class FolderDetailScreen extends StatefulWidget {
  final FolderModel? folder;

  const FolderDetailScreen({super.key, required this.folder});

  @override
  State<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends State<FolderDetailScreen> {
  List<PdfFileModel> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final folder = widget.folder;
      final files = folder == null
          ? await DatabaseService.getAllFiles()
          : await FolderService.getFilesInFolder(folder.id);
      if (!mounted) return;
      setState(() {
        _files = files;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[FolderDetail] load failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showFileActions(PdfFileModel file) async {
    final folder = widget.folder;
    // Files listed inside a folder are in a folder by definition; the
    // "All PDFs" view needs a lookup.
    var inFolder = folder != null;
    if (!inFolder) {
      try {
        inFolder = await FolderService.isFileInAnyFolder(file.id);
      } catch (e) {
        debugPrint('[FolderDetail] folder lookup failed: $e');
      }
      if (!mounted) return;
    }
    PdfFileActions.showFileActions(
      context,
      file,
      onChanged: _load,
      extraActions: [
        if (inFolder)
          PdfFileExtraAction(
            icon: Icons.drive_file_move_outline,
            label: 'Move to folder',
            onTap: () => showFolderPicker(context, file: file, move: true, onDone: _load),
          )
        else
          PdfFileExtraAction(
            icon: Icons.create_new_folder_outlined,
            label: 'Add to folder',
            onTap: () => showFolderPicker(context, file: file, move: false, onDone: _load),
          ),
        if (folder != null)
          PdfFileExtraAction(
            icon: Icons.folder_off_outlined,
            label: 'Remove from folder',
            onTap: () async {
              await FolderService.removeFileFromFolder(file.id, folder.id);
              _load();
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _files.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          BlueHeader(
            title: widget.folder?.name ?? 'All PDFs',
            subtitle: _isLoading ? null : (count == 1 ? '1 file' : '$count files'),
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F2F4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.folder_open_rounded, size: 48, color: Color(0xFFA0A6B1)),
              ),
              const SizedBox(height: 20),
              const Text(
                'This folder is empty',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Add PDFs from My PDFs using "Add to folder"',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return PdfListItem(
          key: ValueKey(file.id),
          file: file,
          onTap: () => _showFileActions(file),
        );
      },
    );
  }
}

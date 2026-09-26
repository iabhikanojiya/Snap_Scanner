import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';
import '../services/pdf_merge_service.dart';
import '../../lock/services/pdf_lock_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/document_icon.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tool_ui.dart';

class PdfMergeScreen extends StatefulWidget {
  /// PDFs to start the merge list with (e.g. the file just created).
  final List<String> initialPdfPaths;

  const PdfMergeScreen({super.key, this.initialPdfPaths = const []});

  @override
  State<PdfMergeScreen> createState() => _PdfMergeScreenState();
}

class _PdfMergeScreenState extends State<PdfMergeScreen> {
  final List<File> _selectedFiles = [];
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Merged_${DateTime.now().millisecondsSinceEpoch}');
    _selectedFiles.addAll(widget.initialPdfPaths.map(File.new));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final newFiles = <File>[];
        for (final picked in result.files) {
          final file = File(picked.path!);
          final locked = await PdfLockService.isPdfLocked(file.path);
          if (locked) {
            if (mounted) {
              await showAppDialog(
                context: context,
                builder: (ctx) => AppDialog(
                  tone: AppDialogTone.warning,
                  icon: Icons.lock_outline_rounded,
                  title: 'Locked PDF Selected',
                  description:
                      'The file "${file.path.split('/').last}" is '
                      'password-protected and cannot be merged.\n\n'
                      'Please select a PDF that is not locked.',
                  primaryLabel: 'OK',
                  onPrimary: () => Navigator.pop(ctx),
                ),
              );
            }
          } else {
            newFiles.add(file);
          }
        }
        if (newFiles.isNotEmpty) {
          setState(() {
            _selectedFiles.addAll(newFiles);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking files: $e')),
        );
      }
    }
  }

  void _removeFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _reorderFiles(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final file = _selectedFiles.removeAt(oldIndex);
      _selectedFiles.insert(newIndex, file);
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _mergeFiles() async {
    if (_selectedFiles.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 PDF files to merge.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final outputName = _nameController.text.trim();
      final filePaths = _selectedFiles.map((file) => file.path).toList();

      final mergedFile = await PdfMergeService.mergePdfs(
        filePaths: filePaths,
        outputName: outputName,
      );

      AnalyticsService.instance.logPdfSaved();
      AnalyticsService.instance.logMergePdf();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: mergedFile,
              shortcuts: const [
                SuccessShortcut.splitPdf,
                SuccessShortcut.signPdf,
                SuccessShortcut.lockPdf,
                SuccessShortcut.compressPdf,
              ],
            ),
          ),
        );
      }
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'merge_failed',
        message: e.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to merge PDFs: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_isProcessing && _selectedFiles.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Merge PDFs'),
      body: _isProcessing
          ? const ToolProcessingView(message: 'Merging your PDFs...')
          : _selectedFiles.isEmpty
              ? _buildEmptyState()
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                        child: ToolSectionCard(
                          title: 'File name',
                          child: TextFormField(
                            controller: _nameController,
                            decoration: toolInputDecoration(
                              hint: 'Merged file name',
                              icon: Icons.edit_document,
                              suffixText: '.pdf',
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter a filename';
                              }
                              return null;
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Selected PDFs (${_selectedFiles.length})', style: toolSectionTitleStyle),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Drag to change the order',
                                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _pickFiles,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.brandRed,
                                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              icon: const Icon(Icons.add_rounded, size: 20),
                              label: const Text('Add More'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          onReorder: _reorderFiles,
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                          itemCount: _selectedFiles.length,
                          itemBuilder: (context, index) {
                            final file = _selectedFiles[index];
                            final fileName = file.path.split('/').last;
                            final size = file.existsSync() ? file.lengthSync() : 0;
                            return Container(
                              key: ValueKey(file.path + index.toString()),
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                                leading: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const DocumentIcon(
                                      icon: Icons.picture_as_pdf_rounded,
                                      color: AppColors.toolMerge,
                                      size: 42,
                                    ),
                                    Positioned(
                                      left: -4,
                                      top: -4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.textPrimary,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  fileName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _formatSize(size),
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Remove',
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textSecondary),
                                      onPressed: () => _removeFile(index),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Icon(Icons.drag_indicator_rounded, color: AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: ready
          ? ToolBottomBar(
              child: ToolPrimaryButton(
                label: 'Merge PDFs',
                icon: Icons.merge_type_rounded,
                onPressed: _mergeFiles,
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return ToolEmptyWithAd(
      empty: ToolEmptyState(
        icon: Icons.merge_type_rounded,
        color: AppColors.toolMerge,
        title: 'Select PDFs to Merge',
        message: 'Choose two or more PDF files from your device storage to merge them offline.',
        buttonLabel: 'Select Files',
        buttonIcon: Icons.add_to_photos_rounded,
        onPressed: _pickFiles,
      ),
      ad: const NativeAdWidget(),
    );
  }
}

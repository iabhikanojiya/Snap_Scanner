import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';
import '../services/pdf_compress_service.dart';
import '../../lock/services/pdf_lock_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tool_ui.dart';

class PdfCompressScreen extends StatefulWidget {
  /// Opens the screen with this PDF already selected (skips the picker).
  final String? initialPdfPath;

  const PdfCompressScreen({super.key, this.initialPdfPath});

  @override
  State<PdfCompressScreen> createState() => _PdfCompressScreenState();
}

class _PdfCompressScreenState extends State<PdfCompressScreen> {
  File? _selectedFile;
  int _originalSize = 0;
  PdfCompressQuality _selectedQuality = PdfCompressQuality.medium;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialPdfPath;
    if (initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialFile(initialPath));
    }
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        await _useFile(File(result.files.first.path!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  Future<void> _openInitialFile(String path) async {
    try {
      await _useFile(File(path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: $e')),
        );
      }
    }
  }

  Future<void> _useFile(File file) async {
    if (await PdfLockService.isPdfLocked(file.path)) {
      if (mounted) {
        await showAppDialog(
          context: context,
          builder: (ctx) => AppDialog(
            tone: AppDialogTone.warning,
            icon: Icons.lock_outline_rounded,
            title: 'Locked PDF Selected',
            description:
                'The file "${file.path.split('/').last}" is '
                'password-protected and cannot be compressed.\n\n'
                'Please select a PDF that is not locked.',
            primaryLabel: 'OK',
            onPrimary: () => Navigator.pop(ctx),
          ),
        );
      }
      return;
    }

    final size = await file.length();

    setState(() {
      _selectedFile = file;
      _originalSize = size;
      _nameController.text = '${file.path.split('/').last.replaceAll('.pdf', '')}_compressed';
    });
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _compressPdf() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF file to compress.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final outputName = _nameController.text.trim();

      final compressedFile = await PdfCompressService.compressPdf(
        sourcePath: _selectedFile!.path,
        quality: _selectedQuality,
        outputName: outputName,
      );

      AnalyticsService.instance.logPdfSaved();
      AnalyticsService.instance.logCompressPdf();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: compressedFile,
              shortcuts: const [
                SuccessShortcut.mergePdf,
                SuccessShortcut.splitPdf,
                SuccessShortcut.lockPdf,
                SuccessShortcut.resizeImage,
              ],
            ),
          ),
        );
      }
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'compress_failed',
        message: e.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to compress PDF: $e')),
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
    final ready = !_isProcessing && _selectedFile != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Compress PDF'),
      body: _isProcessing
          ? const ToolProcessingView(message: 'Compressing your PDF...')
          : _selectedFile == null
              ? _buildEmptyState()
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      SelectedFileCard(
                        icon: Icons.compress_rounded,
                        color: AppColors.toolCompress,
                        name: _selectedFile!.path.split('/').last,
                        meta: _formatSize(_originalSize),
                        onChange: _pickFile,
                      ),
                      const SizedBox(height: 16),
                      ToolSectionCard(
                        title: 'File name',
                        child: TextFormField(
                          controller: _nameController,
                          decoration: toolInputDecoration(
                            hint: 'Compressed file name',
                            icon: Icons.edit_document,
                            suffixText: '.pdf',
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a name';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 10),
                        child: Text('Compression level', style: toolSectionTitleStyle),
                      ),
                      _buildQualityCard(
                        quality: PdfCompressQuality.high,
                        title: 'High Quality',
                        subtitle: 'Slight compression, preserves maximum detail',
                        estimation: 'Est. 10% - 30% reduction',
                        icon: Icons.high_quality_rounded,
                        color: const Color(0xFF16A34A),
                      ),
                      const SizedBox(height: 10),
                      _buildQualityCard(
                        quality: PdfCompressQuality.medium,
                        title: 'Medium Compression',
                        subtitle: 'Balanced file size and quality',
                        estimation: 'Est. 40% - 60% reduction',
                        icon: Icons.speed_rounded,
                        color: const Color(0xFFEA580C),
                      ),
                      const SizedBox(height: 10),
                      _buildQualityCard(
                        quality: PdfCompressQuality.low,
                        title: 'Maximum Compression',
                        subtitle: 'Smallest file size, lower image resolution',
                        estimation: 'Est. 70% - 80% reduction',
                        icon: Icons.compress_rounded,
                        color: AppColors.toolCompress,
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: ready
          ? ToolBottomBar(
              child: ToolPrimaryButton(
                label: 'Compress PDF',
                icon: Icons.compress_rounded,
                onPressed: _compressPdf,
              ),
            )
          : null,
    );
  }

  Widget _buildQualityCard({
    required PdfCompressQuality quality,
    required String title,
    required String subtitle,
    required String estimation,
    required IconData icon,
    required Color color,
  }) {
    return ToolOptionTile(
      selected: _selectedQuality == quality,
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      tag: estimation,
      onTap: () => setState(() => _selectedQuality = quality),
    );
  }

  Widget _buildEmptyState() {
    return ToolEmptyWithAd(
      empty: ToolEmptyState(
        icon: Icons.compress_rounded,
        color: AppColors.toolCompress,
        title: 'Select PDF to Compress',
        message: 'Choose a PDF file from your device storage to optimize images and compress the file size offline.',
        buttonLabel: 'Select PDF',
        buttonIcon: Icons.picture_as_pdf_rounded,
        onPressed: _pickFile,
      ),
      ad: const NativeAdWidget(),
    );
  }
}

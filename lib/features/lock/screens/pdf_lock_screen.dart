import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';
import '../services/pdf_lock_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tool_ui.dart';

class PdfLockScreen extends StatefulWidget {
  /// Opens the screen with this PDF already selected (skips the picker).
  final String? initialPdfPath;

  const PdfLockScreen({super.key, this.initialPdfPath});

  @override
  State<PdfLockScreen> createState() => _PdfLockScreenState();
}

class _PdfLockScreenState extends State<PdfLockScreen> {
  File? _selectedFile;
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _passwordController;
  late TextEditingController _confirmPasswordController;
  bool _isProcessing = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialPdfPath;
    if (initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialFile(initialPath));
    }
    _nameController = TextEditingController();
    _passwordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
                'already password-protected.\n\n'
                'Please select a PDF that is not locked.',
            primaryLabel: 'OK',
            onPrimary: () => Navigator.pop(ctx),
          ),
        );
      }
      return;
    }

    setState(() {
      _selectedFile = file;
      _nameController.text = '${file.path.split('/').last.replaceAll('.pdf', '')}_locked';
    });
  }

  Future<void> _lockPdf() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a PDF file to lock.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final outputName = _nameController.text.trim();

      final lockedFile = await PdfLockService.lockPdf(
        sourcePath: _selectedFile!.path,
        password: _passwordController.text,
        outputName: outputName,
      );

      AnalyticsService.instance.logPdfSaved();
      AnalyticsService.instance.logLockPdf();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(pdfFile: lockedFile, shortcuts: const []),
          ),
        );
      }
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'lock_failed',
        message: e.toString(),
      );
      if (mounted) {
        final msg = e.toString().toLowerCase();
        if (msg.contains('protected') || msg.contains('password') || msg.contains('encrypted')) {
          showAppDialog(
            context: context,
            builder: (ctx) => AppDialog(
              tone: AppDialogTone.warning,
              icon: Icons.lock_outline_rounded,
              title: 'Already Protected',
              description: 'This PDF is already password-protected. '
                  'Please select a PDF that is not locked.',
              primaryLabel: 'OK',
              onPrimary: () => Navigator.pop(ctx),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to lock PDF: $e')),
          );
        }
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
      appBar: toolAppBar(context, 'Lock PDF'),
      body: _isProcessing
          ? const ToolProcessingView(message: 'Encrypting your PDF...')
          : _selectedFile == null
              ? _buildEmptyState()
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      SelectedFileCard(
                        icon: Icons.lock_outline_rounded,
                        color: AppColors.toolLock,
                        name: _selectedFile!.path.split('/').last,
                        onChange: _pickFile,
                      ),
                      const SizedBox(height: 16),
                      ToolSectionCard(
                        title: 'File name',
                        child: TextFormField(
                          controller: _nameController,
                          decoration: toolInputDecoration(
                            hint: 'Locked file name',
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
                      const SizedBox(height: 16),
                      ToolSectionCard(
                        title: 'Set password',
                        subtitle: 'Your PDF will be encrypted with AES-256 bit encryption.',
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: toolInputDecoration(
                                label: 'Password',
                                icon: Icons.lock_rounded,
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a password';
                                }
                                if (value.length < 4) {
                                  return 'Password must be at least 4 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscurePassword,
                              decoration: toolInputDecoration(
                                label: 'Confirm password',
                                icon: Icons.lock_outline_rounded,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please confirm your password';
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: ready
          ? ToolBottomBar(
              child: ToolPrimaryButton(
                label: 'Lock PDF',
                icon: Icons.lock_rounded,
                onPressed: _lockPdf,
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return ToolEmptyWithAd(
      empty: ToolEmptyState(
        icon: Icons.lock_outline_rounded,
        color: AppColors.toolLock,
        title: 'Select PDF to Lock',
        message: 'Choose a PDF file from your device storage to password protect it with AES-256 encryption.',
        buttonLabel: 'Select PDF',
        buttonIcon: Icons.picture_as_pdf_rounded,
        onPressed: _pickFile,
      ),
      ad: const NativeAdWidget(),
    );
  }
}

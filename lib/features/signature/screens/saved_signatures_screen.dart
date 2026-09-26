import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/signature_service.dart';
import 'signature_pdf_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tool_ui.dart';
import 'signature_screen.dart';

class SavedSignaturesScreen extends StatefulWidget {
  /// When set, the chosen signature is applied to this file instead of
  /// opening the picker.
  final String? pdfPath;

  const SavedSignaturesScreen({super.key, this.pdfPath});

  @override
  State<SavedSignaturesScreen> createState() => _SavedSignaturesScreenState();
}

class _SavedSignaturesScreenState extends State<SavedSignaturesScreen> {
  List<File> _signatures = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSignatures();
  }

  Future<void> _loadSignatures() async {
    final sigs = await SignatureService.getSavedSignatures();
    if (mounted) {
      setState(() {
        _signatures = sigs;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectSignature(File signatureFile) async {
    try {
      final String pdfPath;
      final String outputName;
      final presetPath = widget.pdfPath;
      if (presetPath != null) {
        pdfPath = presetPath;
        outputName = '${presetPath.split('/').last.replaceAll('.pdf', '')}_signed';
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: false,
        );

        if (result == null || result.files.isEmpty) return;

        pdfPath = result.files.first.path!;
        outputName = '${result.files.first.name.replaceAll('.pdf', '')}_signed';
      }
      final pngBytes = await signatureFile.readAsBytes();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignaturePdfScreen(
              signaturePngBytes: pngBytes,
              pdfPath: pdfPath,
              outputName: outputName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load signature: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(File sig) async {
    final delete = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        tone: AppDialogTone.destructive,
        icon: Icons.delete_outline_rounded,
        title: 'Delete signature?',
        description: 'This saved signature will be removed from your device.',
        primaryLabel: 'Delete',
        onPrimary: () => Navigator.pop(ctx, true),
        secondaryLabel: 'Cancel',
        onSecondary: () => Navigator.pop(ctx),
      ),
    );
    if (delete != true) return;
    try {
      await sig.delete();
      await _loadSignatures();
    } catch (_) {}
  }

  void _createNew() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SignatureScreen(pdfPath: widget.pdfPath)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Saved Signatures'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandRed))
          : _signatures.isEmpty
              ? ToolEmptyState(
                  icon: Icons.draw_outlined,
                  color: AppColors.toolSignature,
                  title: 'No saved signatures',
                  message: 'Create a signature first, then save it to reuse it here.',
                  buttonLabel: 'Create Signature',
                  buttonIcon: Icons.draw_rounded,
                  onPressed: _createNew,
                )
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_signatures.length} saved signature${_signatures.length == 1 ? '' : 's'}',
                              style: toolSectionTitleStyle,
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Tap a signature to use it',
                              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      sliver: SliverGrid.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.35,
                        ),
                        itemCount: _signatures.length,
                        itemBuilder: (context, index) {
                          final sig = _signatures[index];
                          return Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: const BorderSide(color: AppColors.border),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _selectSignature(sig),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
                                      child: Image.file(
                                        sig,
                                        fit: BoxFit.contain,
                                        cacheWidth: 400,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: IconButton(
                                      tooltip: 'Delete signature',
                                      onPressed: () => _confirmDelete(sig),
                                      icon: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.border),
                                        ),
                                        child: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
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
      bottomNavigationBar: !_isLoading && _signatures.isNotEmpty
          ? ToolBottomBar(
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _createNew,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandRed,
                    side: const BorderSide(color: AppColors.brandRed, width: 1.5),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Create New Signature'),
                ),
              ),
            )
          : null,
    );
  }
}

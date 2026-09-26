import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart' as px;
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';
import '../services/pdf_split_service.dart';
import '../../lock/services/pdf_lock_service.dart';
import '../../pdf/screens/success_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/tool_ui.dart';

class PdfSplitScreen extends StatefulWidget {
  /// Opens the screen with this PDF already selected (skips the picker).
  final String? initialPdfPath;

  const PdfSplitScreen({super.key, this.initialPdfPath});

  @override
  State<PdfSplitScreen> createState() => _PdfSplitScreenState();
}

class _PdfSplitScreenState extends State<PdfSplitScreen> {
  File? _selectedFile;
  px.PdfDocument? _pdfDocument;
  int _pageCount = 0;
  final Set<int> _selectedPages = {}; // 0-indexed indices of selected pages
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  bool _isLoadingPdf = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    final initialPath = widget.initialPdfPath;
    if (initialPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitialFile(initialPath));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _closePdfDocument();
    super.dispose();
  }

  Future<void> _closePdfDocument() async {
    if (_pdfDocument != null) {
      await _pdfDocument!.close();
      _pdfDocument = null;
    }
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
      _onLoadError(e);
    }
  }

  Future<void> _openInitialFile(String path) async {
    try {
      await _useFile(File(path));
    } catch (e) {
      _onLoadError(e);
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
                'password-protected and cannot be split.\n\n'
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
      _isLoadingPdf = true;
      _selectedPages.clear();
      _nameController.text = 'Split_${DateTime.now().millisecondsSinceEpoch}';
    });

    await _closePdfDocument();

    final doc = await px.PdfDocument.openFile(file.path);

    setState(() {
      _pdfDocument = doc;
      _pageCount = doc.pagesCount;
      _isLoadingPdf = false;
    });
  }

  void _onLoadError(Object e) {
    if (!mounted) return;
    setState(() {
      _isLoadingPdf = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error loading PDF: $e')),
    );
  }

  void _togglePageSelection(int index) {
    setState(() {
      if (_selectedPages.contains(index)) {
        _selectedPages.remove(index);
      } else {
        _selectedPages.add(index);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPages.clear();
      _selectedPages.addAll(Iterable<int>.generate(_pageCount));
    });
  }

  void _deselectAll() {
    setState(() {
      _selectedPages.clear();
    });
  }

  Future<void> _splitPdf() async {
    if (_selectedFile == null || _selectedPages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one page to extract.')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final sortedSelectedPages = _selectedPages.toList()..sort();
      final outputName = _nameController.text.trim();

      // We must close the pdfDocument temporarily before splitting to ensure no file lock issues, 
      // although we read as bytes, it's safer.
      final path = _selectedFile!.path;
      await _closePdfDocument();

      final splitFile = await PdfSplitService.splitPdf(
        sourcePath: path,
        selectedPageIndices: sortedSelectedPages,
        outputName: outputName,
      );

      AnalyticsService.instance.logPdfSaved();
      AnalyticsService.instance.logSplitPdf();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: splitFile,
              shortcuts: const [
                SuccessShortcut.mergePdf,
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
        errorType: 'split_failed',
        message: e.toString(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to split PDF: $e')),
        );
      }
      // Re-open doc if failed
      if (_selectedFile != null) {
        try {
          final doc = await px.PdfDocument.openFile(_selectedFile!.path);
          setState(() {
            _pdfDocument = doc;
          });
        } catch (_) {}
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
    final ready = !_isProcessing && _selectedFile != null && !_isLoadingPdf;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Split PDF'),
      body: _isProcessing
          ? const ToolProcessingView(message: 'Extracting pages...')
          : _selectedFile == null
              ? _buildEmptyState()
              : _isLoadingPdf
                  ? const Center(child: CircularProgressIndicator(color: AppColors.brandRed))
                  : Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                            child: ToolSectionCard(
                              title: 'File name',
                              child: TextFormField(
                                controller: _nameController,
                                decoration: toolInputDecoration(
                                  hint: 'Output PDF name',
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
                            padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Select pages', style: toolSectionTitleStyle),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_selectedPages.length} of $_pageCount selected',
                                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: _selectedPages.length == _pageCount ? _deselectAll : _selectAll,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.brandRed,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  child: Text(
                                    _selectedPages.length == _pageCount ? 'Deselect All' : 'Select All',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _pageCount,
                              itemBuilder: (context, index) {
                                final isSelected = _selectedPages.contains(index);
                                return Semantics(
                                  selected: isSelected,
                                  button: true,
                                  label: 'Page ${index + 1}',
                                  child: GestureDetector(
                                    onTap: () => _togglePageSelection(index),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? AppColors.brandRed.withValues(alpha: 0.05)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected ? AppColors.brandRed : AppColors.border,
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: Padding(
                                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 28),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: _pdfDocument != null
                                                    ? PdfPageThumbnail(
                                                        document: _pdfDocument!,
                                                        pageNumber: index + 1,
                                                      )
                                                    : const SizedBox(),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              width: 22,
                                              height: 22,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: isSelected ? AppColors.brandRed : Colors.white,
                                                border: Border.all(
                                                  color: isSelected ? AppColors.brandRed : const Color(0xFFCBD0D8),
                                                  width: 2,
                                                ),
                                              ),
                                              child: isSelected
                                                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                                                  : null,
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 6,
                                            left: 0,
                                            right: 0,
                                            child: Text(
                                              'Page ${index + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: isSelected ? AppColors.brandRed : AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
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
                label: _selectedPages.isEmpty
                    ? 'Select Pages'
                    : 'Split PDF (${_selectedPages.length} Pages)',
                icon: Icons.call_split_rounded,
                onPressed: _selectedPages.isNotEmpty ? _splitPdf : null,
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return ToolEmptyWithAd(
      empty: ToolEmptyState(
        icon: Icons.call_split_rounded,
        color: AppColors.toolSplit,
        title: 'Select PDF to Split',
        message: 'Choose a PDF file from your device storage to view pages and extract selected pages offline.',
        buttonLabel: 'Select PDF',
        buttonIcon: Icons.picture_as_pdf_rounded,
        onPressed: _pickFile,
      ),
      ad: const NativeAdWidget(),
    );
  }
}

class PdfPageThumbnail extends StatefulWidget {
  final px.PdfDocument document;
  final int pageNumber;

  const PdfPageThumbnail({
    super.key,
    required this.document,
    required this.pageNumber,
  });

  @override
  State<PdfPageThumbnail> createState() => _PdfPageThumbnailState();
}

class _PdfPageThumbnailState extends State<PdfPageThumbnail> {
  Uint8List? _imageBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _renderPage();
  }

  Future<void> _renderPage() async {
    try {
      final page = await widget.document.getPage(widget.pageNumber);
      final pageImage = await page.render(
        width: page.width * 0.35,
        height: page.height * 0.35,
        format: px.PdfPageImageFormat.jpeg,
      );
      if (mounted) {
        setState(() {
          _imageBytes = pageImage?.bytes;
          _loading = false;
        });
      }
      await page.close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null || _imageBytes == null) {
      return const Center(child: Icon(Icons.error_outline, color: Colors.red));
    }
    return Image.memory(_imageBytes!, fit: BoxFit.contain);
  }
}

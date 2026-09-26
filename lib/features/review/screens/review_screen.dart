import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/exceptions/app_exceptions.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/core/services/storage_service.dart';
import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/core/widgets/banner_ad_widget.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../home/tool_actions.dart';
import '../../pdf/screens/success_screen.dart';
import '../../pdf/services/pdf_service.dart';

/// Last step of the scan / image-to-PDF flow: name the file, reorder or
/// remove pages, add more pages, and create the PDF.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _isBusy = false;
  String _busyMessage = '';

  String? get _appendTarget =>
      Provider.of<ScanProvider>(context, listen: false).appendToPdfPath;

  String _baseNameOf(String path) =>
      path.split('/').last.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');

  @override
  void initState() {
    super.initState();
    final target = _appendTarget;
    _nameController = TextEditingController(
      text: target != null
          ? '${_baseNameOf(target)}_updated'
          : 'Scan_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addPages() async {
    final camera = await ToolActions.askPageSource(context);
    if (camera == null || !mounted) return;
    final provider = Provider.of<ScanProvider>(context, listen: false);
    final before = provider.pages.length;
    final added = await ToolActions.addPagesFrom(context, camera: camera);
    if (added == 0 || !mounted) return;

    // New pages get the same default Enhance filter as the filter step.
    setState(() {
      _isBusy = true;
      _busyMessage = 'Enhancing new pages...';
    });
    try {
      for (final page in provider.pages.skip(before).toList()) {
        final file = await ImageUtils.applyFilter(page.displayFile, FilterType.enhance);
        provider.updatePageProcessedFile(page.id, file);
      }
    } catch (e) {
      debugPrint('Enhance new pages failed: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Avoids overwriting an existing file with the same name.
  Future<String> _uniqueName(String base) async {
    final dir = await StorageService.getAppDirectory();
    var name = base;
    var n = 2;
    while (await File('$dir/$name.pdf').exists()) {
      name = '${base}_$n';
      n++;
    }
    return name;
  }

  Future<void> _createPdf() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty) {
      _showErrorDialog(
        'No Pages',
        'There are no pages to generate the PDF.\n\nPlease add at least one page.',
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _busyMessage = 'Creating your PDF...';
    });

    try {
      final target = provider.appendToPdfPath;
      final name = target != null
          ? await _uniqueName(_nameController.text.trim())
          : _nameController.text.trim();
      final file = await PdfService.generatePdf(
        fileName: name,
        pages: provider.pages,
        format: PdfPageFormat.a4,
        toolType: provider.toolType,
        prependPdfPath: target,
        onProgress: (step) {
          if (!mounted) return;
          setState(() {
            _busyMessage = switch (step) {
              'validating' => 'Validating images...',
              'processing_page' => 'Creating your PDF...',
              'saving' => 'Saving document...',
              _ => _busyMessage,
            };
          });
        },
      );

      AnalyticsService.instance.logPdfSaved();
      final toolType = provider.toolType;
      if (toolType == 'scan_pdf') {
        AnalyticsService.instance.logScanCompleted();
      } else if (toolType == 'image_to_pdf') {
        AnalyticsService.instance.logImageToPdfCompleted();
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SuccessScreen(pdfFile: file)),
        );
      }
    } on MissingImageException catch (e) {
      e.log();
      if (mounted) _showMissingImageDialog();
    } on ImageProcessingException catch (e) {
      e.log();
      if (mounted) {
        final pageMsg = e.pageIndex != null
            ? 'Page ${e.pageIndex} could not be processed.\n\n'
                'Please edit or replace this page.'
            : e.userMessage;
        _showGenerationFailedDialog(pageMsg);
      }
    } on AppException catch (e) {
      e.log();
      if (mounted) _showGenerationFailedDialog(e.userMessage);
    } catch (e) {
      debugPrint('PDF generation error: $e');
      if (mounted) _showGenerationFailedDialog(null);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMissingImageDialog() {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        tone: AppDialogTone.error,
        icon: Icons.image_not_supported_outlined,
        title: 'Image Missing',
        description: 'One or more edited images are no longer available.\n\n'
            'This can happen if Android removes temporary files.\n\n'
            'Please crop the affected page again and try creating the PDF.',
        primaryLabel: 'Recrop',
        onPrimary: () {
          Navigator.pop(ctx);
          Navigator.pop(context);
        },
        secondaryLabel: 'Cancel',
        onSecondary: () {
          Navigator.pop(ctx);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showAppDialog(
      context: context,
      builder: (ctx) => AppDialog(
        tone: AppDialogTone.error,
        icon: Icons.error_outline_rounded,
        title: title,
        description: message,
        primaryLabel: 'OK',
        onPrimary: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showGenerationFailedDialog(String? customMessage) {
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        tone: AppDialogTone.error,
        icon: Icons.error_outline_rounded,
        title: 'Unable to Create PDF',
        description: customMessage ??
            'Something went wrong while generating your PDF.\n\n'
                'Please try again.\n\n'
                'If the issue continues, reselect the images and recreate the PDF.',
        primaryLabel: 'Try Again',
        onPrimary: () {
          Navigator.pop(ctx);
          _createPdf();
        },
        secondaryLabel: 'Go Back',
        onSecondary: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = _appendTarget;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.brandRed,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
        elevation: 0,
        title: Consumer<ScanProvider>(
          builder: (context, provider, _) => Text('Review (${provider.pages.length})'),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _nameController,
                    enabled: !_isBusy,
                    decoration: AppDialog.inputDecoration(
                      hintText: 'File name',
                      suffixText: '.pdf',
                    ).copyWith(
                      prefixIcon: const Icon(Icons.edit_document, size: 20),
                      fillColor: Colors.white,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Please enter a name' : null,
                  ),
                ),
              ),
              if (target != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'These pages will be added after the pages of '
                          '"${_baseNameOf(target)}". A new PDF will be saved.',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Consumer<ScanProvider>(
                  builder: (context, provider, _) {
                    if (provider.pages.isEmpty) {
                      return const Center(
                        child: Text('No pages yet. Tap Add Pages.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      );
                    }
                    return ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      itemCount: provider.pages.length,
                      onReorder: provider.reorderPages,
                      buildDefaultDragHandles: false,
                      itemBuilder: (context, index) {
                        final page = provider.pages[index];
                        return Container(
                          key: ValueKey(page.id),
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 46,
                                height: 62,
                                child: Image.file(
                                  page.displayFile,
                                  fit: BoxFit.cover,
                                  cacheWidth: 140,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                            title: Text(
                              'Page ${index + 1}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Remove page',
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.brandRed),
                                  onPressed: _isBusy ? null : () => provider.removePage(page.id),
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_indicator_rounded, color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isBusy)
            Container(
              color: Colors.white.withValues(alpha: 0.85),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.brandRed),
                    const SizedBox(height: 16),
                    Text(
                      _busyMessage,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _addPages,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandRed,
                          side: const BorderSide(color: AppColors.brandRed, width: 1.5),
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add Pages', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _isBusy ? null : _createPdf,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.brandRed,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Create PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: BannerAdWidget(compact: true),
            ),
          ],
        ),
      ),
    );
  }
}

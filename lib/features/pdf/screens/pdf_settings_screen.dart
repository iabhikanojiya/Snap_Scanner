import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';
import 'package:snap_scanner/core/exceptions/app_exceptions.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import '../services/pdf_service.dart';
import 'success_screen.dart';

class PdfSettingsScreen extends StatefulWidget {
  final String? buttonText;
  const PdfSettingsScreen({super.key, this.buttonText});

  @override
  State<PdfSettingsScreen> createState() => _PdfSettingsScreenState();
}

class _PdfSettingsScreenState extends State<PdfSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  PdfPageFormat _selectedFormat = PdfPageFormat.a4;
  bool _isLandscape = false;
  bool _isGenerating = false;
  String _progressMessage = '';

  static const _progressMessages = [
    'Preparing pages...',
    'Validating images...',
    'Creating your PDF...',
    'Optimizing content...',
    'Saving document...',
  ];

  int _currentProgressStep = 0;

  @override
  void initState() {
    super.initState();
    String defaultName = 'Scan_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}';
    _nameController = TextEditingController(text: defaultName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onProgress(String step) {
    if (!mounted) return;
    setState(() {
      switch (step) {
        case 'validating':
          _progressMessage = _progressMessages[1];
          _currentProgressStep = 1;
          break;
        case 'processing_page':
          _progressMessage = _progressMessages[2];
          _currentProgressStep = 2;
          break;
        case 'saving':
          _progressMessage = _progressMessages[4];
          _currentProgressStep = 4;
          break;
      }
    });
  }

  Future<void> _generateAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isGenerating = true;
      _progressMessage = _progressMessages[0];
      _currentProgressStep = 0;
    });

    try {
      final provider = Provider.of<ScanProvider>(context, listen: false);

      if (provider.pages.isEmpty) {
        _showErrorDialog(
          'No Pages',
          'There are no pages to generate the PDF.\n\nPlease add at least one page.',
        );
        return;
      }

      PdfPageFormat format = _selectedFormat;
      if (_isLandscape) {
        format = format.landscape;
      }

      final file = await PdfService.generatePdf(
        fileName: _nameController.text,
        pages: provider.pages,
        format: format,
        toolType: provider.toolType,
        onProgress: _onProgress,
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
      if (mounted) {
        _showMissingImageDialog();
      }
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
      if (mounted) {
        _showGenerationFailedDialog(e.userMessage);
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
      if (mounted) {
        _showGenerationFailedDialog(null);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _progressMessage = '';
        });
      }
    }
  }

  void _showMissingImageDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.image_not_supported, color: Colors.red),
            SizedBox(width: 10),
            Expanded(child: Text('Image Missing', style: TextStyle(fontSize: 20))),
          ],
        ),
        content: const Text(
          'One or more edited images are no longer available.\n\n'
          'This can happen if Android removes temporary files.\n\n'
          'Please crop the affected page again and try creating the PDF.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Recrop'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showGenerationFailedDialog(String? customMessage) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Unable to Create PDF', style: TextStyle(fontSize: 20)),
        content: Text(
          customMessage ??
              'Something went wrong while generating your PDF.\n\n'
              'Please try again.\n\n'
              'If the issue continues, reselect the images and recreate the PDF.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Go Back'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _generateAndSave();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('PDF Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isGenerating
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(strokeWidth: 4),
                    ),
                    const SizedBox(height: 32),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _progressMessage,
                        key: ValueKey(_currentProgressStep),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    LinearProgressIndicator(
                      value: (_currentProgressStep + 1) / _progressMessages.length,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('File Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'File Name',
                              prefixIcon: const Icon(Icons.edit_document),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              suffixText: '.pdf',
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a name';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Page Setup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<PdfPageFormat>(
                            value: _selectedFormat,
                            decoration: InputDecoration(
                              labelText: 'Page Size',
                              prefixIcon: const Icon(Icons.pages),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: const [
                              DropdownMenuItem(value: PdfPageFormat.a4, child: Text("A4")),
                              DropdownMenuItem(value: PdfPageFormat.letter, child: Text("Letter")),
                              DropdownMenuItem(value: PdfPageFormat.legal, child: Text("Legal")),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedFormat = val);
                            },
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Landscape Orientation', style: TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: const Text('Rotate pages horizontally', style: TextStyle(fontSize: 12)),
                            value: _isLandscape,
                            activeColor: Colors.blueAccent,
                            onChanged: (val) => setState(() => _isLandscape = val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                        ),
                        onPressed: _isGenerating ? null : _generateAndSave,
                        child: _isGenerating
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                            : Text(widget.buttonText ?? 'Generate PDF', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
          ),
    );
  }
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart' as px;
import '../services/pdf_split_service.dart';
import '../../pdf/screens/success_screen.dart';

class PdfSplitScreen extends StatefulWidget {
  const PdfSplitScreen({super.key});

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
        final filePath = result.files.first.path!;
        final file = File(filePath);

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
    } catch (e) {
      setState(() {
        _isLoadingPdf = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading PDF: $e')),
        );
      }
    }
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

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(pdfFile: splitFile),
          ),
        );
      }
    } catch (e) {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Split PDF', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.blueAccent),
                  SizedBox(height: 16),
                  Text(
                    'Extracting pages offline, please wait...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ],
              ),
            )
          : _selectedFile == null
              ? _buildEmptyState()
              : _isLoadingPdf
                  ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                  : Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _nameController,
                                    decoration: InputDecoration(
                                      labelText: 'Output PDF Name',
                                      prefixIcon: const Icon(Icons.edit_document),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      suffixText: '.pdf',
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Please enter a filename';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Selected: ${_selectedPages.length} of $_pageCount pages',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _selectAll,
                                        child: const Text('Select All'),
                                      ),
                                      TextButton(
                                        onPressed: _deselectAll,
                                        child: const Text('Deselect All'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.72,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: _pageCount,
                              itemBuilder: (context, index) {
                                final isSelected = _selectedPages.contains(index);
                                return GestureDetector(
                                  onTap: () => _togglePageSelection(index),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? Colors.blueAccent : Colors.grey.shade300,
                                        width: isSelected ? 2.5 : 1.0,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.02),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
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
                                        // Selection indicator checkbox/circle at top-right
                                        Positioned(
                                          top: 6,
                                          right: 6,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: isSelected ? Colors.blueAccent : Colors.black26,
                                              shape: BoxShape.circle,
                                            ),
                                            padding: const EdgeInsets.all(4),
                                            child: Icon(
                                              isSelected ? Icons.check : Icons.circle_outlined,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                        // Page tag at bottom center
                                        Positioned(
                                          bottom: 6,
                                          left: 0,
                                          right: 0,
                                          child: Center(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'Page ${index + 1}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
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
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 2,
                                  ),
                                  onPressed: _selectedPages.isNotEmpty ? _splitPdf : null,
                                  child: Text(
                                    _selectedPages.isEmpty
                                        ? 'Select Pages'
                                        : 'Split PDF (${_selectedPages.length} Pages)',
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_split,
                color: Colors.green,
                size: 64,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Select PDF to Split',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a PDF file from your device storage to view pages and extract selected pages offline.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _pickFile,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text(
                  'Select PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
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

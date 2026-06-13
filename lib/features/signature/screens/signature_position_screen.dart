import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;
import '../services/signature_service.dart';
import '../../pdf/screens/success_screen.dart';

class SignaturePositionScreen extends StatefulWidget {
  final ui.Image signatureImage;
  final String pdfPath;
  final String outputName;

  const SignaturePositionScreen({
    super.key,
    required this.signatureImage,
    required this.pdfPath,
    required this.outputName,
  });

  @override
  State<SignaturePositionScreen> createState() => _SignaturePositionScreenState();
}

class _SignaturePositionScreenState extends State<SignaturePositionScreen> {
  px.PdfDocument? _pdfDocument;
  int _pageCount = 0;
  int _selectedPage = 0;
  bool _isLoadingPdf = true;
  bool _isProcessing = false;

  double _positionX = 0.5;
  double _positionY = 0.7;
  double _signatureWidth = 200;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    _closePdfDocument();
    super.dispose();
  }

  Future<void> _closePdfDocument() async {
    if (_pdfDocument != null) {
      await _pdfDocument!.close();
      _pdfDocument = null;
    }
  }

  Future<void> _loadPdf() async {
    try {
      final doc = await px.PdfDocument.openFile(widget.pdfPath);
      if (mounted) {
        setState(() {
          _pdfDocument = doc;
          _pageCount = doc.pagesCount;
          _isLoadingPdf = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPdf = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load PDF: $e')),
        );
      }
    }
  }

  Future<void> _confirmPlacement() async {
    setState(() => _isProcessing = true);

    try {
      final file = await SignatureService.addSignatureToPdf(
        sourcePdfPath: widget.pdfPath,
        signatureImage: widget.signatureImage,
        pageNumber: _selectedPage,
        outputName: widget.outputName,
        positionX: _positionX,
        positionY: _positionY,
        signatureWidth: _signatureWidth,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: file,
              title: 'PDF Signed Successfully!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add signature: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Position Signature', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    'Adding signature to PDF...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ],
              ),
            )
          : _isLoadingPdf
              ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select Page',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 160,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _pageCount,
                                separatorBuilder: (_, __) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final isSelected = _selectedPage == index;
                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedPage = index),
                                    child: Container(
                                      width: 110,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected ? Colors.deepPurpleAccent : Colors.grey.shade300,
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
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: _pdfDocument != null
                                                    ? _PageThumbnail(
                                                        document: _pdfDocument!,
                                                        pageNumber: index + 1,
                                                      )
                                                    : const SizedBox(),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isSelected ? Colors.deepPurpleAccent : Colors.grey.shade100,
                                              borderRadius: const BorderRadius.only(
                                                bottomLeft: Radius.circular(11),
                                                bottomRight: Radius.circular(11),
                                              ),
                                            ),
                                            child: Text(
                                              'Page ${index + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: isSelected ? Colors.white : Colors.black87,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
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
                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            Text(
                              'Position Signature on Page',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
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
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 200,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final previewW = constraints.maxWidth;
                                        final previewH = previewW * 1.414;
                                        final sigW = _signatureWidth / 600 * previewW;
                                        final sigH = sigW * 0.3;
                                        final x = _positionX * (previewW - sigW);
                                        final y = _positionY * (previewH - sigH);

                                        return Container(
                                          height: previewH.clamp(150, 250),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade400),
                                          ),
                                          child: Stack(
                                            children: [
                                              Center(
                                                child: Text(
                                                  'Page Preview',
                                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                                ),
                                              ),
                                              Positioned(
                                                left: x.clamp(0, previewW - sigW),
                                                top: y.clamp(0, previewH - sigH),
                                                child: Container(
                                                  width: sigW.clamp(20, previewW),
                                                  height: sigH.clamp(10, previewH),
                                                  decoration: BoxDecoration(
                                                    color: Colors.deepPurpleAccent.withOpacity(0.5),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: Colors.deepPurpleAccent,
                                                      width: 1.5,
                                                    ),
                                                  ),
                                                  child: const Center(
                                                    child: Text(
                                                      'Signature',
                                                      style: TextStyle(
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
                                        );
                                      },
                                    ),
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
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSlider(
                                    label: 'Horizontal Position',
                                    value: _positionX,
                                    icon: Icons.arrow_back,
                                    onChanged: (v) => setState(() => _positionX = v),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSlider(
                                    label: 'Vertical Position',
                                    value: _positionY,
                                    icon: Icons.arrow_upward,
                                    onChanged: (v) => setState(() => _positionY = v),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSlider(
                                    label: 'Signature Size',
                                    value: (_signatureWidth - 50) / 350,
                                    displayValue: '${_signatureWidth.round()}px',
                                    icon: Icons.zoom_out_map,
                                    onChanged: (v) => setState(() => _signatureWidth = 50 + v * 350),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
                              backgroundColor: Colors.deepPurpleAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 2,
                            ),
                            onPressed: _confirmPlacement,
                            child: const Text(
                              'Add Signature to PDF',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    IconData? icon,
    String? displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
            ],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            Text(
              displayValue ?? '${(value * 100).round()}%',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.deepPurpleAccent),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0.0,
          max: 1.0,
          divisions: 100,
          activeColor: Colors.deepPurpleAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PageThumbnail extends StatefulWidget {
  final px.PdfDocument document;
  final int pageNumber;

  const _PageThumbnail({required this.document, required this.pageNumber});

  @override
  State<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends State<_PageThumbnail> {
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
      return const Center(child: Icon(Icons.error_outline, color: Colors.red, size: 20));
    }
    return Image.memory(_imageBytes!, fit: BoxFit.contain);
  }
}

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/signature_pad.dart';
import '../services/signature_service.dart';
import '../../pdf/screens/success_screen.dart';
import 'signature_pdf_screen.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final GlobalKey<SignaturePadState> _padKey = GlobalKey();
  double _strokeWidth = 3.0;
  Color _strokeColor = Colors.black;
  bool _isProcessing = false;

  final List<Color> _colorOptions = [
    Colors.black,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.deepPurple,
    Colors.orange,
  ];

  Future<void> _saveAsImage() async {
    if (!_padKey.currentState!.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw a signature first.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final image = await _padKey.currentState!.toImage();
      final fileName = 'Signature_${DateTime.now().millisecondsSinceEpoch}';
      final file = await SignatureService.saveSignatureAsImage(
        image: image,
        outputName: fileName,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: file,
              icon: Icons.draw,
              iconColor: Colors.indigo,
              title: 'Signature Saved!',
              fileIcon: Icons.draw,
              fileIconColor: Colors.indigo,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save signature: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _addToPdf() async {
    if (!_padKey.currentState!.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw a signature first.')),
      );
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final pdfPath = result.files.first.path!;
      final outputName = '${result.files.first.name.replaceAll('.pdf', '')}_signed';

      final signatureImage = await _padKey.currentState!.renderSignatureOnly();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignaturePdfScreen(
              signatureImage: signatureImage,
              pdfPath: pdfPath,
              outputName: outputName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Signature', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    'Processing, please wait...',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Draw your signature below',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use your finger or stylus to sign',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 16),

                  SignaturePad(key: _padKey, strokeWidth: _strokeWidth, strokeColor: _strokeColor),

                  const SizedBox(height: 16),

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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('Stroke Width', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            Expanded(
                              child: Slider(
                                value: _strokeWidth,
                                min: 1.0,
                                max: 8.0,
                                divisions: 14,
                                label: _strokeWidth.toStringAsFixed(1),
                                onChanged: (v) => setState(() => _strokeWidth = v),
                              ),
                            ),
                            Text(
                              _strokeWidth.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Color', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(width: 16),
                            ..._colorOptions.map((color) {
                              final isSelected = _strokeColor == color;
                              return GestureDetector(
                                onTap: () => setState(() => _strokeColor = color),
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: isSelected
                                        ? Border.all(color: Colors.blueAccent, width: 3)
                                        : null,
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 6)]
                                        : null,
                                  ),
                                ),
                              );
                            }),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => _padKey.currentState?.clear(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Clear'),
                              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      onPressed: _saveAsImage,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Save as Image', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurpleAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                      ),
                      onPressed: _addToPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Add to PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:snap_scanner/core/services/analytics_service.dart';
import '../widgets/signature_pad.dart';
import '../services/signature_service.dart';
import '../../pdf/screens/success_screen.dart';
import 'signature_pdf_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/tool_ui.dart';

class SignatureScreen extends StatefulWidget {
  /// When set, "Add to PDF" signs this file instead of opening the picker.
  final String? pdfPath;

  const SignatureScreen({super.key, this.pdfPath});

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
    final padState = _padKey.currentState;
    if (padState == null || !padState.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw a signature first.')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final image = await padState.renderSignatureOnly();
      final fileName = 'Signature_${DateTime.now().millisecondsSinceEpoch}';
      final file = await SignatureService.saveSignatureAsImage(
        image: image,
        outputName: fileName,
      );

      AnalyticsService.instance.logSignatureSaved();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(
              pdfFile: file,
              icon: Icons.draw,
              iconColor: Colors.indigo,
              title: 'Signature Saved!',
              shortcuts: const [SuccessShortcut.addSign, SuccessShortcut.scanPdf],
              fileIcon: Icons.draw,
              fileIconColor: Colors.indigo,
            ),
          ),
        );
      }
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'signature_save_failed',
        message: e.toString(),
      );
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
    final padState = _padKey.currentState;
    if (padState == null || !padState.hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw a signature first.')),
      );
      return;
    }

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

        final file = result.files.first;
        if (file.path == null) throw Exception('Selected file has no accessible path');
        pdfPath = file.path!;
        outputName = '${file.name.replaceAll('.pdf', '')}_signed';
      }

      final padState = _padKey.currentState;
      if (padState == null) throw Exception('Signature pad no longer available');
      final signatureImage = await padState.renderSignatureOnly();
      final byteData = await signatureImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null) throw Exception('Failed to capture signature');

      final strokeData = padState.getStrokeData();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignaturePdfScreen(
              signaturePngBytes: pngBytes,
              pdfPath: pdfPath,
              outputName: outputName,
              strokeData: strokeData,
            ),
          ),
        );
      }
    } catch (e) {
      AnalyticsService.instance.logErrorOccurred(
        errorType: 'signature_pdf_load_failed',
        message: e.toString(),
      );
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
      backgroundColor: AppColors.background,
      appBar: toolAppBar(context, 'Create Signature'),
      body: _isProcessing
          ? const ToolProcessingView(message: 'Processing your signature...')
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                ToolSectionCard(
                  title: 'Draw your signature',
                  subtitle: 'Use your finger or stylus to sign',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Undo',
                        onPressed: () => _padKey.currentState?.undo(),
                        icon: const Icon(Icons.undo_rounded, color: AppColors.textSecondary),
                      ),
                      TextButton(
                        onPressed: () => _padKey.currentState?.clear(),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.brandRed,
                          textStyle: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      SignaturePad(key: _padKey, strokeWidth: _strokeWidth, strokeColor: _strokeColor),
                      // "Sign here" hint; purely visual, never captured.
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 30,
                        child: IgnorePointer(
                          child: Text(
                            'Sign here',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Color(0xFFB8BEC8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ToolSectionCard(
                  title: 'Pen',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Color',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: _colorOptions.map((color) {
                          final isSelected = _strokeColor == color;
                          return Semantics(
                            selected: isSelected,
                            button: true,
                            label: 'Pen color',
                            child: GestureDetector(
                              onTap: () => setState(() => _strokeColor = color),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 38,
                                height: 38,
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? color : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                  child: isSelected
                                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text(
                            'Thickness',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                          ),
                          const Spacer(),
                          // Live preview of the current pen.
                          Container(
                            width: 48,
                            height: _strokeWidth,
                            decoration: BoxDecoration(
                              color: _strokeColor,
                              borderRadius: BorderRadius.circular(_strokeWidth),
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.brandRed,
                          thumbColor: AppColors.brandRed,
                          inactiveTrackColor: AppColors.brandRed.withValues(alpha: 0.15),
                          overlayColor: AppColors.brandRed.withValues(alpha: 0.1),
                          valueIndicatorColor: AppColors.brandRed,
                        ),
                        child: Slider(
                          value: _strokeWidth,
                          min: 1.0,
                          max: 8.0,
                          divisions: 14,
                          label: _strokeWidth.toStringAsFixed(1),
                          onChanged: (v) => setState(() => _strokeWidth = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _isProcessing
          ? null
          : ToolBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _saveAsImage,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.brandRed,
                          side: const BorderSide(color: AppColors.brandRed, width: 1.5),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        icon: const Icon(Icons.save_alt_rounded, size: 20),
                        label: const Text('Save'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ToolPrimaryButton(
                      label: 'Add to PDF',
                      icon: Icons.picture_as_pdf_rounded,
                      onPressed: _addToPdf,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

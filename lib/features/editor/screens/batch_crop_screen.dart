import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/core/exceptions/app_exceptions.dart';
import 'package:snap_scanner/core/utils/file_utils.dart';
import 'package:snap_scanner/core/utils/image_validator.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/editor/screens/batch_filter_screen.dart';
import 'package:snap_scanner/core/widgets/banner_ad_widget.dart';

class BatchCropScreen extends StatefulWidget {
  const BatchCropScreen({super.key});

  @override
  State<BatchCropScreen> createState() => _BatchCropScreenState();
}

class _BatchCropScreenState extends State<BatchCropScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isCropProcessing = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _cropCurrentImage(BuildContext context) async {
    final provider = Provider.of<ScanProvider>(context, listen: false);
    if (provider.pages.isEmpty) return;

    if (_isCropProcessing) return;
    setState(() => _isCropProcessing = true);

    try {
      final page = provider.pages[_currentIndex];
      final currentFile = page.displayFile;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: currentFile.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop & Rotate',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
          IOSUiSettings(
            title: 'Crop & Rotate',
          ),
        ],
      );

      if (croppedFile != null) {
        final docPath = await FileUtils.getAppDocPath();
        final permanentFile = await ImageValidator.validateAndCopyToPermanent(
          File(croppedFile.path),
          '$docPath/ProcessedImages',
        );
        provider.updatePageProcessedFile(page.id, permanentFile);
      }
    } on AppException catch (e) {
      e.log();
      if (!context.mounted) return;
      _showErrorDialog(context, e.userMessage);
    } catch (e) {
      debugPrint('Crop failed: $e');
      if (!context.mounted) return;
      _showErrorDialog(
        context,
        'Could not crop the image.\n\nPlease try again.',
      );
    } finally {
      if (mounted) setState(() => _isCropProcessing = false);
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 10),
            Text('Image Missing'),
          ],
        ),
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

  void _goToNextStep() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BatchFilterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScanProvider>(
      builder: (context, provider, child) {
        if (provider.pages.isEmpty) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: Text("No images to crop", style: TextStyle(color: Colors.white))),
          );
        }

        final totalPages = provider.pages.length;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentIndex + 1} / $totalPages',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: _goToNextStep,
                child: const Text('Next', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ],
          ),
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: totalPages,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final page = provider.pages[index];
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Image.file(page.displayFile, fit: BoxFit.contain),
                    ),
                  );
                },
              ),
              if (_isCropProcessing)
                Container(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _currentIndex > 0
                            ? () {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                        icon: Icon(Icons.arrow_back_ios, color: _currentIndex > 0 ? Colors.white : Colors.grey),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _isCropProcessing ? null : () => _cropCurrentImage(context),
                            icon: Icon(Icons.crop, color: _isCropProcessing ? Colors.grey : Colors.white, size: 32),
                          ),
                          const Text('Crop', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                      IconButton(
                        onPressed: _currentIndex < totalPages - 1
                            ? () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              }
                            : null,
                        icon: Icon(Icons.arrow_forward_ios, color: _currentIndex < totalPages - 1 ? Colors.white : Colors.grey),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: const BannerAdWidget(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/editor/screens/batch_filter_screen.dart';

class BatchCropScreen extends StatefulWidget {
  const BatchCropScreen({super.key});

  @override
  State<BatchCropScreen> createState() => _BatchCropScreenState();
}

class _BatchCropScreenState extends State<BatchCropScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

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

    final page = provider.pages[_currentIndex];
    final currentFile = page.displayFile;

    try {
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
        provider.updatePageProcessedFile(page.id, File(croppedFile.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Crop failed: $e')),
        );
      }
    }
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
          body: PageView.builder(
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
          bottomNavigationBar: Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: SafeArea(
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
                        onPressed: () => _cropCurrentImage(context),
                        icon: const Icon(Icons.crop, color: Colors.white, size: 32),
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
          ),
        );
      },
    );
  }
}

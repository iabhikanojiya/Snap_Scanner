import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/core/models/scanned_page.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/editor/screens/batch_crop_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInit = false;
  bool _isProcessing = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Reset provider for a new scan session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<ScanProvider>(context, listen: false);
        provider.clearPages();
        provider.setToolType('scan_pdf');
      }
    });

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Use the first rear camera
        _controller = CameraController(
          _cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
        );

        await _controller!.initialize();
        if (mounted) {
          setState(() {
            _isInit = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
      // Handle permission errors or no camera
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to initialize camera')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _controller!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }
  
  void _toggleFlash() async {
    if (_controller == null) return;
    
    FlashMode newMode;
    if (_flashMode == FlashMode.off) {
      newMode = FlashMode.torch;
    } else {
      newMode = FlashMode.off;
    }

    try {
      await _controller!.setFlashMode(newMode);
      setState(() {
        _flashMode = newMode;
      });
    } catch (e) {
      debugPrint("Error setting flash: $e");
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _controller!.takePicture();
      
      final String pageId = const Uuid().v4();
      
      // Create a ScannedPage with the original image right away for speed
      final page = ScannedPage(
        id: pageId,
        originalPath: image.path, 
        processedFile: File(image.path), 
      );

      // Add to provider immediately
      if (mounted) {
        Provider.of<ScanProvider>(context, listen: false).addPage(page);
      }

      // Optimize Image in background to avoid blocking the user
      ImageUtils.optimizeImage(File(image.path)).then((optimizedFile) {
        if (mounted) {
          Provider.of<ScanProvider>(context, listen: false)
              .updatePageProcessedFile(pageId, optimizedFile);
        }
      }).catchError((e) {
        debugPrint("Optimization error: $e");
      });

    } catch (e) {
      debugPrint("Capture error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _onDone() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BatchCropScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInit || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera Preview
             SizedBox.expand(
               child: CameraPreview(_controller!),
             ),
             
             // Top Toolbar
             Positioned(
               top: 16,
               left: 16,
               right: 16,
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                   IconButton(
                     onPressed: () => Navigator.pop(context),
                     icon: const Icon(Icons.close, color: Colors.white, size: 28),
                   ),
                   IconButton(
                     onPressed: _toggleFlash,
                     icon: Icon(
                       _flashMode == FlashMode.off ? Icons.flash_off : Icons.flash_on,
                       color: Colors.white,
                       size: 28,
                     ),
                   ),
                 ],
               ),
             ),

             // Bottom Controls
             Positioned(
               bottom: 32,
               left: 0,
               right: 0,
               child: Column(
                 children: [
                   // Horizontal List of Thumbnails with Delete button
                   Consumer<ScanProvider>(
                     builder: (context, scanProvider, _) {
                       if (scanProvider.pages.isEmpty) return const SizedBox.shrink();
                       return Container(
                         height: 80,
                         margin: const EdgeInsets.only(bottom: 24),
                         child: ListView.builder(
                           scrollDirection: Axis.horizontal,
                           padding: const EdgeInsets.symmetric(horizontal: 16),
                           itemCount: scanProvider.pages.length,
                           itemBuilder: (context, index) {
                             final page = scanProvider.pages[index];
                             return Stack(
                               clipBehavior: Clip.none,
                               children: [
                                 Container(
                                   width: 60,
                                   margin: const EdgeInsets.only(right: 12),
                                   decoration: BoxDecoration(
                                     border: Border.all(color: Colors.white, width: 2),
                                     borderRadius: BorderRadius.circular(8),
                                     image: DecorationImage(
                                       image: FileImage(page.displayFile),
                                       fit: BoxFit.cover,
                                     ),
                                   ),
                                   child: Align(
                                     alignment: Alignment.bottomCenter,
                                     child: Container(
                                       width: double.infinity,
                                       color: Colors.black54,
                                       child: Text(
                                         '${index + 1}',
                                         textAlign: TextAlign.center,
                                         style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                       ),
                                     ),
                                   ),
                                 ),
                                 Positioned(
                                   top: -8,
                                   right: 4,
                                   child: GestureDetector(
                                     onTap: () => scanProvider.removePage(page.id),
                                     child: Container(
                                       padding: const EdgeInsets.all(2),
                                       decoration: const BoxDecoration(
                                         color: Colors.red,
                                         shape: BoxShape.circle,
                                       ),
                                       child: const Icon(Icons.close, color: Colors.white, size: 16),
                                     ),
                                   ),
                                 ),
                               ],
                             );
                           },
                         ),
                       );
                     },
                   ),
                   
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                     children: [
                        // Left: Empty space for balance (Thumbnails moved above)
                        const SizedBox(width: 48),
                        
                        // Center: Capture Button
                        GestureDetector(
                          onTap: _captureImage,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: Colors.transparent,
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: _isProcessing 
                                ? const CircularProgressIndicator(strokeWidth: 2) 
                                : null,
                            ),
                          ),
                        ),

                        // Right: Done Button
                        Consumer<ScanProvider>(
                          builder: (context, provider, _) {
                            return GestureDetector(
                              onTap: provider.pages.isNotEmpty ? _onDone : null,
                              child: Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                child: Text(
                                  "Done",
                                  style: TextStyle(
                                    color: provider.pages.isNotEmpty ? Colors.white : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                     ],
                   ),
                 ],
               ),
             ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/core/models/scanned_page.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/editor/screens/batch_crop_screen.dart';

enum _CameraUiState {
  idle,
  requesting,
  ready,
  denied,
  permanentlyDenied,
  unavailable,
}

class ScannerScreen extends StatefulWidget {
  final bool appendMode;
  /// Folder the resulting PDF is added to (scan started from a folder).
  final String? folderId;
  const ScannerScreen({super.key, this.appendMode = false, this.folderId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with WidgetsBindingObserver {
  _CameraUiState _cameraUiState = _CameraUiState.idle;
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _denialCount = 0;
  bool _isProcessing = false;
  bool _isDisposed = false;
  bool _wasCameraActive = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = Provider.of<ScanProvider>(context, listen: false);
      if (!widget.appendMode) {
        provider.clearPages();
        provider.setToolType('scan_pdf');
        provider.setTargetFolder(widget.folderId);
      }
    });
  }

  Future<void> _startCamera() async {
    if (_cameraUiState == _CameraUiState.requesting || _isDisposed) return;

    debugPrint('[Camera] Initializing...');

    setState(() {
      _cameraUiState = _CameraUiState.requesting;
    });

    try {
      final cameras = await availableCameras();
      if (!mounted || _isDisposed) {
        debugPrint('[Camera] Disposed');
        return;
      }

      if (cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _cameraUiState = _CameraUiState.unavailable;
          });
        }
        return;
      }

      final cameraController = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
      );

      await cameraController.initialize();
      if (!mounted || _isDisposed) {
        debugPrint('[Camera] Disposed');
        await cameraController.dispose();
        return;
      }

      if (cameraController.value.hasError) {
        debugPrint('[Camera] Initialization failed: ${cameraController.value.errorDescription}');
        await cameraController.dispose();
        if (mounted) {
          setState(() {
            _cameraUiState = _CameraUiState.unavailable;
          });
        }
        return;
      }

      _controller = cameraController;
      debugPrint('[Camera] Initialized');

      if (mounted) {
        setState(() {
          _cameraUiState = _CameraUiState.ready;
        });
      }
    } catch (e) {
      debugPrint('[Camera] Initialization error: $e');
      _controller?.dispose();
      _controller = null;
      if (mounted) {
        if (e.toString().toLowerCase().contains('permission')) {
          _denialCount++;
          setState(() {
            _cameraUiState = _denialCount >= 2
                ? _CameraUiState.permanentlyDenied
                : _CameraUiState.denied;
          });
        } else {
          setState(() {
            _cameraUiState = _CameraUiState.unavailable;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    debugPrint('[Camera] Disposed');
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _wasCameraActive = _cameraUiState == _CameraUiState.ready;
      _controller?.dispose();
      _controller = null;
      if (_wasCameraActive && mounted) {
        setState(() {
          _cameraUiState = _CameraUiState.idle;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_wasCameraActive) {
        _wasCameraActive = false;
        if (mounted) {
          _startCamera();
        }
      }
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
    if (_controller == null || !_controller!.value.isInitialized || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final XFile image = await _controller!.takePicture();

      final String pageId = const Uuid().v4();

      final page = ScannedPage(
        id: pageId,
        originalPath: image.path,
        processedFile: File(image.path),
      );

      if (mounted) {
        Provider.of<ScanProvider>(context, listen: false).addPage(page);
      }

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
    if (widget.appendMode) {
      Navigator.pop(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BatchCropScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    switch (_cameraUiState) {
      case _CameraUiState.idle:
        return _buildIdleView();
      case _CameraUiState.requesting:
        return _buildLoadingView();
      case _CameraUiState.ready:
        return _buildCameraView();
      case _CameraUiState.denied:
        return _buildDeniedView();
      case _CameraUiState.permanentlyDenied:
        return _buildPermanentlyDeniedView();
      case _CameraUiState.unavailable:
        return _buildUnavailableView();
    }
  }

  Widget _buildIdleView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.document_scanner, color: Colors.white70, size: 64),
            ),
            const SizedBox(height: 28),
            const Text(
              'Scan Documents',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Position your document in frame and capture clear, high-quality scans.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Start Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text('Go Back', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 20),
          Text(
            'Starting camera...',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white70, size: 64),
            ),
            const SizedBox(height: 28),
            const Text(
              'Camera Permission Needed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'SnapScanner needs camera access to scan documents.\n\nPlease grant permission to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text('Go Back', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermanentlyDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white70, size: 64),
            ),
            const SizedBox(height: 28),
            const Text(
              'Camera Permission Needed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Camera permission is permanently denied.\n\nTo use the scanner, please go to:\nSettings > Apps > SnapScanner > Permissions\nand enable Camera.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white70, size: 64),
            ),
            const SizedBox(height: 28),
            const Text(
              'Camera Not Available',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A camera is required to use the Scan PDF feature.\n\nPlease use "Image to PDF" to select images from your gallery instead.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    final controller = _controller;
    debugPrint('[Camera] Building preview');

    if (controller == null) {
      debugPrint('[Camera] Controller null');
      return _buildLoadingView();
    }

    if (!controller.value.isInitialized) {
      return _buildLoadingView();
    }

    if (controller.value.hasError) {
      debugPrint('[Camera] Initialization failed');
      return _buildCameraErrorView();
    }

    return Stack(
      children: [
        SizedBox.expand(
          child: CameraPreview(controller),
        ),
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
        Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Column(
            children: [
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
                                  // 60px thumbnail: don't decode the full photo.
                                  image: ResizeImage(FileImage(page.displayFile), width: 180),
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
                  const SizedBox(width: 48),
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
    );
  }

  Widget _buildCameraErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline, color: Colors.white70, size: 64),
            ),
            const SizedBox(height: 28),
            const Text(
              'Camera Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The camera encountered an error.\nPlease try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _startCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

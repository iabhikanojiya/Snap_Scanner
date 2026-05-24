import 'dart:io';

class ScannedPage {
  final String id;
  final String originalPath; // Initial capture/selection
  File? processedFile; // Optimized/cropped/filtered version

  ScannedPage({
    required this.id,
    required this.originalPath,
    this.processedFile,
  });

  File get displayFile => processedFile ?? File(originalPath);
}

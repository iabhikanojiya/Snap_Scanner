import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'file_utils.dart';

class ImageUtils {
  
  static Future<File> optimizeImage(File file) async {
    final bytes = await file.readAsBytes();
    final decodedImage = await compute(img.decodeImage, bytes);

    if (decodedImage == null) return file;

    // Resize if width > 1080
    img.Image processedImage = decodedImage;
    if (processedImage.width > 1080) {
      processedImage = img.copyResize(processedImage, width: 1080);
    }

    // Compress to JPEG 75%
    final jpg = await compute(_encodeJpg, processedImage);
    
    final tempFile = await FileUtils.createTempFile(extension: 'jpg');
    await tempFile.writeAsBytes(jpg);
    
    return tempFile;
  }

  static List<int> _encodeJpg(img.Image image) {
    return img.encodeJpg(image, quality: 75);
  }

  // Filter Logic
  static Future<File> applyFilter(File file, FilterType type) async {
    if (type == FilterType.original) return file;

    final bytes = await file.readAsBytes();
    final decodedImage = await compute(img.decodeImage, bytes);
    
    if (decodedImage == null) return file;

    img.Image filtered;
    
    switch (type) {
      case FilterType.grayscale:
        filtered = img.grayscale(decodedImage);
        break;
      case FilterType.bw:
         filtered = img.grayscale(decodedImage);
         // Simple threshold for B&W
         filtered = img.luminanceThreshold(filtered, threshold: 0.5); 
        break;
      case FilterType.enhance:
         // Increase contrast
         filtered = img.contrast(decodedImage, contrast: 120);
         break;
      default:
        filtered = decodedImage;
    }
    
    final jpg = await compute(_encodeJpg, filtered);
    final tempFile = await FileUtils.createTempFile(extension: 'jpg');
    await tempFile.writeAsBytes(jpg);
    return tempFile;
  }
}

enum FilterType {
  original,
  grayscale,
  bw,
  enhance
}

import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'file_utils.dart';

class ImageUtils {

  static Future<File> optimizeImage(File file) async {
    final bytes = await file.readAsBytes();
    final decodedImage = await compute(img.decodeImage, bytes);

    if (decodedImage == null) return file;

    img.Image processedImage = decodedImage;
    if (processedImage.width > 1080) {
      processedImage = img.copyResize(processedImage, width: 1080);
    }

    final jpg = await compute(_encodeJpg, processedImage);

    final permFile = await FileUtils.createPermanentFile(extension: 'jpg');
    await permFile.writeAsBytes(jpg);

    return permFile;
  }

  static List<int> _encodeJpg(img.Image image) {
    return img.encodeJpg(image, quality: 75);
  }

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
         filtered = img.luminanceThreshold(filtered, threshold: 0.5);
        break;
      case FilterType.enhance:
         filtered = img.contrast(decodedImage, contrast: 120);
         break;
      default:
        filtered = decodedImage;
    }

    final jpg = await compute(_encodeJpg, filtered);
    final permFile = await FileUtils.createPermanentFile(extension: 'jpg');
    await permFile.writeAsBytes(jpg);
    return permFile;
  }
}

enum FilterType {
  original,
  grayscale,
  bw,
  enhance
}

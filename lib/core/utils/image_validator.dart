import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../exceptions/app_exceptions.dart';

class ImageValidator {
  static Future<File> validateAndCopyToPermanent(
      File sourceFile, String permanentDirPath) async {
    await _validateFile(sourceFile);

    final dir = Directory(permanentDirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final fileName = sourceFile.path.split('/').last;
    final destPath = '${dir.path}/$fileName';
    final destFile = File(destPath);

    if (await destFile.exists()) {
      return destFile;
    }

    await sourceFile.copy(destPath);
    return destFile;
  }

  static Future<void> _validateFile(File file) async {
    if (!await file.exists()) {
      throw MissingImageException(
        technicalMessage: 'File not found: ${file.path}',
      );
    }

    final fileStat = await file.stat();
    if (fileStat.size <= 0) {
      throw MissingImageException(
        technicalMessage: 'File is empty: ${file.path}',
      );
    }

    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw MissingImageException(
          technicalMessage: 'File bytes are empty: ${file.path}',
        );
      }

      final decoded = await compute(img.decodeImage, bytes);
      if (decoded == null) {
        throw MissingImageException(
          technicalMessage: 'Could not decode image: ${file.path}',
        );
      }

      if (decoded.width <= 0 || decoded.height <= 0) {
        throw MissingImageException(
          technicalMessage: 'Invalid dimensions for: ${file.path}',
        );
      }
    } on AppException {
      rethrow;
    } catch (e) {
      throw MissingImageException(
        technicalMessage: 'Failed to read file: ${file.path} - $e',
      );
    }
  }

  static Future<Uint8List> readValidatedBytes(File file) async {
    await _validateFile(file);
    return file.readAsBytes();
  }
}

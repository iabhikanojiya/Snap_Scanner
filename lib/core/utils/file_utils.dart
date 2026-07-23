import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class FileUtils {
  static const Uuid _uuid = Uuid();

  static Future<String> getAppDocPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> createPermanentFile({String? extension}) async {
    final path = await getAppDocPath();
    final processedDir = Directory('$path/ProcessedImages');
    if (!await processedDir.exists()) {
      await processedDir.create(recursive: true);
    }
    final fileName = '${_uuid.v4()}.${extension ?? "jpg"}';
    return File('${processedDir.path}/$fileName');
  }

  static Future<void> clearProcessedFiles() async {
    final path = await getAppDocPath();
    final processedDir = Directory('$path/ProcessedImages');
    if (await processedDir.exists()) {
      try {
        await processedDir.delete(recursive: true);
      } catch (e) {
        debugPrint('Error clearing processed files: $e');
      }
    }
  }
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class FileUtils {
  static const Uuid _uuid = Uuid();

  static Future<String> getAppTempPath() async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  static Future<String> getAppDocPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> createTempFile({String? extension}) async {
    final path = await getAppTempPath();
    final fileName = '${_uuid.v4()}.${extension ?? "jpg"}';
    return File('$path/$fileName');
  }

  static Future<void> clearTempFiles() async {
    final tempDir = await getTemporaryDirectory();
    if (tempDir.existsSync()) {
      tempDir.listSync().forEach((FileSystemEntity entity) {
        if (entity is File) {
          try {
            entity.deleteSync();
          } catch (e) {
            print("Error deleting temp file: $e");
          }
        }
      });
    }
  }
}

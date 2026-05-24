import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class StorageService {
  static Future<String> getAppDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final pdfToolsDir = Directory(p.join(directory.path, 'PDFTools'));
    
    if (!await pdfToolsDir.exists()) {
      await pdfToolsDir.create(recursive: true);
    }
    
    return pdfToolsDir.path;
  }

  static Future<File> savePdfFile(String fileName, List<int> bytes) async {
    final dirPath = await getAppDirectory();
    final filePath = p.join(dirPath, fileName.endsWith('.pdf') ? fileName : '$fileName.pdf');
    final file = File(filePath);
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<String> renameFile(String oldPath, String newName) async {
    final file = File(oldPath);
    if (await file.exists()) {
      final dir = p.dirname(oldPath);
      final sanitizedNewName = newName.endsWith('.pdf') ? newName : '$newName.pdf';
      final newPath = p.join(dir, sanitizedNewName);
      await file.rename(newPath);
      return newPath;
    }
    return oldPath;
  }
}

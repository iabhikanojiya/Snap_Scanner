import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

class PdfLockService {
  static Future<File> lockPdf({
    required String sourcePath,
    required String password,
    required String outputName,
  }) async {
    final lockedBytes = await compute(_lockPdfIsolate, {
      'sourcePath': sourcePath,
      'password': password,
    });

    final file = await StorageService.savePdfFile(outputName, lockedBytes);

    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: outputName.endsWith('.pdf') ? outputName : '$outputName.pdf',
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
      toolType: 'lock_pdf',
    );
    await DatabaseService.insertFile(pdfModel);

    return file;
  }

  static List<int> _lockPdfIsolate(Map<String, dynamic> params) {
    final String sourcePath = params['sourcePath'];
    final String password = params['password'];

    final sourceFile = File(sourcePath);
    final sourceBytes = sourceFile.readAsBytesSync();

    final PdfDocument document = PdfDocument(inputBytes: sourceBytes);
    document.security.userPassword = password;
    document.security.ownerPassword = password;

    final List<int> lockedBytes = document.saveSync();
    document.dispose();

    return lockedBytes;
  }
}

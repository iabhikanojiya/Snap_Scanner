import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

enum PdfCompressQuality {
  high,   // normal compression
  medium, // normal compression
  low     // best compression
}

class PdfCompressService {
  static Future<File> compressPdf({
    required String sourcePath,
    required PdfCompressQuality quality,
    required String outputName,
  }) async {
    // Run the CPU intensive compression operation in a background isolate
    final compressedBytes = await compute(_compressPdfIsolate, {
      'sourcePath': sourcePath,
      'quality': quality.index,
    });
    
    // Save to local storage
    final file = await StorageService.savePdfFile(outputName, compressedBytes);
    
    // Insert metadata into local database
    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: outputName.endsWith('.pdf') ? outputName : '$outputName.pdf',
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
      toolType: 'compress_pdf',
    );
    await DatabaseService.insertFile(pdfModel);
    
    return file;
  }

  static List<int> _compressPdfIsolate(Map<String, dynamic> params) {
    final String sourcePath = params['sourcePath'];
    final int qualityIndex = params['quality'];
    final PdfCompressQuality quality = PdfCompressQuality.values[qualityIndex];

    final sourceFile = File(sourcePath);
    final sourceBytes = sourceFile.readAsBytesSync();
    
    // Load existing document
    final PdfDocument document = PdfDocument(inputBytes: sourceBytes);
    
    // Disable incremental updates to enforce complete rebuild and compression
    document.fileStructure.incrementalUpdate = false;
    
    // Map compression levels
    switch (quality) {
      case PdfCompressQuality.high:
        document.compressionLevel = PdfCompressionLevel.normal;
        break;
      case PdfCompressQuality.medium:
        document.compressionLevel = PdfCompressionLevel.normal;
        break;
      case PdfCompressQuality.low:
        document.compressionLevel = PdfCompressionLevel.best;
        break;
    }
    
    // Save compressed bytes
    final List<int> compressedBytes = document.saveSync();
    document.dispose();
    
    return compressedBytes;
  }
}

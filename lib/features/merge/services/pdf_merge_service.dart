import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

class PdfMergeService {
  static Future<File> mergePdfs({
    required List<String> filePaths,
    required String outputName,
  }) async {
    // Run the CPU intensive merging operation in a background isolate
    final mergedBytes = await compute(_mergePdfsIsolate, filePaths);
    
    // Save to local storage
    final file = await StorageService.savePdfFile(outputName, mergedBytes);
    
    // Insert metadata into local database
    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: outputName.endsWith('.pdf') ? outputName : '$outputName.pdf',
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
      toolType: 'merge_pdf',
    );
    await DatabaseService.insertFile(pdfModel);
    
    return file;
  }

  static List<int> _mergePdfsIsolate(List<String> filePaths) {
    final PdfDocument newDocument = PdfDocument();
    
    for (final path in filePaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      
      final bytes = file.readAsBytesSync();
      final PdfDocument loadedDocument = PdfDocument(inputBytes: bytes);
      
      PdfSection? section;
      for (int i = 0; i < loadedDocument.pages.count; i++) {
        final PdfTemplate template = loadedDocument.pages[i].createTemplate();
        
        // Add a section to preserve page size and margins
        if (section == null || section.pageSettings.size != template.size) {
          section = newDocument.sections!.add();
          section.pageSettings.size = template.size;
          section.pageSettings.margins.all = 0;
        }
        
        section.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
      }
      
      loadedDocument.dispose();
    }
    
    final List<int> mergedBytes = newDocument.saveSync();
    newDocument.dispose();
    return mergedBytes;
  }
}

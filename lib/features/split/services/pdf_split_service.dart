import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

class PdfSplitService {
  static Future<File> splitPdf({
    required String sourcePath,
    required List<int> selectedPageIndices,
    required String outputName,
  }) async {
    // Run the CPU intensive splitting operation in a background isolate
    final splitBytes = await compute(_splitPdfIsolate, {
      'sourcePath': sourcePath,
      'selectedPageIndices': selectedPageIndices,
    });
    
    // Save to local storage
    final file = await StorageService.savePdfFile(outputName, splitBytes);
    
    // Insert metadata into local database
    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: outputName.endsWith('.pdf') ? outputName : '$outputName.pdf',
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
      toolType: 'split_pdf',
    );
    await DatabaseService.insertFile(pdfModel);
    
    return file;
  }

  static List<int> _splitPdfIsolate(Map<String, dynamic> params) {
    final String sourcePath = params['sourcePath'];
    final List<int> selectedPageIndices = List<int>.from(params['selectedPageIndices']);
    
    final sourceFile = File(sourcePath);
    final sourceBytes = sourceFile.readAsBytesSync();
    
    final PdfDocument sourceDoc = PdfDocument(inputBytes: sourceBytes);
    final PdfDocument targetDoc = PdfDocument();
    
    PdfSection? section;
    for (final pageIndex in selectedPageIndices) {
      if (pageIndex < 0 || pageIndex >= sourceDoc.pages.count) continue;
      
      final PdfTemplate template = sourceDoc.pages[pageIndex].createTemplate();
      
      // Preserve original page size and zero out margins
      if (section == null || section.pageSettings.size != template.size) {
        section = targetDoc.sections!.add();
        section.pageSettings.size = template.size;
        section.pageSettings.margins.all = 0;
      }
      
      section.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
    }
    
    final List<int> splitBytes = targetDoc.saveSync();
    targetDoc.dispose();
    sourceDoc.dispose();
    
    return splitBytes;
  }
}

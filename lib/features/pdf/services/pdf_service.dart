import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';
import '../../../core/models/scanned_page.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

class PdfService {
  static Future<File> generatePdf({
    required String fileName,
    required List<ScannedPage> pages,
    required PdfPageFormat format,
  }) async {
    final pdf = pw.Document();

    for (var page in pages) {
      final imageFile = page.displayFile;
      final image = pw.MemoryImage(
        imageFile.readAsBytesSync(),
      );

      pdf.addPage(
        pw.Page(
          pageFormat: format,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    
    // Save file locally
    final file = await StorageService.savePdfFile(fileName, bytes);
    
    // Save metadata to database
    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: fileName,
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
    );
    
    await DatabaseService.insertFile(pdfModel);
    
    return file;
  }
}

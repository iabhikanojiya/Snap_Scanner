import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';
import '../../../core/models/scanned_page.dart';
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/image_validator.dart';
import '../../../core/exceptions/app_exceptions.dart';

class PdfService {
  static Future<File> generatePdf({
    required String fileName,
    required List<ScannedPage> pages,
    required PdfPageFormat format,
    required String toolType,
    void Function(String step)? onProgress,
  }) async {
    onProgress?.call('validating');

    final pdf = pw.Document();

    for (int i = 0; i < pages.length; i++) {
      onProgress?.call('processing_page');

      final page = pages[i];
      final file = page.processedFile ?? File(page.originalPath);

      try {
        final bytes = await ImageValidator.readValidatedBytes(file);
        final image = pw.MemoryImage(bytes);

        pdf.addPage(
          pw.Page(
            pageFormat: format,
            margin: pw.EdgeInsets.zero,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(image, fit: pw.BoxFit.contain),
              );
            },
          ),
        );
      } on AppException {
        rethrow;
      } catch (e) {
        throw ImageProcessingException(
          pageIndex: i + 1,
          technicalMessage: 'Failed to process page ${i + 1}: $e',
        );
      }
    }

    onProgress?.call('saving');
    final bytes = await pdf.save();

    final file = await StorageService.savePdfFile(fileName, bytes);

    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: fileName,
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
      toolType: toolType,
    );

    await DatabaseService.insertFile(pdfModel);

    onProgress?.call('done');
    return file;
  }
}

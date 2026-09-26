import 'dart:io';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
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
    /// Existing PDF whose pages go before the new pages.
    String? prependPdfPath,
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
    List<int> bytes = await pdf.save();
    if (prependPdfPath != null) {
      final existing = await File(prependPdfPath).readAsBytes();
      bytes = await compute(_prependPdf, (existing, Uint8List.fromList(bytes)));
    }

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

  /// Returns a PDF with all pages of `job.$1` followed by all pages of `job.$2`.
  static List<int> _prependPdf((Uint8List, Uint8List) job) {
    final output = sf.PdfDocument();
    sf.PdfSection? section;
    for (final bytes in [job.$1, job.$2]) {
      final source = sf.PdfDocument(inputBytes: bytes);
      for (var i = 0; i < source.pages.count; i++) {
        final template = source.pages[i].createTemplate();
        if (section == null || section.pageSettings.size != template.size) {
          section = output.sections!.add();
          section.pageSettings.size = template.size;
          section.pageSettings.margins.all = 0;
        }
        section.pages.add().graphics.drawPdfTemplate(template, const Offset(0, 0));
      }
      source.dispose();
    }
    final result = output.saveSync();
    output.dispose();
    return result;
  }
}

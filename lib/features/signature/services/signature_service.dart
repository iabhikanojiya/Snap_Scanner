import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

class SignaturePlacement {
  final int pageIndex;
  final double x;
  final double y;
  final double width;

  SignaturePlacement({
    required this.pageIndex,
    required this.x,
    required this.y,
    this.width = 200,
  });

  Map<String, dynamic> toMap() => {
    'pageIndex': pageIndex,
    'x': x,
    'y': y,
    'width': width,
  };
}

class SignatureService {
  static Future<File> saveSignatureAsImage({
    required ui.Image image,
    required String outputName,
  }) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to capture signature');

    final bytes = byteData.buffer.asUint8List();

    final directory = await getApplicationDocumentsDirectory();
    final signaturesDir = Directory(p.join(directory.path, 'Signatures'));
    if (!await signaturesDir.exists()) {
      await signaturesDir.create(recursive: true);
    }

    final fileName = outputName.endsWith('.png') ? outputName : '$outputName.png';
    final file = File(p.join(signaturesDir.path, fileName));
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<File> addSignaturesToPdf({
    required String sourcePdfPath,
    required ui.Image signatureImage,
    required List<SignaturePlacement> placements,
    required String outputName,
  }) async {
    if (placements.isEmpty) throw Exception('No signature placements');

    final pngBytes = await signatureImage.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes == null) throw Exception('Failed to capture signature');

    final placementsData = placements.map((p) => p.toMap()).toList();

    final result = await compute(_addSignaturesIsolate, {
      'sourcePdfPath': sourcePdfPath,
      'pngBytes': pngBytes.buffer.asUint8List(),
      'placements': placementsData,
    });

    final file = await StorageService.savePdfFile(outputName, result);

    final pdfModel = PdfFileModel(
      id: const Uuid().v4(),
      name: outputName.endsWith('.pdf') ? outputName : '$outputName.pdf',
      path: file.path,
      size: await file.length(),
      createdAt: DateTime.now(),
      toolType: 'signature_pdf',
    );
    await DatabaseService.insertFile(pdfModel);

    return file;
  }

  static List<int> _addSignaturesIsolate(Map<String, dynamic> params) {
    final sourcePath = params['sourcePdfPath'] as String;
    final pngBytes = List<int>.from(params['pngBytes']);
    final placements = List<Map<String, dynamic>>.from(params['placements']);

    final sourceBytes = File(sourcePath).readAsBytesSync();
    final document = PdfDocument(inputBytes: sourceBytes);

    final signature = PdfBitmap(pngBytes);
    final aspectRatio = signature.width / signature.height;

    for (final placement in placements) {
      final pageIndex = (placement['pageIndex'] as int).clamp(0, document.pages.count - 1);
      final posX = placement['x'] as double;
      final posY = placement['y'] as double;
      final sigWidth = placement['width'] as double;

      final page = document.pages[pageIndex];
      final template = page.createTemplate();
      final pageWidth = template.size.width;
      final pageHeight = template.size.height;
      final sigHeight = sigWidth / aspectRatio;

      final x = posX * pageWidth - sigWidth / 2;
      final y = posY * pageHeight - sigHeight / 2;

      page.graphics.drawImage(
        signature,
        Rect.fromLTWH(x, y, sigWidth, sigHeight),
      );
    }

    final result = document.saveSync();
    document.dispose();

    return result;
  }

  @Deprecated('Use addSignaturesToPdf instead')
  static Future<File> addSignatureToPdf({
    required String sourcePdfPath,
    required ui.Image signatureImage,
    required int pageNumber,
    required String outputName,
    double positionX = 0.3,
    double positionY = 0.7,
    double signatureWidth = 200,
  }) async {
    return addSignaturesToPdf(
      sourcePdfPath: sourcePdfPath,
      signatureImage: signatureImage,
      placements: [SignaturePlacement(
        pageIndex: pageNumber,
        x: positionX,
        y: positionY,
        width: signatureWidth,
      )],
      outputName: outputName,
    );
  }
}

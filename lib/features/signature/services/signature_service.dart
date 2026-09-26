import 'dart:async';
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

  /// Clockwise rotation in degrees around the signature's centre.
  final double rotation;

  SignaturePlacement({
    required this.pageIndex,
    required this.x,
    required this.y,
    this.width = 200,
    this.rotation = 0,
  });

  Map<String, dynamic> toMap() => {
    'pageIndex': pageIndex,
    'x': x,
    'y': y,
    'width': width,
    'rotation': rotation,
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
      final rotation = (placement['rotation'] as num?)?.toDouble() ?? 0;

      // Draw around the centre so rotation (clockwise, like the preview)
      // pivots on the middle of the signature.
      final graphics = page.graphics;
      final state = graphics.save();
      graphics.translateTransform(posX * pageWidth, posY * pageHeight);
      if (rotation != 0) graphics.rotateTransform(rotation);
      graphics.drawImage(
        signature,
        Rect.fromLTWH(-sigWidth / 2, -sigHeight / 2, sigWidth, sigHeight),
      );
      graphics.restore(state);
    }

    final result = document.saveSync();
    document.dispose();

    return result;
  }

  static Future<Directory> _getSignaturesDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    final signaturesDir = Directory(p.join(directory.path, 'Signatures'));
    if (!await signaturesDir.exists()) {
      await signaturesDir.create(recursive: true);
    }
    return signaturesDir;
  }

  static Future<List<File>> getSavedSignatures() async {
    final signaturesDir = await _getSignaturesDirectory();
    final files = signaturesDir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<bool> hasSavedSignatures() async {
    final sigs = await getSavedSignatures();
    return sigs.isNotEmpty;
  }

  static Future<ui.Image> loadSignatureImage(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (image) => completer.complete(image));
    return completer.future;
  }

  static Future<File> addSignaturesToPdfWithStrokes({
    required String sourcePdfPath,
    required List<Map<String, dynamic>> strokeData,
    required List<SignaturePlacement> placements,
    required String outputName,
  }) async {
    if (placements.isEmpty) throw Exception('No signature placements');
    if (strokeData.isEmpty) throw Exception('No stroke data');

    final placementsData = placements.map((p) => p.toMap()).toList();

    final result = await compute(_addStrokesIsolate, {
      'sourcePdfPath': sourcePdfPath,
      'strokeData': strokeData,
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

  static List<int> _addStrokesIsolate(Map<String, dynamic> params) {
    final sourcePath = params['sourcePdfPath'] as String;
    final strokeData = List<Map<String, dynamic>>.from(params['strokeData']);
    final placements = List<Map<String, dynamic>>.from(params['placements']);

    final sourceBytes = File(sourcePath).readAsBytesSync();
    final document = PdfDocument(inputBytes: sourceBytes);

    double minX = double.infinity, minY = double.infinity;
    double maxX = 0, maxY = 0;
    for (final stroke in strokeData) {
      final points = List<Map<String, dynamic>>.from(stroke['points']);
      for (final pt in points) {
        final dx = pt['x'] as double;
        final dy = pt['y'] as double;
        if (dx < minX) minX = dx;
        if (dy < minY) minY = dy;
        if (dx > maxX) maxX = dx;
        if (dy > maxY) maxY = dy;
      }
    }
    const padding = 15.0;
    final strokeW = maxX - minX + padding * 2;
    final strokeH = maxY - minY + padding * 2;

    for (final placement in placements) {
      final pageIndex = (placement['pageIndex'] as int).clamp(0, document.pages.count - 1);
      final posX = placement['x'] as double;
      final posY = placement['y'] as double;
      final sigWidth = placement['width'] as double;

      final page = document.pages[pageIndex];
      final template = page.createTemplate();
      final pageWidth = template.size.width;
      final pageHeight = template.size.height;
      final sigHeight = sigWidth * (strokeH / strokeW);
      final rotation = (placement['rotation'] as num?)?.toDouble() ?? 0;

      // Strokes are drawn relative to the signature's centre so rotation
      // pivots on it (clockwise, like the preview).
      final graphics = page.graphics;
      final state = graphics.save();
      graphics.translateTransform(posX * pageWidth, posY * pageHeight);
      if (rotation != 0) graphics.rotateTransform(rotation);
      final originX = -sigWidth / 2;
      final originY = -sigHeight / 2;

      for (final stroke in strokeData) {
        final points = List<Map<String, dynamic>>.from(stroke['points']);
        if (points.isEmpty) continue;

        final colorValue = stroke['color'] as int;
        final strokeWidth = stroke['width'] as double;
        final scaledWidth = strokeWidth * (sigWidth / strokeW);

        final r = (colorValue >> 16) & 0xFF;
        final g = (colorValue >> 8) & 0xFF;
        final b = colorValue & 0xFF;

        final pdfPath = PdfPath();
        final first = points.first;
        double prevX = originX + ((first['x'] as double) - minX + padding) / strokeW * sigWidth;
        double prevY = originY + ((first['y'] as double) - minY + padding) / strokeH * sigHeight;

        for (int i = 1; i < points.length; i++) {
          final pt = points[i];
          final curX = originX + ((pt['x'] as double) - minX + padding) / strokeW * sigWidth;
          final curY = originY + ((pt['y'] as double) - minY + padding) / strokeH * sigHeight;
          pdfPath.addLine(Offset(prevX, prevY), Offset(curX, curY));
          prevX = curX;
          prevY = curY;
        }

        graphics.drawPath(
          pdfPath,
          pen: PdfPen(PdfColor(r, g, b),
            width: scaledWidth,
            lineCap: PdfLineCap.round,
            lineJoin: PdfLineJoin.round,
          ),
        );
      }
      graphics.restore(state);
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

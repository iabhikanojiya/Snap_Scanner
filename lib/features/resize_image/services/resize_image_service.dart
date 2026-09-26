import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

enum ResizeFormat { jpeg, png }

class ResizeImageService {
  /// Upright pixel size of [file] (EXIF rotation applied), decoded off the
  /// UI thread. Returns null if the file isn't a readable image.
  static Future<(int, int)?> readDimensions(File file) async {
    final bytes = await file.readAsBytes();
    return compute(_dimensionsIsolate, bytes);
  }

  static (int, int)? _dimensionsIsolate(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    // Orientations 5–8 are rotated by 90°, so width and height swap.
    final orientation = decoded.exif.imageIfd.orientation ?? 1;
    return orientation >= 5 && orientation <= 8
        ? (decoded.height, decoded.width)
        : (decoded.width, decoded.height);
  }

  static Future<File> resizeImage({
    required File sourceFile,
    required int width,
    required int height,
    required ResizeFormat format,
    int quality = 85,
    String? outputName,
  }) async {
    final bytes = await sourceFile.readAsBytes();
    final result = await compute(_resizeIsolate, {
      'bytes': bytes,
      'width': width,
      'height': height,
      'format': format.index,
      'quality': quality,
    });

    final directory = await getApplicationDocumentsDirectory();
    final resizedDir = Directory(p.join(directory.path, 'ResizedImages'));
    if (!await resizedDir.exists()) {
      await resizedDir.create(recursive: true);
    }

    final extension = format == ResizeFormat.jpeg ? 'jpg' : 'png';
    final name = outputName ?? 'Resized_${const Uuid().v4()}';
    final fileName = name.endsWith('.$extension') ? name : '$name.$extension';
    final file = File(p.join(resizedDir.path, fileName));
    await file.writeAsBytes(Uint8List.fromList(result));
    return file;
  }

  static List<int> _resizeIsolate(Map<String, dynamic> params) {
    final bytes = Uint8List.fromList(List<int>.from(params['bytes']));
    final width = params['width'] as int;
    final height = params['height'] as int;
    final formatIndex = params['format'] as int;
    final quality = params['quality'] as int;
    final format = ResizeFormat.values[formatIndex];

    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Failed to decode image');

    // Apply the camera's EXIF rotation so the output matches what the user
    // sees (and the dimensions shown on screen).
    final upright = img.bakeOrientation(decoded);
    final resized = img.copyResize(upright, width: width, height: height);

    if (format == ResizeFormat.jpeg) {
      return img.encodeJpg(resized, quality: quality);
    } else {
      return img.encodePng(resized);
    }
  }
}

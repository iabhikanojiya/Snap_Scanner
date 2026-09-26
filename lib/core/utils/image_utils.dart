import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'file_utils.dart';

class ImageUtils {

  static Future<File> optimizeImage(File file) async {
    final bytes = await file.readAsBytes();
    final decodedImage = await compute(img.decodeImage, bytes);

    if (decodedImage == null) return file;

    img.Image processedImage = decodedImage;
    if (processedImage.width > 1080) {
      processedImage = img.copyResize(processedImage, width: 1080);
    }

    final jpg = await compute(_encodeJpg, processedImage);

    final permFile = await FileUtils.createPermanentFile(extension: 'jpg');
    await permFile.writeAsBytes(jpg);

    return permFile;
  }

  static List<int> _encodeJpg(img.Image image) {
    return img.encodeJpg(image, quality: 75);
  }

  static Future<File> applyFilter(File file, FilterType type) async {
    if (type == FilterType.original) return file;

    final bytes = await file.readAsBytes();
    final jpg = await compute(_filterAndEncode, (bytes, type));
    if (jpg == null) return file;

    final permFile = await FileUtils.createPermanentFile(extension: 'jpg');
    await permFile.writeAsBytes(jpg);
    return permFile;
  }

  /// Rotates [file] clockwise by [quarterTurns] × 90° and then crops it to
  /// the normalised rect ([left], [top], [right], [bottom] in 0..1 of the
  /// rotated image). Runs off the UI thread.
  static Future<File> cropAndRotate(
    File file, {
    int quarterTurns = 0,
    double left = 0,
    double top = 0,
    double right = 1,
    double bottom = 1,
  }) async {
    final bytes = await file.readAsBytes();
    final jpg = await compute(
      _cropAndRotate,
      (bytes, quarterTurns % 4, left, top, right, bottom),
    );
    if (jpg == null) return file;
    final permFile = await FileUtils.createPermanentFile(extension: 'jpg');
    await permFile.writeAsBytes(jpg);
    return permFile;
  }

  static List<int>? _cropAndRotate(
      (Uint8List, int, double, double, double, double) job) {
    final (bytes, turns, l, t, r, b) = job;
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    if (turns != 0) image = img.copyRotate(image, angle: 90 * turns);
    final x = (l * image.width).round().clamp(0, image.width - 1);
    final y = (t * image.height).round().clamp(0, image.height - 1);
    final w = ((r - l) * image.width).round().clamp(1, image.width - x);
    final h = ((b - t) * image.height).round().clamp(1, image.height - y);
    if (x != 0 || y != 0 || w != image.width || h != image.height) {
      image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    }
    return img.encodeJpg(image, quality: 90);
  }

  /// Finds the document (the largest bright region, e.g. paper on a table)
  /// in [file] after rotating it by [quarterTurns]. Returns the normalised
  /// bounds (left, top, right, bottom in 0..1), or null if no clear document
  /// edge was found.
  static Future<(double, double, double, double)?> detectDocumentBounds(
    File file, {
    int quarterTurns = 0,
  }) async {
    final bytes = await file.readAsBytes();
    return compute(_detectDocumentBounds, (bytes, quarterTurns % 4));
  }

  static (double, double, double, double)? _detectDocumentBounds((Uint8List, int) job) {
    final decoded = img.decodeImage(job.$1);
    if (decoded == null) return null;
    var image = img.bakeOrientation(decoded);
    if (job.$2 != 0) image = img.copyRotate(image, angle: 90 * job.$2);
    const maxSide = 256;
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
    final w = image.width, h = image.height, n = w * h;

    // Luminance + Otsu threshold.
    final lum = Uint8List(n);
    final hist = List<int>.filled(256, 0);
    for (final p in image) {
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      lum[p.y * w + p.x] = l;
      hist[l]++;
    }
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, best = 0.0, threshold = 128;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = n - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        threshold = t;
      }
    }

    // Largest connected bright component (4-neighbour flood fill).
    final visited = Uint8List(n);
    final stack = <int>[];
    var bestCount = 0, bx0 = 0, by0 = 0, bx1 = w - 1, by1 = h - 1;
    for (var start = 0; start < n; start++) {
      if (visited[start] == 1 || lum[start] <= threshold) continue;
      var count = 0, x0 = w, y0 = h, x1 = 0, y1 = 0;
      visited[start] = 1;
      stack.add(start);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final x = i % w, y = i ~/ w;
        count++;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        for (final j in [
          if (x > 0) i - 1,
          if (x < w - 1) i + 1,
          if (y > 0) i - w,
          if (y < h - 1) i + w,
        ]) {
          if (visited[j] == 0 && lum[j] > threshold) {
            visited[j] = 1;
            stack.add(j);
          }
        }
      }
      if (count > bestCount) {
        bestCount = count;
        bx0 = x0;
        by0 = y0;
        bx1 = x1;
        by1 = y1;
      }
    }

    final boxArea = (bx1 - bx0 + 1) * (by1 - by0 + 1);
    // Too small to be the page, or basically the whole photo: no clear edge.
    if (bestCount < n * 0.12 || boxArea > n * 0.97) return null;

    const inset = 0.005;
    return (
      (bx0 / w + inset).clamp(0.0, 1.0),
      (by0 / h + inset).clamp(0.0, 1.0),
      ((bx1 + 1) / w - inset).clamp(0.0, 1.0),
      ((by1 + 1) / h - inset).clamp(0.0, 1.0),
    );
  }

  /// Small JPEG thumbnails of [file] with each of [types] applied, for the
  /// filter picker. Runs off the UI thread.
  static Future<Map<FilterType, Uint8List>> buildFilterPreviews(
    File file,
    List<FilterType> types, {
    int width = 160,
  }) async {
    final bytes = await file.readAsBytes();
    return compute(_buildPreviews, (bytes, types, width));
  }

  static List<int>? _filterAndEncode((Uint8List, FilterType) job) {
    final decoded = img.decodeImage(job.$1);
    if (decoded == null) return null;
    return img.encodeJpg(_filtered(decoded, job.$2), quality: 75);
  }

  static Map<FilterType, Uint8List> _buildPreviews(
      (Uint8List, List<FilterType>, int) job) {
    final decoded = img.decodeImage(job.$1);
    if (decoded == null) return const {};
    final thumb = decoded.width > job.$3 ? img.copyResize(decoded, width: job.$3) : decoded;
    return {
      for (final type in job.$2)
        type: img.encodeJpg(_filtered(img.Image.from(thumb), type), quality: 80),
    };
  }

  /// Applies [type] to [src]. May modify [src] in place.
  static img.Image _filtered(img.Image src, FilterType type) {
    switch (type) {
      case FilterType.original:
        return src;
      case FilterType.enhance:
        return img.contrast(src, contrast: 120);
      case FilterType.magicColor:
        return img.adjustColor(src, contrast: 1.25, saturation: 1.3, brightness: 1.08);
      case FilterType.sharpen:
        return img.convolution(src, filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0]);
      case FilterType.bright:
        return img.adjustColor(src, brightness: 1.2, contrast: 1.05);
      case FilterType.grayscale:
        return img.grayscale(src);
      case FilterType.bw:
        return img.luminanceThreshold(img.grayscale(src), threshold: 0.5);
      case FilterType.sepia:
        return img.sepia(src);
    }
  }
}

enum FilterType {
  original,
  grayscale,
  bw,
  enhance,
  magicColor,
  sharpen,
  bright,
  sepia,
}

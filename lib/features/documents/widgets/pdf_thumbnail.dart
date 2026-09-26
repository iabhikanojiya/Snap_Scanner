import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as px;

import '../../../core/models/pdf_file_model.dart';

/// First-page thumbnails rendered with the existing pdfx package.
/// Renders run one at a time and results are kept in a small in-memory
/// LRU cache, so scrolling or switching tabs never re-renders a PDF.
class PdfThumbnailCache {
  PdfThumbnailCache._();

  static const int _maxEntries = 120;
  static const double _renderWidth = 160;

  static final LinkedHashMap<String, Uint8List?> _cache = LinkedHashMap();
  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static Future<void> _queue = Future.value();

  static String keyFor(PdfFileModel file) => '${file.path}|${file.size}';

  static bool contains(String key) => _cache.containsKey(key);

  static Uint8List? peek(String key) {
    final value = _cache.remove(key);
    _cache[key] = value; // mark as recently used
    return value;
  }

  static Future<Uint8List?> load(String key, String path) {
    if (_cache.containsKey(key)) return SynchronousFuture(peek(key));
    return _inFlight[key] ??= _enqueue(key, path);
  }

  static Future<Uint8List?> _enqueue(String key, String path) {
    final result = _queue.then((_) => _render(path));
    _queue = result.then((_) {});
    return result.then((bytes) {
      _inFlight.remove(key);
      _cache[key] = bytes;
      while (_cache.length > _maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      return bytes;
    });
  }

  static Future<Uint8List?> _render(String path) async {
    px.PdfDocument? doc;
    try {
      if (!await File(path).exists()) return null;
      doc = await px.PdfDocument.openFile(path);
      final page = await doc.getPage(1);
      try {
        final image = await page.render(
          width: _renderWidth,
          height: _renderWidth * page.height / page.width,
          format: px.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
          quality: 75,
        );
        return image?.bytes;
      } finally {
        await page.close();
      }
    } catch (e) {
      // Password-protected or unreadable PDFs fall back to an icon.
      debugPrint('[PdfThumbnail] render failed for $path: $e');
      return null;
    } finally {
      try {
        await doc?.close();
      } catch (_) {}
    }
  }
}

class PdfThumbnail extends StatefulWidget {
  final PdfFileModel file;
  final double width;
  final double height;

  const PdfThumbnail({
    super.key,
    required this.file,
    this.width = 46,
    this.height = 60,
  });

  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  Uint8List? _bytes;
  bool _done = false;

  bool get _isImage => widget.file.toolType == 'resize_image';

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PdfThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (PdfThumbnailCache.keyFor(oldWidget.file) !=
        PdfThumbnailCache.keyFor(widget.file)) {
      _bytes = null;
      _done = false;
      _resolve();
    }
  }

  void _resolve() {
    if (_isImage) return;
    final key = PdfThumbnailCache.keyFor(widget.file);
    if (PdfThumbnailCache.contains(key)) {
      _bytes = PdfThumbnailCache.peek(key);
      _done = true;
      return;
    }
    PdfThumbnailCache.load(key, widget.file.path).then((bytes) {
      if (!mounted || PdfThumbnailCache.keyFor(widget.file) != key) return;
      setState(() {
        _bytes = bytes;
        _done = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget child;
    if (_isImage) {
      child = Image.file(
        File(widget.file.path),
        fit: BoxFit.cover,
        cacheWidth: (widget.width * dpr).round(),
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _placeholder(Icons.image, Colors.pink),
      );
    } else if (_bytes != null) {
      child = Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
      );
    } else {
      child = _placeholder(
        widget.file.toolType == 'lock_pdf' && _done
            ? Icons.lock_outline
            : Icons.picture_as_pdf,
        Colors.red,
      );
    }
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _placeholder(IconData icon, Color color) {
    return ColoredBox(
      color: color.withValues(alpha: 0.08),
      child: Center(child: Icon(icon, color: color, size: 24)),
    );
  }
}

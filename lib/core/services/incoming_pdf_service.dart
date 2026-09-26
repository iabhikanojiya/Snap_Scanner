import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/viewer/screens/pdf_viewer_screen.dart';
import '../navigation/app_navigator.dart';

/// Opens PDFs that other apps send to Snap Scanner ("Open with" / "Share").
/// The native side copies the file locally and passes its path.
class IncomingPdfService {
  IncomingPdfService._();
  static final IncomingPdfService instance = IncomingPdfService._();

  static const _channel = MethodChannel('snap_scanner/incoming_pdf');
  bool _started = false;

  /// Call once after the first frame, when the navigator exists.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPdf' && call.arguments is String) {
        _open(call.arguments as String);
      }
    });
    try {
      final path = await _channel.invokeMethod<String>('getInitialPdf');
      if (path != null) _open(path);
    } on MissingPluginException {
      // Platform without the native handler (tests, web).
    } catch (e) {
      debugPrint('[IncomingPdf] initial check failed: $e');
    }
  }

  void _open(String path) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => PdfViewerScreen(path: path)),
    );
  }
}

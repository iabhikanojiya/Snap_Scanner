import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Service wrapping Google ML Kit Document Scanner for Scan PDF flow.
///
/// This service is Android-only. On iOS it will not be invoked; callers
/// should guard with [Platform.isAndroid] before calling [scanDocuments].
class MlkitDocumentScannerService {
  /// Launches the Google ML Kit Document Scanner and returns scanned image paths.
  ///
  /// Returns:
  /// - `List<String>` with file paths for each scanned page on success.
  /// - `null` if user cancelled or scanner produced no pages (caller should
  ///   treat as cancel – do not navigate or show error).
  /// - Throws only on unexpected failure; callers should catch and show a
  ///   user-friendly message without crashing.
  static Future<List<String>?> scanDocuments() async {
    final options = DocumentScannerOptions(
      documentFormats: const {DocumentFormat.jpeg},
      mode: ScannerMode.full,
      pageLimit: 50,
      isGalleryImport: false,
    );

    final scanner = DocumentScanner(options: options);
    try {
      final DocumentScanningResult result = await scanner.scanDocument();
      // Plugin 0.5.0 maps null images to empty list; treat empty as no result.
      final images = result.images;
      if (images == null || images.isEmpty) {
        debugPrint('[MLKit] Scanner returned no pages');
        return null;
      }
      return images;
    } on PlatformException catch (e) {
      debugPrint('[MLKit] PlatformException: ${e.code} ${e.message}');
      // Android plugin reports cancellation as error with message containing "cancel".
      final msg = e.message?.toLowerCase() ?? '';
      final code = e.code.toLowerCase();
      if (msg.contains('cancel') || code.contains('cancel')) {
        // User cancelled – not an error.
        return null;
      }
      // Real failure – rethrow so caller can show error UI.
      rethrow;
    } catch (e) {
      debugPrint('[MLKit] Unexpected error: $e');
      rethrow;
    } finally {
      try {
        await scanner.close();
      } catch (e) {
        debugPrint('[MLKit] scanner.close failed: $e');
      }
    }
  }
}

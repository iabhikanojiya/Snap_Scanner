import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  Future<void> logAppOpen() => _analytics.logAppOpen();

  Future<void> logScanStarted() =>
      _analytics.logEvent(name: 'scan_started');

  Future<void> logScanCompleted() =>
      _analytics.logEvent(name: 'scan_completed');

  Future<void> logImageToPdfStarted() =>
      _analytics.logEvent(name: 'image_to_pdf_started');

  Future<void> logImageToPdfCompleted() =>
      _analytics.logEvent(name: 'image_to_pdf_completed');

  Future<void> logPdfSaved() =>
      _analytics.logEvent(name: 'pdf_saved');

  Future<void> logPdfShared() =>
      _analytics.logEvent(name: 'pdf_shared');

  Future<void> logPdfDeleted() =>
      _analytics.logEvent(name: 'pdf_deleted');

  Future<void> logMergePdf() =>
      _analytics.logEvent(name: 'merge_pdf');

  Future<void> logSplitPdf() =>
      _analytics.logEvent(name: 'split_pdf');

  Future<void> logCompressPdf() =>
      _analytics.logEvent(name: 'compress_pdf');

  Future<void> logLockPdf() =>
      _analytics.logEvent(name: 'lock_pdf');

  Future<void> logUnlockPdf() =>
      _analytics.logEvent(name: 'unlock_pdf');

  Future<void> logSignatureSaved() =>
      _analytics.logEvent(name: 'signature_saved');

  Future<void> logSignatureUsed() =>
      _analytics.logEvent(name: 'signature_used');

  Future<void> logErrorOccurred({
    required String errorType,
    String? message,
  }) async {
    final params = <String, Object>{'error_type': errorType};
    if (message != null) params['message'] = message;
    await _analytics.logEvent(name: 'error_occurred', parameters: params);
  }
}

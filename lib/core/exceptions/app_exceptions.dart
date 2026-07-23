import 'package:flutter/foundation.dart';

abstract class AppException implements Exception {
  final String userMessage;
  final String? technicalMessage;

  const AppException({
    required this.userMessage,
    this.technicalMessage,
  });

  void log() {
    if (technicalMessage != null) {
      debugPrint('$runtimeType: $technicalMessage');
    }
  }
}

class MissingImageException extends AppException {
  const MissingImageException({
    super.technicalMessage,
    super.userMessage = 'One or more edited images are no longer available.\n\n'
        'This can happen if Android removes temporary files.\n\n'
        'Please crop the affected page again and try creating the PDF.',
  });
}

class PdfGenerationException extends AppException {
  const PdfGenerationException({
    super.technicalMessage,
    super.userMessage = 'Something went wrong while generating your PDF.\n\n'
        'Please try again.\n\n'
        'If the issue continues, reselect the images and recreate the PDF.',
  });
}

class ImageProcessingException extends AppException {
  final int? pageIndex;

  const ImageProcessingException({
    this.pageIndex,
    super.technicalMessage,
    super.userMessage = 'Image could not be processed.',
  });
}

class StorageException extends AppException {
  const StorageException({
    super.technicalMessage,
    super.userMessage = 'Could not save the file to your device.\n\n'
        'Please check your storage space and try again.',
  });
}

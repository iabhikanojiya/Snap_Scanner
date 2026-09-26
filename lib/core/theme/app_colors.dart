import 'package:flutter/material.dart';

/// Shared colours for the tabbed shell (headers, nav, cards).
class AppColors {
  AppColors._();

  /// Medium, soft brand red (matches the app icon) used for the top header
  /// and the selected bottom-nav tab. 4.9:1 contrast with white text.
  static const Color brandRed = Color(0xFFC94141);
  static const Color primary = Color(0xFF3A6BC9);
  // Tool colours (Tools screen icons and matching tool screens).
  static const Color toolScan = Color(0xFF2563EB);
  static const Color toolImageToPdf = Color(0xFF16A34A);
  static const Color toolMerge = Color(0xFFDC2626);
  static const Color toolSplit = Color(0xFFEA580C);
  static const Color toolCompress = Color(0xFF9333EA);
  static const Color toolLock = Color(0xFF1E3A8A);
  static const Color toolSignature = Color(0xFF6D28D9);
  static const Color toolResize = Color(0xFF0D9488);

  static const Color background = Color(0xFFF8F9FA);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1C1F26);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE8EBF0);
}

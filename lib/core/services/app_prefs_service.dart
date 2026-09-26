import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';

/// Small key/value store backed by the existing app database
/// (`app_settings` table), so no extra storage dependency is needed.
class AppPrefsService {
  static const String _onboardingKey = 'onboarding_completed';
  static const String _userNameKey = 'user_name';
  static const String defaultUserName = 'User';

  static Future<String?> _get(String key) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  static Future<void> _set(String key, String value) async {
    final db = await DatabaseService.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<bool> isOnboardingCompleted() async {
    try {
      return await _get(_onboardingKey) == '1';
    } catch (e) {
      // Never block app launch on a storage error.
      debugPrint('[AppPrefs] onboarding flag read failed: $e');
      return true;
    }
  }

  static Future<void> setOnboardingCompleted() async {
    try {
      await _set(_onboardingKey, '1');
    } catch (e) {
      debugPrint('[AppPrefs] onboarding flag write failed: $e');
    }
  }

  static Future<String> getUserName() async {
    final name = await _get(_userNameKey);
    return (name == null || name.trim().isEmpty) ? defaultUserName : name;
  }

  static Future<void> setUserName(String name) => _set(_userNameKey, name.trim());

  /// Number of PDFs created with the app (resized images are not PDFs).
  static Future<int> getPdfCount() async {
    final db = await DatabaseService.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM pdf_files WHERE toolType IS NULL OR toolType != 'resize_image'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}

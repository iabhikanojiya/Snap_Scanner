import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:flutter/services.dart';

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  bool _checkPerformed = false;

  /// Called once on app launch (from HomeScreen after first frame).
  /// Waits ~2.5s to let the UI settle, then checks for an update.
  void checkForUpdates(BuildContext context) {
    if (_checkPerformed) return;
    _checkPerformed = true;

    if (!kReleaseMode) {
      debugPrint('[Update] Skipping check in debug mode');
      return;
    }

    Future.delayed(const Duration(milliseconds: 2500), () {
      _performUpdateCheck(context);
    });
  }

  /// Called from HomeScreen's [WidgetsBindingObserver.didChangeAppLifecycleState]
  /// when the app returns to foreground. Handles the
  /// [UpdateAvailability.developerTriggeredUpdateInProgress] case.
  Future<void> onResume(BuildContext context) async {
    if (!_checkPerformed || !kReleaseMode) return;

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability !=
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        return;
      }

      if (info.installStatus == InstallStatus.downloaded) {
        debugPrint('[Update] Resume: download already completed');
        if (context.mounted) _showUpdateDialog(context);
      } else {
        debugPrint('[Update] Resume: download still in progress');
      }
    } catch (e) {
      debugPrint('[Update] Resume check error: $e');
    }
  }

  Future<void> _performUpdateCheck(BuildContext context) async {
    debugPrint('[Update] Checking...');
    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        debugPrint('[Update] Previous update in progress');
        if (info.installStatus == InstallStatus.downloaded) {
          debugPrint('[Update] Download already completed');
          if (context.mounted) _showUpdateDialog(context);
        } else {
          debugPrint('[Update] Resuming download');
          await _startFlexibleUpdate(context);
        }
        return;
      }

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        debugPrint('[Update] Not available');
        return;
      }

      debugPrint('[Update] Available');

      if (!info.flexibleUpdateAllowed) {
        debugPrint('[Update] Flexible update not allowed');
        return;
      }

      debugPrint('[Update] Flexible update allowed');
      await _startFlexibleUpdate(context);
    } catch (e) {
      debugPrint('[Update] Error: $e');
    }
  }

  Future<void> _startFlexibleUpdate(BuildContext context) async {
    debugPrint('[Update] Download started');
    try {
      final result = await InAppUpdate.startFlexibleUpdate();

      if (result == AppUpdateResult.success) {
        debugPrint('[Update] Download completed');
        if (context.mounted) _showUpdateDialog(context);
      } else if (result == AppUpdateResult.userDeniedUpdate) {
        debugPrint('[Update] User cancelled');
      } else {
        debugPrint('[Update] AppUpdateResult failed');
      }
    } on PlatformException catch (e) {
      if (e.code == 'USER_DENIED_UPDATE') {
        debugPrint('[Update] User cancelled');
      } else {
        debugPrint('[Update] Error: code=${e.code} message=${e.message}');
      }
    } catch (e) {
      debugPrint('[Update] Error: $e');
    }
  }

  void _showUpdateDialog(BuildContext context) {
    showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text('Update Ready'),
        content: const Text(
          'Update downloaded. Restart now to install the latest version.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _completeUpdate();
            },
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeUpdate() async {
    debugPrint('[Update] Restart requested');
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('[Update] Error completing update: $e');
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _checkPerformed = false;
  }
}

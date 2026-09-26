import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Visual tone of an [AppDialog]. Drives the icon badge colour (the primary
/// button is always brand red). Pair every tone with an icon and a clear label
/// so the meaning never relies on colour alone.
enum AppDialogTone { normal, success, warning, error, destructive }

/// Shows [builder] as a bottom-anchored modal with a dimmed backdrop and a
/// subtle fade + slide-up entrance. Drop-in replacement for `showDialog`.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) => builder(dialogContext),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
              .animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Snap Scanner's modern popup: large rounded white card floating at the
/// bottom of the screen, optional icon or illustration, centred title +
/// description, optional custom content, a full-width red pill primary button
/// and an optional secondary text action.
class AppDialog extends StatelessWidget {
  final String title;
  final String? description;
  final IconData? icon;

  /// Replaces the icon badge when a richer visual is wanted.
  final Widget? illustration;

  /// Extra content (text fields, lists…) shown under the description.
  final Widget? content;

  final AppDialogTone tone;

  final String? primaryLabel;

  /// Null disables the primary button (e.g. while saving).
  final VoidCallback? onPrimary;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Shows a close (X) button in the top-right corner when set.
  final VoidCallback? onClose;

  const AppDialog({
    super.key,
    required this.title,
    this.description,
    this.icon,
    this.illustration,
    this.content,
    this.tone = AppDialogTone.normal,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.onClose,
  });

  static const double _radius = 28;

  static Color toneColor(AppDialogTone tone) {
    switch (tone) {
      case AppDialogTone.normal:
        return AppColors.primary;
      case AppDialogTone.success:
        return const Color(0xFF16A34A);
      case AppDialogTone.warning:
        return const Color(0xFFD97706);
      case AppDialogTone.error:
      case AppDialogTone.destructive:
        return const Color(0xFFD92D20);
    }
  }

  /// Soft filled input style used by text fields inside dialogs.
  static InputDecoration inputDecoration({
    String? hintText,
    String? errorText,
    String? suffixText,
  }) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: 1.5),
        );
    return InputDecoration(
      hintText: hintText,
      errorText: errorText,
      suffixText: suffixText,
      counterText: '',
      filled: true,
      fillColor: const Color(0xFFF3F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.brandRed),
      errorBorder: border(toneColor(AppDialogTone.error)),
      focusedErrorBorder: border(toneColor(AppDialogTone.error)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final header = <Widget>[
      if (illustration != null)
        Center(child: illustration!)
      else if (icon != null)
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 30),
          ),
        ),
      if (illustration != null || icon != null) const SizedBox(height: 18),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: -0.2,
          color: AppColors.textPrimary,
        ),
      ),
      if (description != null) ...[
        const SizedBox(height: 8),
        Text(
          description!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      ],
      if (content != null) ...[
        const SizedBox(height: 20),
        content!,
      ],
    ];

    final actions = <Widget>[
      if (primaryLabel != null)
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: onPrimary,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandRed,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.brandRed.withValues(alpha: 0.4),
              disabledForegroundColor: Colors.white,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: Text(primaryLabel!),
          ),
        ),
      if (secondaryLabel != null) ...[
        if (primaryLabel != null) const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: TextButton(
            onPressed: onSecondary,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: Text(secondaryLabel!),
          ),
        ),
      ],
    ];

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(12, 24, 12, 12 + keyboard),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(_radius),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        onClose != null ? 36 : 28,
                        24,
                        actions.isEmpty ? 24 : 16,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: header,
                              ),
                            ),
                          ),
                          if (actions.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            ...actions,
                          ],
                        ],
                      ),
                    ),
                    if (onClose != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: onClose,
                          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable option row for list-style popups (file actions, sort, …).
class AppDialogOption extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;

  /// Optional second line under the label.
  final String? subtitle;

  /// Shows the icon in a tinted square of this colour (e.g. tool colours).
  final Color? iconColor;

  /// Shows a trailing chevron for rows that open another screen.
  final bool showChevron;

  /// Shows the row in red for irreversible actions like Delete.
  final bool destructive;

  /// Highlights the row and shows a check mark (e.g. current sort order).
  final bool selected;

  const AppDialogOption({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.showChevron = false,
    this.destructive = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = destructive || selected
        ? AppColors.brandRed
        : AppColors.textPrimary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? AppColors.brandRed.withValues(alpha: 0.08)
            : const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  if (icon != null && iconColor != null) ...[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor!.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 22, color: iconColor),
                    ),
                    const SizedBox(width: 12),
                  ] else if (icon != null) ...[
                    Icon(icon, size: 20, color: accent),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                            color: accent,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_rounded, size: 20, color: AppColors.brandRed)
                  else if (showChevron)
                    const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

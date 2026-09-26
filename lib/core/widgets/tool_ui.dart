import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'document_icon.dart';

/// Shared building blocks for the tool screens (Merge, Split, Compress, Lock,
/// Resize…) so they share one look: soft white cards, filled inputs, a
/// sticky red primary button and red selection states.

/// White rounded card with an optional section title / subtitle.
class ToolSectionCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const ToolSectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: toolSectionTitleStyle),
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
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

const TextStyle toolSectionTitleStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w700,
  color: AppColors.textPrimary,
);

/// Card showing the chosen file with its tool icon and a "Change" action.
class SelectedFileCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String? meta;
  final VoidCallback? onChange;

  const SelectedFileCard({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    this.meta,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return ToolSectionCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      child: Row(
        children: [
          DocumentIcon(icon: icon, color: color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (meta != null) ...[
                  const SizedBox(height: 3),
                  Text(meta!, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (onChange != null)
            TextButton(
              onPressed: onChange,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brandRed,
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              child: const Text('Change'),
            ),
        ],
      ),
    );
  }
}

/// Soft filled input style for tool screen text fields.
InputDecoration toolInputDecoration({
  String? label,
  String? hint,
  IconData? icon,
  String? suffixText,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1.5]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );
  const error = Color(0xFFD92D20);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon != null ? Icon(icon, size: 20, color: AppColors.textSecondary) : null,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF3F4F6),
    floatingLabelStyle: const TextStyle(color: AppColors.brandRed, fontWeight: FontWeight.w600),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(AppColors.brandRed),
    errorBorder: border(error),
    focusedErrorBorder: border(error),
  );
}

/// Full-width red pill button used as the main action on tool screens.
class ToolPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;

  const ToolPrimaryButton({super.key, required this.label, this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AppColors.brandRed,
      foregroundColor: Colors.white,
      disabledBackgroundColor: AppColors.brandRed.withValues(alpha: 0.35),
      disabledForegroundColor: Colors.white,
      shape: const StadiumBorder(),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: icon != null
          ? FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 20), label: Text(label))
          : FilledButton(onPressed: onPressed, style: style, child: Text(label)),
    );
  }
}

/// Sticky bottom area holding the primary action.
class ToolBottomBar extends StatelessWidget {
  final Widget child;

  const ToolBottomBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: child,
        ),
      ),
    );
  }
}

/// Centered "working on it" state shown while a tool processes.
class ToolProcessingView extends StatelessWidget {
  final String message;

  const ToolProcessingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.brandRed),
            ),
            const SizedBox(height: 22),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Everything stays on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selectable option card (e.g. compression level). Selected: red border
/// and a check; unselected: plain card.
class ToolOptionTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? tag;
  final VoidCallback onTap;

  const ToolOptionTile({
    super.key,
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.brandRed.withValues(alpha: 0.05) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: selected ? AppColors.brandRed : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      if (tag != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tag!,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? AppColors.brandRed : Colors.transparent,
                    border: Border.all(
                      color: selected ? AppColors.brandRed : const Color(0xFFCBD0D8),
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty "pick a file" state with the tool's document icon and a red CTA.
class ToolEmptyState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final String buttonLabel;
  final IconData buttonIcon;
  final VoidCallback onPressed;

  const ToolEmptyState({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DocumentIcon(icon: icon, color: color, size: 112),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 220,
                  child: ToolPrimaryButton(label: buttonLabel, icon: buttonIcon, onPressed: onPressed),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Red app bar with white title/icons used by the tool screens.
PreferredSizeWidget toolAppBar(BuildContext context, String title) {
  return AppBar(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    backgroundColor: AppColors.brandRed,
    foregroundColor: Colors.white,
    iconTheme: const IconThemeData(color: Colors.white),
    titleTextStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(color: Colors.white),
    elevation: 0,
  );
}

/// Bottom native ad shown under empty states.
class ToolEmptyWithAd extends StatelessWidget {
  final Widget empty;
  final Widget ad;

  const ToolEmptyWithAd({super.key, required this.empty, required this.ad});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: empty),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SafeArea(top: false, child: ad),
        ),
      ],
    );
  }
}

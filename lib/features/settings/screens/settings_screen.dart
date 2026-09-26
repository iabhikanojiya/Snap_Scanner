import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../core/services/app_prefs_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/blue_header.dart';
import '../../../core/widgets/glass_bottom_nav.dart';
import '../widgets/profile_card.dart';
import '../../../core/widgets/app_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> with RouteAware {
  String _userName = AppPrefsService.defaultUserName;
  int? _pdfCount;
  PageRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    refreshProfile();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => refreshProfile();

  Future<void> refreshProfile() async {
    try {
      final name = await AppPrefsService.getUserName();
      final count = await AppPrefsService.getPdfCount();
      if (!mounted) return;
      setState(() {
        _userName = name;
        _pdfCount = count;
      });
    } catch (e) {
      debugPrint('[Settings] profile load failed: $e');
    }
  }

  Future<void> _editName() async {
    final newName = await showAppDialog<String>(
      context: context,
      builder: (_) => _EditNameDialog(initialName: _userName),
    );
    if (newName == null) return;
    try {
      await AppPrefsService.setUserName(newName);
    } catch (e) {
      debugPrint('[Settings] save name failed: $e');
    }
    refreshProfile();
  }

  Future<void> _shareApp() async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text:
              'https://play.google.com/store/apps/details?id=com.antigravity.snapscanner.snap_scanner&hl',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open share sheet')),
        );
      }
    }
  }

  Future<void> _sendFeedback() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: 'fusionsix.tech@gmail.com',
      query: 'subject=Feedback for SnapScanner PDF Maker',
    );
    try {
      await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app')),
        );
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final Uri url = Uri.parse(
      'https://sites.google.com/view/snapscanner/home',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open browser')),
        );
      }
    }
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _group(List<Widget> tiles) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        children.add(const Divider(
            height: 1, thickness: 1, color: Color(0xFFF1F3F6), indent: 64, endIndent: 16));
      }
      children.add(tiles[i]);
    }
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          const BlueHeader(title: 'Settings'),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, GlassBottomNav.clearance(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProfileCard(
                    name: _userName,
                    pdfCount: _pdfCount,
                    onEditName: _editName,
                  ),
                  _sectionLabel('ABOUT & SUPPORT'),
                  _group([
                    _tile(
                      icon: Icons.share,
                      color: Colors.blueAccent,
                      title: 'Share App',
                      onTap: () => _shareApp(),
                    ),
                    _tile(
                      icon: Icons.feedback,
                      color: Colors.orange,
                      title: 'Feedback',
                      onTap: _sendFeedback,
                    ),
                    _tile(
                      icon: Icons.privacy_tip,
                      color: Colors.green,
                      title: 'Privacy Policy',
                      onTap: _openPrivacyPolicy,
                    ),
                  ]),
                  const SizedBox(height: 16),
                  const NativeAdWidget(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  final String initialName;

  const _EditNameDialog({required this.initialName});

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName == AppPrefsService.defaultUserName ? '' : widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.person_outline_rounded,
      title: 'Your name',
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 30,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
        decoration: AppDialog.inputDecoration(hintText: 'Enter your name'),
      ),
      primaryLabel: 'Save',
      onPrimary: _save,
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.pop(context),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snap_scanner/core/widgets/native_ad_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title:
            const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.share,
                          color: Colors.blueAccent),
                    ),
                    title: const Text('Share App',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () => _shareApp(),
                  ),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey.shade100,
                      indent: 20,
                      endIndent: 20),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:
                          const Icon(Icons.feedback, color: Colors.orange),
                    ),
                    title: const Text('Feedback',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: _sendFeedback,
                  ),
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: Colors.grey.shade100,
                      indent: 20,
                      endIndent: 20),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.privacy_tip,
                          color: Colors.green),
                    ),
                    title: const Text('Privacy Policy',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    trailing:
                        const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: _openPrivacyPolicy,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const NativeAdWidget(),
          ],
        ),
      ),
    );
  }
}

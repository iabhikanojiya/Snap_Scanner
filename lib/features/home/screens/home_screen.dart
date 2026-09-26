import 'package:flutter/material.dart';
import 'package:snap_scanner/features/settings/screens/settings_screen.dart';
import 'package:snap_scanner/services/app_update_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_bottom_nav.dart';
import '../../documents/screens/pdf_home_screen.dart';
// Upgrade UI temporarily hidden; restore this import with the tab below.
// import '../../upgrade/screens/upgrade_screen.dart';
import 'tools_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // Was 3 while the Upgrade tab was shown.
  static const int _settingsTab = 2;

  static const _navItems = [
    GlassNavItem(
      icon: Icons.picture_as_pdf_outlined,
      activeIcon: Icons.picture_as_pdf_rounded,
      label: 'PDF',
    ),
    GlassNavItem(
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      label: 'Tools',
    ),
    // Upgrade tab temporarily hidden.
    // GlassNavItem(
    //   icon: Icons.workspace_premium_outlined,
    //   activeIcon: Icons.workspace_premium_rounded,
    //   label: 'Upgrade',
    // ),
    GlassNavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: 'Settings',
    ),
  ];

  int _currentIndex = 0;

  // Tabs are built the first time they are opened and then kept alive, so
  // their ads/controllers are created once and never on every switch.
  final Set<int> _builtTabs = {0};

  final GlobalKey<SettingsScreenState> _settingsKey =
      GlobalKey<SettingsScreenState>();

  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _fadeController,
    curve: Curves.easeOut,
  ).drive(Tween(begin: 0.35, end: 1.0));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateService.instance.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppUpdateService.instance.onResume(context);
    }
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _builtTabs.add(index);
    });
    _fadeController.forward(from: 0);
    if (index == _settingsTab) {
      // PDFs may have been added/deleted from the PDF tab (cheap count query).
      _settingsKey.currentState?.refreshProfile();
    }
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return const PdfHomeScreen();
      case 1:
        return const ToolsScreen();
      // Upgrade tab temporarily hidden.
      // case 2:
      //   return const UpgradeScreen();
      default:
        return SettingsScreen(key: _settingsKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _fade,
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  for (var i = 0; i < _navItems.length; i++)
                    _builtTabs.contains(i)
                        ? TickerMode(
                            enabled: i == _currentIndex,
                            child: _buildTab(i),
                          )
                        : const SizedBox.shrink(),
                ],
              ),
            ),
          ),

          // Floating glass bottom navigation (hidden while typing so it
          // does not float above the keyboard over the content).
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            Positioned(
              left: 16,
              right: 16,
              bottom: GlassBottomNav.bottomOffset(context),
              child: GlassBottomNav(
                items: _navItems,
                currentIndex: _currentIndex,
                onTap: _onTabSelected,
              ),
            ),
        ],
      ),
    );
  }
}

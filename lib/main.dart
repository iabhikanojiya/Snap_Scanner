import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/theme/app_theme.dart';
import 'core/services/ad_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/app_prefs_service.dart';
import 'core/services/banner_ad_service.dart';
import 'core/navigation/app_navigator.dart';
import 'core/navigation/app_route_observer.dart';
import 'core/services/incoming_pdf_service.dart';
import 'features/home/screens/home_screen.dart';
import 'features/onboarding/screens/onboarding_screen.dart';
import 'providers/scan_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onboardingCompleted = AppPrefsService.isOnboardingCompleted();
  await Firebase.initializeApp();
  await Future.wait([
    AdService.instance.initialize(),
    BannerAdService.instance.initialize(),
  ]);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  AnalyticsService.instance.logAppOpen();
  final showOnboarding = !await onboardingCompleted;
  runApp(SnapScannerApp(showOnboarding: showOnboarding));
  // Handle PDFs opened with / shared to the app once the navigator exists.
  WidgetsBinding.instance.addPostFrameCallback((_) => IncomingPdfService.instance.start());
}

class SnapScannerApp extends StatelessWidget {
  final bool showOnboarding;

  const SnapScannerApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ScanProvider()),
      ],
      child: MaterialApp(
        title: 'SnapScanner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        navigatorKey: appNavigatorKey,
        navigatorObservers: [appRouteObserver],
        home: showOnboarding ? const OnboardingScreen() : const HomeScreen(),
      ),
    );
  }
}

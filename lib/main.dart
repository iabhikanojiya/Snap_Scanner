import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'core/theme/app_theme.dart';
import 'core/services/ad_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/banner_ad_service.dart';
import 'features/home/screens/home_screen.dart';
import 'providers/scan_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Future.wait([
    AdService.instance.initialize(),
    BannerAdService.instance.initialize(),
  ]);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  AnalyticsService.instance.logAppOpen();
  runApp(const SnapScannerApp());
}

class SnapScannerApp extends StatelessWidget {
  const SnapScannerApp({super.key});

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
        home: const HomeScreen(),
      ),
    );
  }
}

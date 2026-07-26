import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class BannerAdService {
  BannerAdService._();
  static final BannerAdService instance = BannerAdService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    log('initialize() called');
    await MobileAds.instance.initialize();
    log('MobileAds initialized');
    _initialized = true;
    log('initialize() completed');
  }

  Future<AdSize?> getAdaptiveAdSize(double screenWidth) async {
    log('getAdaptiveBannerSize() called | screenWidth=$screenWidth');
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        screenWidth.truncate(),
      );
      if (size != null) {
        log('Adaptive size = ${size.width} x ${size.height}');
      } else {
        log('Adaptive size is NULL');
      }
      return size;
    } catch (e) {
      log('getAdaptiveAdSize exception: $e');
      return null;
    }
  }

  static void log(String message) {
    assert(() {
      debugPrint('[BannerAd] $message');
      return true;
    }());
  }
}

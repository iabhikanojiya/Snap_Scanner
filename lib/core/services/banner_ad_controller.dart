import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'banner_ad_service.dart';

class BannerAdController extends ChangeNotifier {
  static const int _maxExponentialRetries = 5;
  static const int _minContinuousRetrySeconds = 30;
  static const int _maxContinuousRetrySeconds = 60;

  final String adUnitId;
  final BannerAdService _service = BannerAdService.instance;

  BannerAd? _bannerAd;
  AdSize? _adaptiveSize;
  double? _lastScreenWidth;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _visible = false;
  bool _disposed = false;
  int _exponentialRetryCount = 0;
  Timer? _retryTimer;

  BannerAdController({required this.adUnitId});

  bool get isLoaded => _isLoaded;
  bool get isVisible => _visible;
  double get targetHeight =>
      _adaptiveSize?.height.toDouble() ?? AdSize.banner.height.toDouble();

  AdSize get effectiveSize => _adaptiveSize ?? AdSize.banner;

  BannerAd? get bannerAd => _bannerAd;

  void show({required double screenWidth}) {
    if (_disposed || _visible) return;
    BannerAdService.log('Show requested');
    _visible = true;
    _loadAdaptiveAndAd(screenWidth);
  }

  void hide() {
    if (_disposed || !_visible) return;
    BannerAdService.log('Hide requested');
    _visible = false;
    _cancelRetry();
    _disposeAd();
    notifyListeners();
  }

  void updateScreenWidth(double screenWidth) {
    if (_disposed || !_visible) return;
    _loadAdaptiveSize(screenWidth).then((_) {
      if (_disposed || !_visible) return;
      if (!_isLoaded && !_isLoading) {
        _loadAd();
      }
    });
  }

  void pauseRetry() {
    _cancelRetry();
  }

  void resumeRetry() {
    if (_disposed || !_visible || _isLoaded) return;
    _scheduleRetry();
  }

  Future<void> _loadAdaptiveSize(double screenWidth) async {
    if (_lastScreenWidth == screenWidth && _adaptiveSize != null) return;
    _lastScreenWidth = screenWidth;
    final size = await _service.getAdaptiveAdSize(screenWidth);
    if (_disposed) return;
    if (size != null) {
      _adaptiveSize = size;
    }
  }

  Future<void> _loadAdaptiveAndAd(double screenWidth) async {
    await _loadAdaptiveSize(screenWidth);

    if (_disposed || !_visible) return;
    _loadAd();
  }

  void _loadAd() {
    if (_disposed || !_visible) return;
    if (_isLoading && !_isLoaded) return;
    if (_isLoaded && _bannerAd != null) return;

    _disposeAd();
    _isLoading = true;
    _isLoaded = false;
    _cancelRetry();
    notifyListeners();

    BannerAdService.log('Loading ad (size: ${effectiveSize.width}x${effectiveSize.height})');

    final size = effectiveSize;

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (_disposed) return;
          BannerAdService.log('Ad loaded successfully');
          _isLoaded = true;
          _isLoading = false;
          _exponentialRetryCount = 0;
          _cancelRetry();
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (_disposed) return;
          BannerAdService.log(
            'Ad failed: code=${error.code} message=${error.message} '
            'retryExponential=$_exponentialRetryCount',
          );
          _bannerAd = null;
          _isLoaded = false;
          _isLoading = false;
          notifyListeners();
          _scheduleRetry();
        },
        onAdImpression: (_) {
          BannerAdService.log('Impression recorded');
        },
        onAdClicked: (_) {
          BannerAdService.log('Ad clicked');
        },
      ),
    )..load();
  }

  void _scheduleRetry() {
    if (_disposed || !_visible) return;
    _cancelRetry();

    Duration delay;
    if (_exponentialRetryCount < _maxExponentialRetries) {
      _exponentialRetryCount++;
      delay = Duration(
        milliseconds: 1000 * (1 << (_exponentialRetryCount - 1)),
      );
    } else {
      final seconds = _minContinuousRetrySeconds +
          Random().nextInt(
            _maxContinuousRetrySeconds - _minContinuousRetrySeconds + 1,
          );
      delay = Duration(seconds: seconds);
    }

    BannerAdService.log('Retry scheduled in ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () {
      if (!_disposed && _visible) {
        _loadAd();
      }
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    _isLoading = false;
  }

  @override
  void dispose() {
    BannerAdService.log('Controller disposed');
    _disposed = true;
    _cancelRetry();
    _disposeAd();
    super.dispose();
  }
}
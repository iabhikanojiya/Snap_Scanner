import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'banner_ad_service.dart';

class BannerAdController extends ChangeNotifier {
  static const int _maxExponentialRetries = 5;
  static const int _minContinuousRetrySeconds = 30;
  static const int _maxContinuousRetrySeconds = 60;
  static const Duration _loadTimeout = Duration(seconds: 9);

  final String adUnitId;
  final BannerAdService _service = BannerAdService.instance;

  BannerAd? _bannerAd;
  AdSize? _adaptiveSize;
  double? _lastScreenWidth;
  bool _isLoaded = false;
  bool _isLoading = false;
  bool _visible = false;
  bool _disposed = false;
  bool _loadTimedOut = false;
  int _exponentialRetryCount = 0;
  int _requestId = 0;
  int _requestGeneration = 0;
  Timer? _retryTimer;
  Timer? _loadTimeoutTimer;
  DateTime? _requestStartTime;

  BannerAdController({required this.adUnitId});

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  bool get isVisible => _visible;
  bool get isLoadTimedOut => _loadTimedOut;
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
    _cancelLoadTimeout();
    _disposeAd();
    notifyListeners();
  }

  void updateScreenWidth(double screenWidth) {
    if (_disposed || !_visible) return;
    BannerAdService.log('updateScreenWidth | width=$screenWidth');
    _loadAdaptiveSize(screenWidth).then((_) {
      if (_disposed || !_visible) return;
      if (!_isLoaded && !_isLoading) {
        _loadAd();
      }
    });
  }

  void pauseRetry() {
    BannerAdService.log('Retry paused');
    _cancelRetry();
  }

  void resumeRetry() {
    if (_disposed || !_visible || _isLoaded) return;
    BannerAdService.log('Retry resumed');
    _scheduleRetry();
  }

  Future<void> _loadAdaptiveSize(double screenWidth) async {
    if (_lastScreenWidth == screenWidth && _adaptiveSize != null) return;
    _lastScreenWidth = screenWidth;
    final size = await _service.getAdaptiveAdSize(screenWidth);
    if (_disposed) return;
    if (size != null) {
      _adaptiveSize = size;
      BannerAdService.log('Adaptive size set: ${size.width}x${size.height}');
    }
  }

  Future<void> _loadAdaptiveAndAd(double screenWidth) async {
    await _loadAdaptiveSize(screenWidth);

    if (_disposed || !_visible) return;
    _loadAd();
  }

  void _loadAd() {
    if (_disposed || !_visible) return;
    // Exactly ONE active request per controller.
    if (_isLoading && !_isLoaded) return;
    if (_isLoaded && _bannerAd != null) return;

    final id = ++_requestId;
    final gen = ++_requestGeneration;

    _disposeAd();
    _isLoading = true;
    _isLoaded = false;
    _loadTimedOut = false;
    _cancelRetry();
    _cancelLoadTimeout();
    _requestStartTime = DateTime.now();
    notifyListeners();

    BannerAdService.log('[REQUEST-$id] START');
    BannerAdService.log(
        '[REQUEST-$id] ADAPTIVE SIZE ${effectiveSize.width}x${effectiveSize.height}');

    _loadTimeoutTimer = Timer(_loadTimeout, () {
      _loadTimeoutTimer = null;
      if (_disposed || !_visible) return;
      if (gen != _requestGeneration) return;
      if (_isLoaded && _bannerAd != null) return;
      BannerAdService.log(
          '[REQUEST-$id] TIMEOUT after ${_loadTimeout.inSeconds}s | hiding placeholder, scheduling background retry');
      _loadTimedOut = true;
      _isLoading = false;
      notifyListeners();
      _scheduleRetry();
    });

    final size = effectiveSize;

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (_disposed) return;
          if (gen != _requestGeneration || !identical(_bannerAd, ad)) {
            BannerAdService.log(
                '[REQUEST_$id] STALE LOADED ignored (gen mismatch or old ad)');
            return;
          }
          _cancelLoadTimeout();
          final elapsed = DateTime.now()
              .difference(_requestStartTime ?? DateTime.now())
              .inMilliseconds;
          BannerAdService.log('[REQUEST_$id] LOADED after ${elapsed}ms');
          _loadTimedOut = false;
          _isLoaded = true;
          _isLoading = false;
          _exponentialRetryCount = 0;
          _cancelRetry();
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          if (_disposed) return;
          if (gen != _requestGeneration || !identical(_bannerAd, ad)) {
            BannerAdService.log(
                '[REQUEST_$id] STALE FAILED ignored (gen mismatch or old ad)');
            return;
          }
          ad.dispose();
          _cancelLoadTimeout();
          final elapsed = DateTime.now()
              .difference(_requestStartTime ?? DateTime.now())
              .inMilliseconds;
          BannerAdService.log(
            '[REQUEST_$id] FAILED after ${elapsed}ms '
            '(code=${error.code} domain=${error.domain} message=${error.message})',
          );
          _loadTimedOut = false;
          _bannerAd = null;
          _isLoaded = false;
          _isLoading = false;
          notifyListeners();
          _scheduleRetry();
        },
        onAdImpression: (_) {
          BannerAdService.log('[REQUEST_$id] Impression recorded');
        },
        onAdClicked: (_) {
          BannerAdService.log('[REQUEST_$id] Ad clicked');
        },
        onAdClosed: (_) {
          BannerAdService.log('[REQUEST_$id] Ad closed');
        },
      ),
    )..load();
    BannerAdService.log('[REQUEST_$id] BannerAd CREATED + load() CALLED');
  }

  void _scheduleRetry() {
    if (_disposed || !_visible || _isLoaded) return;
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

    BannerAdService.log(
        'Retry attempt $_exponentialRetryCount scheduled in ${delay.inSeconds}s');
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (!_disposed && _visible) {
        _loadAd();
      }
    });
  }

  void _cancelRetry() {
    if (_retryTimer != null) {
      BannerAdService.log('Retry timer cancelled');
    }
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _cancelLoadTimeout() {
    if (_loadTimeoutTimer != null) {
      BannerAdService.log('Load timeout timer cancelled');
    }
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
  }

  void _disposeAd() {
    if (_bannerAd != null) {
      BannerAdService.log('[REQUEST_$_requestId] DISPOSED');
    }
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
    _cancelLoadTimeout();
    _disposeAd();
    super.dispose();
  }
}
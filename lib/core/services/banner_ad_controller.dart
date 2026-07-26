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
    if (_disposed || _visible) {
      BannerAdService.log('show() skipped | disposed=$_disposed visible=$_visible');
      return;
    }
    BannerAdService.log('show() called | screenWidth=$screenWidth');
    _visible = true;
    _loadAdaptiveAndAd(screenWidth);
  }

  void hide() {
    if (_disposed || !_visible) {
      BannerAdService.log('hide() skipped | disposed=$_disposed visible=$_visible');
      return;
    }
    BannerAdService.log('hide() called');
    _visible = false;
    _cancelRetry();
    _disposeAd();
    BannerAdService.log('notifyListeners()');
    notifyListeners();
  }

  void updateScreenWidth(double screenWidth) {
    if (_disposed || !_visible) {
      BannerAdService.log('updateScreenWidth() skipped | disposed=$_disposed visible=$_visible');
      return;
    }
    BannerAdService.log('updateScreenWidth() | screenWidth=$screenWidth');
    _loadAdaptiveSize(screenWidth).then((_) {
      if (_disposed || !_visible) return;
      if (!_isLoaded && !_isLoading) {
        BannerAdService.log('updateScreenWidth() triggering _loadAd');
        _loadAd();
      }
    });
  }

  void pauseRetry() {
    BannerAdService.log('pauseRetry() called');
    _cancelRetry();
  }

  void resumeRetry() {
    if (_disposed || !_visible || _isLoaded) {
      BannerAdService.log('resumeRetry() skipped | disposed=$_disposed visible=$_visible isLoaded=$_isLoaded');
      return;
    }
    BannerAdService.log('resumeRetry() called');
    _scheduleRetry();
  }

  Future<void> _loadAdaptiveSize(double screenWidth) async {
    if (_lastScreenWidth == screenWidth && _adaptiveSize != null) {
      BannerAdService.log('_loadAdaptiveSize() skipped | cached width=$screenWidth');
      return;
    }
    BannerAdService.log('_loadAdaptiveSize() | screenWidth=$screenWidth');
    _lastScreenWidth = screenWidth;
    final size = await _service.getAdaptiveAdSize(screenWidth);
    if (_disposed) return;
    if (size != null) {
      _adaptiveSize = size;
      BannerAdService.log('Adaptive size changed | width=${size.width} height=${size.height}');
    } else {
      BannerAdService.log('Adaptive size unchanged | using fallback');
    }
  }

  Future<void> _loadAdaptiveAndAd(double screenWidth) async {
    BannerAdService.log('_loadAdaptiveAndAd() | screenWidth=$screenWidth');

    await _loadAdaptiveSize(screenWidth);

    if (_disposed || !_visible) {
      BannerAdService.log('_loadAdaptiveAndAd() aborted | disposed=$_disposed visible=$_visible');
      return;
    }
    _loadAd();
  }

  void _loadAd() {
    BannerAdService.log('_loadAd() entered | isLoading=$_isLoading isLoaded=$_isLoaded disposed=$_disposed hasBanner=${_bannerAd != null} retryCount=$_exponentialRetryCount');

    if (_disposed || !_visible) {
      BannerAdService.log('_loadAd() skipped | disposed=$_disposed visible=$_visible');
      return;
    }
    if (_isLoading && !_isLoaded) {
      BannerAdService.log('_loadAd() skipped | already loading');
      return;
    }
    if (_isLoaded && _bannerAd != null) {
      BannerAdService.log('_loadAd() skipped | already loaded');
      return;
    }

    _disposeAd();
    _isLoading = true;
    BannerAdService.log('_isLoading = true');
    _isLoaded = false;
    BannerAdService.log('_isLoaded = false');
    _cancelRetry();
    BannerAdService.log('notifyListeners()');
    notifyListeners();

    BannerAdService.log('Loading ad (size: ${effectiveSize.width}x${effectiveSize.height})');

    final size = effectiveSize;

    BannerAdService.log('Creating BannerAd | adUnitId=$adUnitId width=${size.width} height=${size.height}');

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (_disposed) return;
          BannerAdService.log('onAdLoaded() | width=${_bannerAd?.size.width} height=${_bannerAd?.size.height} adUnitId=$adUnitId');
          _isLoaded = true;
          BannerAdService.log('_isLoaded = true');
          _isLoading = false;
          BannerAdService.log('_isLoading = false');
          _exponentialRetryCount = 0;
          _cancelRetry();
          BannerAdService.log('notifyListeners()');
          notifyListeners();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (_disposed) return;
          BannerAdService.log('onAdFailedToLoad() | code=${error.code} message=${error.message} retryExponential=$_exponentialRetryCount');
          _bannerAd = null;
          BannerAdService.log('_bannerAd = null');
          _isLoaded = false;
          BannerAdService.log('_isLoaded = false');
          _isLoading = false;
          BannerAdService.log('_isLoading = false');
          BannerAdService.log('notifyListeners()');
          notifyListeners();
          _scheduleRetry();
        },
        onAdImpression: (_) {
          if (_disposed) return;
          BannerAdService.log('onAdImpression()');
        },
        onAdClicked: (_) {
          if (_disposed) return;
          BannerAdService.log('onAdClicked()');
        },
        onAdOpened: (_) {
          if (_disposed) return;
          BannerAdService.log('onAdOpened()');
        },
        onAdClosed: (_) {
          if (_disposed) return;
          BannerAdService.log('onAdClosed()');
        },
      ),
    );
    BannerAdService.log('_bannerAd assigned | id=${_bannerAd?.adUnitId}');
    BannerAdService.log('Calling banner.load()');
    _bannerAd!.load();
    BannerAdService.log('banner.load() completed');
  }

  void _scheduleRetry() {
    if (_disposed || !_visible) {
      BannerAdService.log('_scheduleRetry() skipped | disposed=$_disposed visible=$_visible');
      return;
    }
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

    BannerAdService.log('Retry scheduled | delay=${delay.inSeconds}s');
    _retryTimer = Timer(delay, () {
      BannerAdService.log('Retry started');
      if (!_disposed && _visible) {
        _loadAd();
      }
      BannerAdService.log('Retry completed');
    });
  }

  void _cancelRetry() {
    if (_retryTimer != null) {
      BannerAdService.log('Retry cancelled');
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  void _disposeAd() {
    if (_bannerAd != null) {
      BannerAdService.log('Disposing banner');
      _bannerAd!.dispose();
      BannerAdService.log('Banner disposed');
      _bannerAd = null;
      BannerAdService.log('_bannerAd = null');
    }
    _isLoaded = false;
    _isLoading = false;
  }

  @override
  void dispose() {
    BannerAdService.log('Controller dispose() called');
    _disposed = true;
    BannerAdService.log('_disposed = true');
    _cancelRetry();
    _disposeAd();
    super.dispose();
    BannerAdService.log('Controller disposed');
  }
}

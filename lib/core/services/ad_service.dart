import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_config.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  int _successfulOperationCount = 0;
  InterstitialAd? _interstitialAd;
  bool _initialized = false;
  int _retryAttempt = 0;
  static const int _maxRetryAttempts = 5;

  Future<void> initialize() async {
    if (_initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    _loadInterstitialAd();
  }

  void _loadInterstitialAd() {
    _interstitialAd?.dispose();
    _interstitialAd = null;

    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _retryAttempt = 0;
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) => _loadInterstitialAd(),
            onAdFailedToShowFullScreenContent: (ad, error) =>
                _loadInterstitialAd(),
            onAdImpression: (_) {},
          );
        },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          if (_retryAttempt < _maxRetryAttempts) {
            _retryAttempt++;
            final delay = Duration(
              milliseconds: (1000 * (1 << (_retryAttempt - 1))).round(),
            );
            Future.delayed(delay, _loadInterstitialAd);
          }
        },
      ),
    );
  }

  void onSuccessfulOperation() {
    _successfulOperationCount++;
    if (_successfulOperationCount >= 2) {
      _successfulOperationCount = 0;
      final ad = _interstitialAd;
      _interstitialAd = null;
      if (ad != null) {
        ad.show();
      }
    }
    if (_interstitialAd == null) {
      _loadInterstitialAd();
    }
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}

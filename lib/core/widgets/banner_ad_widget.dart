import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_config.dart';

class BannerAdWidget extends StatefulWidget {
  final bool visible;

  const BannerAdWidget({super.key, this.visible = true});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _hasError = false;
  int _retryAttempt = 0;
  static const int _maxRetryAttempts = 5;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _loadBannerAd();
  }

  @override
  void didUpdateWidget(BannerAdWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _loadBannerAd();
    } else if (!widget.visible && oldWidget.visible) {
      _disposeAd();
    }
  }

  void _loadBannerAd() {
    if (_bannerAd != null) return;
    _bannerAd = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() {
              _isLoaded = true;
              _hasError = false;
              _retryAttempt = 0;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          if (mounted) {
            setState(() => _hasError = true);
          }
          if (_retryAttempt < _maxRetryAttempts) {
            _retryAttempt++;
            final delay = Duration(
              milliseconds: (1000 * (1 << (_retryAttempt - 1))).round(),
            );
            Future.delayed(delay, () {
              if (mounted && widget.visible) _loadBannerAd();
            });
          }
        },
      ),
    )..load();
  }

  void _disposeAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
    _hasError = false;
    _retryAttempt = 0;
  }

  @override
  void dispose() {
    _disposeAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    if (_hasError) return const SizedBox.shrink();
    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Container(
      color: Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}

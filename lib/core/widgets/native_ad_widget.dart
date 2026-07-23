import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_config.dart';

class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _hasError = false;
  int _retryAttempt = 0;
  static const int _maxRetryAttempts = 3;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    _nativeAd?.dispose();
    _nativeAd = NativeAd(
      adUnitId: AdConfig.nativeAdUnitId,
      listener: NativeAdListener(
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
          debugPrint('NativeAd failed to load: $error');
          ad.dispose();
          _nativeAd = null;
          if (mounted) setState(() => _hasError = true);
          if (_retryAttempt < _maxRetryAttempts) {
            _retryAttempt++;
            final delay = Duration(
              milliseconds: (2000 * (1 << (_retryAttempt - 1))).round(),
            );
            Future.delayed(delay, () {
              if (mounted) _loadNativeAd();
            });
          }
        },
      ),
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        cornerRadius: 12.0,
        mainBackgroundColor: Colors.white,
        primaryTextStyle: NativeTemplateTextStyle(
          style: NativeTemplateFontStyle.bold,
          size: 16.0,
          textColor: Colors.black87,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey.shade600,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey.shade400,
        ),
        callToActionTextStyle: NativeTemplateTextStyle(
          style: NativeTemplateFontStyle.bold,
          size: 16.0,
          backgroundColor: Colors.blueAccent,
          textColor: Colors.white,
        ),
      ),
    )..load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return const SizedBox.shrink();
    if (!_isLoaded || _nativeAd == null) {
      return const SizedBox(height: 120);
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 320,
        child: AdWidget(ad: _nativeAd!),
      ),
      );
  }
}

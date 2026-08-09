import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../services/ad_config.dart';
import '../services/banner_ad_controller.dart';
import '../services/banner_ad_service.dart';

class BannerAdWidget extends StatefulWidget {
  final bool visible;

  const BannerAdWidget({super.key, this.visible = true});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget>
    with WidgetsBindingObserver {
  BannerAdController? _controller;
  double _screenWidth = 0;

  @override
  void initState() {
    super.initState();
    BannerAdService.log('Widget initState()');
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.of(context).size.width;
    final widthChanged = width != _screenWidth;
    BannerAdService.log('didChangeDependencies() | width=$width widthChanged=$widthChanged visible=${widget.visible} hasController=${_controller != null}');
    if (widthChanged) {
      _screenWidth = width;
      BannerAdService.log('screenWidth = $width');
    }
    if (_controller == null && widget.visible && _screenWidth > 0) {
      _createController();
    } else if (widthChanged && _controller != null) {
      BannerAdService.log('didChangeDependencies() triggering updateScreenWidth');
      _controller!.updateScreenWidth(width);
    }
  }

  @override
  void didUpdateWidget(BannerAdWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    BannerAdService.log('didUpdateWidget() | visible=${widget.visible} wasVisible=${oldWidget.visible}');
    if (widget.visible && !oldWidget.visible) {
      _createController();
    } else if (!widget.visible && oldWidget.visible) {
      _destroyController();
    }
  }

  @override
  void dispose() {
    BannerAdService.log('Widget dispose()');
    WidgetsBinding.instance.removeObserver(this);
    _destroyController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    BannerAdService.log('didChangeAppLifecycleState | state=$state');
    switch (state) {
      case AppLifecycleState.resumed:
        if (widget.visible) {
          _screenWidth = MediaQuery.of(context).size.width;
          BannerAdService.log('App resumed | screenWidth=$_screenWidth');
          if (_controller != null) {
            _controller!.updateScreenWidth(_screenWidth);
            _controller!.resumeRetry();
          } else {
            _createController();
          }
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        BannerAdService.log('App lifecycle pause | pausing retry');
        _controller?.pauseRetry();
    }
  }

  void _createController() {
    if (_controller != null) {
      BannerAdService.log('_createController() skipped | already exists');
      return;
    }
    BannerAdService.log('_createController() | screenWidth=$_screenWidth');
    _controller = BannerAdController(adUnitId: AdConfig.bannerAdUnitId);
    BannerAdService.log('Listener attached');
    _controller!.addListener(_onControllerChanged);
    _controller!.show(screenWidth: _screenWidth);
  }

  void _destroyController() {
    if (_controller != null) {
      BannerAdService.log('_destroyController() called');
      BannerAdService.log('Listener removed');
      _controller!.removeListener(_onControllerChanged);
      _controller!.dispose();
      _controller = null;
      BannerAdService.log('Controller reference set to null');
    } else {
      BannerAdService.log('_destroyController() skipped | no controller');
    }
  }

  void _onControllerChanged() {
    BannerAdService.log('Controller listener triggered');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    BannerAdService.log('Widget build | visible=${widget.visible} loading=${c?.isLoading ?? false} loaded=${c?.isLoaded ?? false} timedOut=${c?.isLoadTimedOut ?? false} hasBanner=${c?.bannerAd != null} bannerHeight=${c?.targetHeight ?? 0}');

    if (!widget.visible) return const SizedBox.shrink();

    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    final height = controller.targetHeight;
    final isLoaded = controller.isLoaded;
    final hasAd = controller.bannerAd != null;

    if (isLoaded && hasAd) {
      return Container(
        color: Colors.transparent,
        child: SafeArea(
          top: false,
          child: SizedBox(
            width: controller.effectiveSize.width.toDouble(),
            height: height,
            child: AdWidget(ad: controller.bannerAd!),
          ),
        ),
      );
    }

    // Only show the loading spinner while a request is actually in flight.
    // After a failure or timeout (during backoff) there is no active request,
    // so collapse the placeholder and keep the surrounding UI usable.
    if (controller.isLoading && !controller.isLoadTimedOut) {
      return SizedBox(
        height: height,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

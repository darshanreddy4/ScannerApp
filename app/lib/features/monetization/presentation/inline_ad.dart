import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../core/theme/app_colors.dart';
import '../data/admob_service.dart';
import '../domain/ad_pass.dart';
import 'plan_cubit.dart';

/// Space kept above and below the banner, so a tap meant for a document cannot land on it.
const double adGap = 16;

/// One ad that sits inside a scrolling list, never next to navigation or buttons: a native ad, or an adaptive banner when no
/// native ad is available. It takes no room, and loads nothing, for Premium users, during a pass, or until the person's ad
/// consent is known.
class InlineAd extends StatelessWidget {
  const InlineAd({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([AdMobService.adsReady, AdPass.until]),
    builder: (context, _) {
      if (!AdMobService.adsReady.value || AdPass.active) return const SizedBox.shrink();
      if (!context.watch<PlanCubit>().state.showsAds) return const SizedBox.shrink();
      return const _NativeOrBanner();
    },
  );
}

class _NativeOrBanner extends StatefulWidget {
  const _NativeOrBanner();

  @override
  State<_NativeOrBanner> createState() => _NativeOrBannerState();
}

class _NativeOrBannerState extends State<_NativeOrBanner> with AutomaticKeepAliveClientMixin {
  var _nativeFailed = false;

  // A lazy list drops items that scroll away; keeping this one stops the ad being requested again each time it scrolls back.
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _nativeFailed ? const _BannerAdView() : _NativeAdView(onFailed: () => setState(() => _nativeFailed = true));
  }
}

/// A native ad in Google's small template, on a bordered card with its own "Ad" label so it cannot be taken for a document.
class _NativeAdView extends StatefulWidget {
  const _NativeAdView({required this.onFailed});
  final VoidCallback onFailed;

  @override
  State<_NativeAdView> createState() => _NativeAdViewState();
}

class _NativeAdViewState extends State<_NativeAdView> {
  NativeAd? _ad;
  bool _loaded = false;

  static const _height = 120.0;

  @override
  void initState() {
    super.initState();
    final ad = NativeAd(
      adUnitId: AdUnitIds.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) widget.onFailed();
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: AppColors.surface,
        callToActionTextStyle: NativeTemplateTextStyle(textColor: Colors.white, backgroundColor: AppColors.primary, style: NativeTemplateFontStyle.bold),
        primaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.ink, style: NativeTemplateFontStyle.bold),
        secondaryTextStyle: NativeTemplateTextStyle(textColor: AppColors.inkMuted),
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    // The space is held while the ad loads so the list below does not jump when it appears.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: adGap),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.inkMuted.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: _loaded && ad != null ? AdWidget(ad: ad) : null,
      ),
    );
  }
}

class _BannerAdView extends StatefulWidget {
  const _BannerAdView();

  @override
  State<_BannerAdView> createState() => _BannerAdViewState();
}

class _BannerAdViewState extends State<_BannerAdView> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _failed = false;
  double? _height;
  int? _loadedWidth;

  Future<void> _load(int width) async {
    _loadedWidth = width;
    _loaded = false;
    _failed = false;
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    // The space is held while the ad loads so the list below does not jump when it appears.
    setState(() => _height = size.height.toDouble());
    final ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => mounted ? setState(() => _loaded = true) : null,
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    );
    _ad?.dispose();
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 32).truncate();
    if (_loadedWidth != width) _load(width);

    final ad = _ad, height = _height;
    if (_failed || height == null) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: adGap),
      alignment: Alignment.center,
      width: double.infinity,
      height: height + adGap * 2,
      child: _loaded && ad != null ? AdWidget(ad: ad) : null,
    );
  }
}

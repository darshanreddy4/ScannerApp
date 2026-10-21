import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../domain/entities/plan_status.dart';
import '../domain/repositories/monetization_contracts.dart';

/// Ad unit IDs. The values below are Google's public test IDs.
/// Replace them (and the app IDs in AndroidManifest.xml / Info.plist) before release.
abstract final class AdUnitIds {
  static String get banner => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';

  static String get interstitial => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';
}

class AdMobService implements AdService {
  AdMobService({AdPolicy policy = const AdPolicy()}) : _policy = policy;

  final AdPolicy _policy;
  InterstitialAd? _interstitial;
  DateTime? _lastShownAt;
  bool _initialized = false;
  bool _loading = false;

  @override
  Future<void> initialize() async {
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      _loadInterstitial();
    } catch (e) {
      debugPrint('Ads unavailable: $e');
    }
  }

  void _loadInterstitial() {
    if (!_initialized || _loading || _interstitial != null) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
          debugPrint('Interstitial failed to load: ${error.message}');
        },
      ),
    );
  }

  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {
    final ad = _interstitial;
    final eligible = _policy.shouldShowInterstitial(plan: plan, lastShownAt: _lastShownAt, now: DateTime.now());
    if (!eligible || ad == null) {
      _loadInterstitial();
      return;
    }

    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!done.isCompleted) done.complete();
      },
    );
    _interstitial = null;
    _lastShownAt = DateTime.now();
    await ad.show();
    await done.future.timeout(const Duration(minutes: 1), onTimeout: () {});
    _loadInterstitial();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../app/app_config.dart';
import '../domain/ad_pass.dart';
import '../domain/entities/plan_status.dart';
import '../domain/repositories/monetization_contracts.dart';

/// Ad unit IDs come from [AppConfig]; the defaults are Google's public test IDs.
abstract final class AdUnitIds {
  static String get banner => Platform.isAndroid ? AppConfig.bannerAndroid : AppConfig.bannerIos;
  static String get native => Platform.isAndroid ? AppConfig.nativeAndroid : AppConfig.nativeIos;
  static String get rewarded => Platform.isAndroid ? AppConfig.rewardedAndroid : AppConfig.rewardedIos;
  static String get interstitial => Platform.isAndroid ? AppConfig.interstitialAndroid : AppConfig.interstitialIos;
}

/// True while a text field has focus or the on-screen keyboard is showing.
bool isTyping() {
  final focus = FocusManager.instance.primaryFocus?.context;
  if (focus != null && (focus.widget is EditableText || focus.findAncestorWidgetOfExactType<EditableText>() != null)) return true;
  return WidgetsBinding.instance.platformDispatcher.views.any((v) => v.viewInsets.bottom > 0);
}

/// True while the app is on screen; null means the first frame has not been drawn yet.
bool isForeground() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == null || state == AppLifecycleState.resumed;
}

/// A full-screen ad waits this long after the task ends, so the result is on screen before the ad covers it.
const interstitialSettle = Duration(milliseconds: 700);

class AdMobService implements AdService {
  AdMobService({AdPolicy policy = const AdPolicy()}) : _policy = policy;

  final AdPolicy _policy;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  bool _rewardedLoading = false;
  DateTime? _lastShownAt;
  int _actionsSinceAd = 0;
  bool _initialized = false;
  bool _loading = false;

  /// True once the user's consent choice is known and ads may be requested. Banners wait for it.
  static final ValueNotifier<bool> adsReady = ValueNotifier(false);

  @override
  Future<void> initialize() async {
    try {
      await _gatherConsent();
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      _initialized = true;
      adsReady.value = true;
      _loadInterstitial();
      unawaited(_loadRewarded());
    } catch (e) {
      debugPrint('Ads unavailable: $e');
    }
  }

  /// Google's User Messaging Platform: shows the consent form where the law requires one (EEA, UK, ...).
  Future<void> _gatherConsent() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!done.isCompleted) done.complete();
        });
      },
      (_) {
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future.timeout(const Duration(seconds: 30), onTimeout: () {});
  }

  @override
  Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    // A form that is still due is shown first; the options form is for a choice that was already made.
    if (!await ConsentInformation.instance.canRequestAds()) await _gatherConsent();
    if (await privacyOptionsRequired()) {
      final done = Completer<void>();
      await ConsentForm.showPrivacyOptionsForm((_) {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
    }
    if (!_initialized && await ConsentInformation.instance.canRequestAds()) await initialize();
  }

  /// Loads a rewarded video ahead of time so it can start the moment it is asked for.
  Future<RewardedAd?> _loadRewarded() async {
    if (!_initialized) return null;
    if (_rewarded != null) return _rewarded;
    if (_rewardedLoading) {
      // Another load is running; wait briefly for it.
      for (var i = 0; i < 40 && _rewardedLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return _rewarded;
    }
    _rewardedLoading = true;
    final done = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => done.complete(ad),
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded failed to load: ${error.message}');
          done.complete(null);
        },
      ),
    );
    final ad = await done.future.timeout(const Duration(seconds: 12), onTimeout: () => null);
    _rewardedLoading = false;
    _rewarded = ad;
    return ad;
  }

  @override
  Future<RewardResult> showRewarded() async {
    if (!_initialized) {
      final info = ConsentInformation.instance;
      if (await info.canRequestAds()) {
        await initialize();
      } else if (await info.getConsentStatus() != ConsentStatus.unknown) {
        return RewardResult.consentNeeded;
      }
    }
    final ad = await _loadRewarded();
    if (ad == null) return RewardResult.unavailable;
    _rewarded = null;

    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!closed.isCompleted) closed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future.timeout(const Duration(minutes: 5), onTimeout: () {});
    unawaited(_loadRewarded());
    return earned ? RewardResult.earned : RewardResult.dismissed;
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
    if (plan.showsAds) _actionsSinceAd++;
    final eligible = _policy.shouldShowInterstitial(
      plan: plan,
      lastShownAt: _lastShownAt,
      now: DateTime.now(),
      typing: isTyping(),
      actionsSinceLastAd: _actionsSinceAd,
      foreground: isForeground(),
      adFree: AdPass.active,
    );
    if (!eligible || ad == null) {
      _loadInterstitial();
      return;
    }

    await Future<void>.delayed(interstitialSettle);
    // The person may have started typing, left the app or started a pass while the result appeared.
    if (isTyping() || !isForeground() || AdPass.active) return;

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
    _actionsSinceAd = 0;
    await ad.show();
    await done.future.timeout(const Duration(minutes: 1), onTimeout: () {});
    _loadInterstitial();
  }
}

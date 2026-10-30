import '../entities/plan_status.dart';

abstract interface class PlanRepository {
  Future<PlanStatus> current();
  Future<void> setPlan(PlanStatus plan);
}

/// Decides when ads may be shown. Premium users never see ads.
class AdPolicy {
  const AdPolicy({this.interstitialCooldown = const Duration(minutes: 2), this.everyNthAction = 2});

  final Duration interstitialCooldown;

  /// An ad is offered after every Nth finished action, not after each one.
  final int everyNthAction;

  /// [typing] is true while a text field has focus or the keyboard is up; a full-screen ad must never cut that off.
  bool shouldShowInterstitial({
    required PlanStatus plan,
    required DateTime? lastShownAt,
    required DateTime now,
    bool typing = false,
    int? actionsSinceLastAd,
    bool foreground = true,
    bool adFree = false,
  }) {
    // Never when the app is not on screen, and never during a pass.
    if (!plan.showsAds || typing || !foreground || adFree) return false;
    if (actionsSinceLastAd != null && actionsSinceLastAd < everyNthAction) return false;
    if (lastShownAt == null) return true;
    return now.difference(lastShownAt) >= interstitialCooldown;
  }

  bool shouldShowBanner(PlanStatus plan) => plan.showsAds;
}

/// Outcome of offering a rewarded video.
enum RewardResult {
  /// Watched to the end: the reward is due.
  earned,

  /// Closed early, so no reward.
  dismissed,

  /// No video could be loaded (offline, no fill).
  unavailable,

  /// Ads are off because the person's privacy choice does not allow them. Going online will not help; changing the choice will.
  consentNeeded,

  /// Today's limit of rewarded videos is used up.
  limitReached,
}

abstract interface class AdService {
  Future<void> initialize();

  /// Plays a rewarded video the person chose to watch.
  Future<RewardResult> showRewarded();

  /// Whether the law requires an entry point where users can change their ad consent.
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();

  /// Shows an interstitial if [plan] and the frequency cap allow it. Completes when dismissed or skipped.
  Future<void> showInterstitialIfEligible(PlanStatus plan);
}

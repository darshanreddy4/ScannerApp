import '../entities/plan_status.dart';

abstract interface class PlanRepository {
  Future<PlanStatus> current();
  Future<void> setPlan(PlanStatus plan);
}

/// Decides when ads may be shown. Premium users never see ads.
class AdPolicy {
  const AdPolicy({this.interstitialCooldown = const Duration(minutes: 2)});

  final Duration interstitialCooldown;

  bool shouldShowInterstitial({required PlanStatus plan, required DateTime? lastShownAt, required DateTime now}) {
    if (!plan.showsAds) return false;
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

  /// No video could be loaded (offline, consent not given, no fill).
  unavailable,

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

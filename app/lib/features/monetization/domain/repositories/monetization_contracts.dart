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

abstract interface class AdService {
  Future<void> initialize();

  /// Shows an interstitial if [plan] and the frequency cap allow it. Completes when dismissed or skipped.
  Future<void> showInterstitialIfEligible(PlanStatus plan);
}

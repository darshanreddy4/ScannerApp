import '../../monetization/domain/entities/plan_status.dart';

enum FeatureState {
  /// Switched off by the owner: not shown to anyone.
  hidden,

  /// Switched on but the user's plan does not include it.
  locked,
  available,
}

/// Single place that decides who gets which feature. Swap the inputs for remote config later.
abstract final class FeatureAccess {
  /// Editing saved documents is a Premium feature that the owner can switch on or off.
  ///
  /// While purchases are not available ([billingEnabled] false) nothing is locked, because a feature
  /// the user cannot buy must not be offered as locked.
  /// Choosing how long a QR share stays available is Premium; Free users get it by paying coins for the share.
  ///
  /// [coinsEnabled]: Free users can pay with coins earned from rewarded videos, so the feature
  /// counts as locked (priced) even without purchases.
  static FeatureState customShareDuration({required PlanStatus plan, bool billingEnabled = true, bool coinsEnabled = false}) {
    if (!billingEnabled && !coinsEnabled) return FeatureState.available;
    return plan == PlanStatus.premium ? FeatureState.available : FeatureState.locked;
  }

  static FeatureState editSavedDocuments({required PlanStatus plan, required bool enabled, bool billingEnabled = true, bool coinsEnabled = false}) {
    if (!enabled) return FeatureState.hidden;
    if (!billingEnabled && !coinsEnabled) return FeatureState.available;
    return plan == PlanStatus.premium ? FeatureState.available : FeatureState.locked;
  }
}

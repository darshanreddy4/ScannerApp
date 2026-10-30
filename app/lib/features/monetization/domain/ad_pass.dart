import 'package:flutter/foundation.dart';

/// While a pass runs, the person sees no interstitial or banner ads. The coin screen sets [until]; the ad code only reads it.
abstract final class AdPass {
  static final ValueNotifier<DateTime?> until = ValueNotifier(null);

  /// The clock; tests replace it.
  static DateTime Function() now = DateTime.now;

  static bool get active {
    final end = until.value;
    return end != null && end.isAfter(now());
  }
}

import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full-screen ad may come every 90 seconds, after every second finished action', () {
    const policy = AdPolicy();
    expect((policy.interstitialCooldown, policy.everyNthAction), (const Duration(seconds: 90), 2));
  });

  group('an ad is requested only when the next finished action could show it', () {
    const policy = AdPolicy();
    final now = DateTime(2026, 11, 24, 12);

    bool preload({PlanStatus plan = PlanStatus.free, DateTime? last, int actions = 0, bool adFree = false}) =>
        policy.shouldPreloadInterstitial(plan: plan, lastShownAt: last, now: now, actionsSinceLastAd: actions, adFree: adFree);

    test('not at the start, before any action was finished', () => expect(preload(actions: 0), isFalse));
    test('once the next action would be the second', () => expect(preload(actions: 1), isTrue));
    test('not for Premium or during a pass', () {
      expect(preload(plan: PlanStatus.premium, actions: 3), isFalse);
      expect(preload(actions: 3, adFree: true), isFalse);
    });
    test('not while the pause after the last ad is far from over, but shortly before it ends', () {
      expect(preload(actions: 3, last: now.subtract(const Duration(seconds: 20))), isFalse);
      expect(preload(actions: 3, last: now.subtract(const Duration(seconds: 70))), isTrue);
    });
  });
}

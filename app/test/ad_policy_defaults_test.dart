import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a full-screen ad may come every 90 seconds, after every second finished action', () {
    const policy = AdPolicy();
    expect((policy.interstitialCooldown, policy.everyNthAction), (const Duration(seconds: 90), 2));
  });
}

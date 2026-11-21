import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/rewards/presentation/earn_coins_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/coins_fakes.dart';

class _Plans implements PlanRepository {
  _Plans(this.plan);
  final PlanStatus plan;
  @override
  Future<PlanStatus> current() async => plan;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

Future<void> _pump(WidgetTester tester, {required MemoryWallet wallet, ScriptedAds? ads, PlanStatus plan = PlanStatus.free, int? cap}) async {
  final coins = coinsCubit(wallet: wallet, ads: ads ?? ScriptedAds([RewardResult.earned]), dailyAdCap: cap);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans(plan))..load()),
          BlocProvider.value(value: coins),
        ],
        child: const Scaffold(body: EarnCoinsBar()),
      ),
    ),
  );
  await coins.load();
  await tester.pumpAndSettle();
}

void main() {
  test('a full-screen ad may come every 90 seconds, after every second finished action', () {
    const policy = AdPolicy();
    expect((policy.interstitialCooldown, policy.everyNthAction), (const Duration(seconds: 90), 2));
  });

  group('the earn coins strip on the Tools screen', () {
    testWidgets('shows the balance and a video button, and a watched video adds the coins', (tester) async {
      final wallet = MemoryWallet(balance: 3);
      await _pump(tester, wallet: wallet);
      expect(find.text('3 coins'), findsOneWidget);
      expect(find.text('Watch video (+10)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('earn-coins-watch')));
      await tester.pumpAndSettle();
      expect(wallet.balance, 13);
      expect(find.text('13 coins'), findsOneWidget);
    });

    testWidgets('is hidden for Premium, during a pass and when today\'s videos are used up', (tester) async {
      await _pump(tester, wallet: MemoryWallet(balance: 3), plan: PlanStatus.premium);
      expect(find.byKey(const ValueKey('earn-coins-bar')), findsNothing);

      await _pump(tester, wallet: MemoryWallet(balance: 3, passUntil: DateTime.now().add(const Duration(hours: 1)), passMinutes: 30));
      expect(find.byKey(const ValueKey('earn-coins-bar')), findsNothing);

      await _pump(tester, wallet: MemoryWallet(balance: 3, adsToday: 18), cap: 18);
      expect(find.byKey(const ValueKey('earn-coins-bar')), findsNothing);
    });

    testWidgets('is simply absent where there are no coins to show', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: EarnCoinsBar())));
      expect(find.byKey(const ValueKey('earn-coins-bar')), findsNothing);
    });
  });
}

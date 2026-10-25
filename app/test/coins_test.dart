import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/rewards/data/coin_wallet_impl.dart';
import 'package:scanvault/features/rewards/domain/coin_rules.dart';
import 'package:scanvault/features/rewards/presentation/coins_card.dart';
import 'package:scanvault/features/settings/domain/feature_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/coins_fakes.dart';

void main() {
  group('CoinWalletImpl', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('earning adds coins and counts the video; spending needs enough coins', () async {
      final wallet = CoinWalletImpl();
      expect((await wallet.read()).balance, 0);

      final after = await wallet.earnFromAd(10);
      expect((after.balance, after.adsToday), (10, 1));

      expect(await wallet.spend(4), isTrue);
      expect((await wallet.read()).balance, 6);
      expect(await wallet.spend(7), isFalse);
      expect((await wallet.read()).balance, 6, reason: 'a refused spend changes nothing');
      expect(await wallet.spend(0), isFalse);
    });

    test('the daily video count starts again the next day but the coins stay', () async {
      var now = DateTime(2026, 10, 23, 23, 50);
      final wallet = CoinWalletImpl(clock: () => now);
      await wallet.earnFromAd(10);
      await wallet.earnFromAd(10);
      expect((await wallet.read()).adsToday, 2);

      now = DateTime(2026, 10, 24, 0, 5);
      final next = await wallet.read();
      expect(next.adsToday, 0);
      expect(next.balance, 20);
      expect((await wallet.earnFromAd(10)).adsToday, 1);
    });

    test('the balance survives a restart', () async {
      await CoinWalletImpl().earnFromAd(10);
      expect((await CoinWalletImpl().read()).balance, 10);
    });
  });

  group('CoinsCubit', () {
    test('pays only for a video watched to the end', () async {
      final ads = ScriptedAds([RewardResult.dismissed, RewardResult.unavailable, RewardResult.earned]);
      final cubit = coinsCubit(ads: ads);

      expect(await cubit.watchAd(), RewardResult.dismissed);
      expect(await cubit.watchAd(), RewardResult.unavailable);
      expect(cubit.state.balance, 0);
      expect(await cubit.watchAd(), RewardResult.earned);
      expect(cubit.state.balance, CoinRules.rewardPerAd);
      expect(cubit.state.adsToday, 1);
      expect(cubit.state.watching, isFalse);
    });

    test('there is no daily limit unless one is set', () async {
      expect(CoinRules.dailyAdCap, isNull);
      final ads = ScriptedAds([for (var i = 0; i < 25; i++) RewardResult.earned]);
      final cubit = coinsCubit(ads: ads);
      for (var i = 0; i < 25; i++) {
        expect(await cubit.watchAd(), RewardResult.earned, reason: 'video ${i + 1}');
      }
      expect(cubit.state.balance, 25 * CoinRules.rewardPerAd);
      expect(cubit.state.adsToday, 25);
      expect(cubit.state.adsLeft, isNull);
      expect(cubit.state.canWatch, isTrue);
    });

    test('a limit set later stops offering videos once it is used', () async {
      final ads = ScriptedAds([RewardResult.earned]);
      final cubit = coinsCubit(wallet: MemoryWallet(adsToday: 50), ads: ads, dailyAdCap: 50);

      expect(await cubit.watchAd(), RewardResult.limitReached);
      expect(ads.shown, 0, reason: 'no video is even requested');
      expect(cubit.state.adsLeft, 0);
      expect(cubit.state.canWatch, isFalse);
    });

    test('with a limit, the videos left are counted down', () async {
      final cubit = coinsCubit(ads: ScriptedAds([RewardResult.earned, RewardResult.earned]), dailyAdCap: 3);
      await cubit.load();
      expect(cubit.state.adsLeft, 3);
      await cubit.watchAd();
      await cubit.watchAd();
      expect(cubit.state.adsLeft, 1);
    });

    test('spending takes coins and reports a shortfall', () async {
      final cubit = coinsCubit(wallet: MemoryWallet(balance: 6));
      await cubit.load();
      expect(await cubit.spend(5), isTrue);
      expect(cubit.state.balance, 1);
      expect(await cubit.spend(5), isFalse);
      expect(cubit.state.balance, 1);
    });

    test('a second request while a video is playing is ignored', () async {
      final cubit = coinsCubit(ads: ScriptedAds([RewardResult.earned, RewardResult.earned]));
      final first = cubit.watchAd();
      expect(await cubit.watchAd(), RewardResult.unavailable);
      expect(await first, RewardResult.earned);
      expect(cubit.state.balance, 10);
    });
  });

  group('feature access with coins', () {
    test('Free users are priced when coins exist even without purchases', () {
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: true, billingEnabled: false, coinsEnabled: true), FeatureState.locked);
      expect(FeatureAccess.customShareDuration(plan: PlanStatus.free, billingEnabled: false, coinsEnabled: true), FeatureState.locked);
    });

    test('Premium never pays, and with neither coins nor purchases nothing is locked', () {
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.premium, enabled: true, billingEnabled: false, coinsEnabled: true), FeatureState.available);
      expect(FeatureAccess.customShareDuration(plan: PlanStatus.free, billingEnabled: false, coinsEnabled: false), FeatureState.available);
      expect(FeatureAccess.editSavedDocuments(plan: PlanStatus.free, enabled: false, billingEnabled: false, coinsEnabled: true), FeatureState.hidden);
    });
  });

  group('CoinsCard', () {
    Future<CoinsCardHarness> show(WidgetTester tester, {MemoryWallet? wallet, ScriptedAds? ads, int? dailyAdCap}) async {
      final w = wallet ?? MemoryWallet(balance: 12);
      final cubit = coinsCubit(wallet: w, ads: ads, dailyAdCap: dailyAdCap);
      await tester.runAsync(cubit.load);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider.value(value: cubit, child: const CoinsCard()),
          ),
        ),
      );
      await tester.pump();
      return CoinsCardHarness(w);
    }

    testWidgets('shows the balance, the earn button and what coins buy', (tester) async {
      await show(tester);
      expect(find.text('12 coins'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.textContaining('left today'), findsNothing, reason: 'no limit, so no counter');
      for (final f in CoinFeature.values) {
        expect(find.textContaining('${f.label}: ${f.cost} coins'), findsOneWidget);
      }
    });

    testWidgets('watching a video adds coins and says so', (tester) async {
      final h = await show(tester, ads: ScriptedAds([RewardResult.earned]));
      await tester.tap(find.text('+10'));
      await tester.pumpAndSettle();
      expect(h.wallet.balance, 22);
      expect(find.text('22 coins'), findsOneWidget);
      expect(find.text('Coins added'), findsNothing, reason: 'the animation has finished and removed itself');
    });

    testWidgets('earning coins plays a coin animation that counts the balance up and then goes away', (tester) async {
      await show(tester, ads: ScriptedAds([RewardResult.earned]));
      await tester.tap(find.text('+10'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('coin-burst')), findsOneWidget);
      expect(find.text('+10'), findsWidgets);
      expect(find.text('Coins added'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
      final mid = RegExp(r'(\d+) coins').firstMatch(tester.widget<Text>(find.textContaining(RegExp(r'^\d+ coins$'))).data!)!.group(1)!;
      expect(int.parse(mid), inInclusiveRange(12, 22));

      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('coin-burst')), findsNothing);
      expect(find.text('22 coins'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with animations turned off the coins are announced with a message instead', (tester) async {
      final w = MemoryWallet(balance: 12);
      final cubit = coinsCubit(wallet: w, ads: ScriptedAds([RewardResult.earned]));
      await tester.runAsync(cubit.load);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: BlocProvider.value(value: cubit, child: const CoinsCard()),
            ),
          ),
        ),
      );
      await tester.tap(find.text('+10'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coin-burst')), findsNothing);
      expect(find.text('You earned 10 coins'), findsOneWidget);
    });

    testWidgets('a limit set later shows how many videos are left', (tester) async {
      await show(tester, wallet: MemoryWallet(balance: 3, adsToday: 4), dailyAdCap: 10);
      expect(find.textContaining('6 left today'), findsOneWidget);
    });

    testWidgets('the button stays on however many videos were watched', (tester) async {
      await show(tester, wallet: MemoryWallet(balance: 3, adsToday: 200));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('the button is off for the rest of the day after a set limit', (tester) async {
      await show(tester, wallet: MemoryWallet(balance: 3, adsToday: 10), dailyAdCap: 10);
      expect(find.textContaining('all of today'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}

class CoinsCardHarness {
  CoinsCardHarness(this.wallet);
  final MemoryWallet wallet;
}

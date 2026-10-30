import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/widgets/feedback.dart';
import '../../monetization/domain/entities/plan_status.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../../monetization/presentation/plan_cubit.dart';
import '../domain/coin_rules.dart';
import 'coin_burst.dart';
import 'coins_cubit.dart';
import 'consent_needed.dart';
import 'passes_sheet.dart';
import '../../../core/widgets/text.dart';

enum _Choice { watch, upgrade, passes }

String _coins(int n) => n == 1 ? tr('1 coin') : trf('{n} coins', {'n': n});

/// For the places that open a tool: Premium, builds without coins, and screens with no coin counter skip the question.
Future<bool> requestToolAccess(BuildContext context, CoinFeature feature) async {
  if (!AppConfig.rewardsEnabled || feature.tier == CoinTier.free) return true;
  try {
    if (context.read<PlanCubit>().state == PlanStatus.premium) return true;
    context.read<CoinsCubit>();
  } on Object {
    return true;
  }
  return requestUnlock(context, feature);
}

/// Asks a Free user to pay [feature]'s cost in coins, offering a rewarded video or a pass when the balance is short.
/// A pass, the same tool opened a moment ago, or a light tool's free use of the day, all open it
/// without coins. Returns true when the tool may be used.
Future<bool> requestUnlock(BuildContext context, CoinFeature feature) async {
  final coins = context.read<CoinsCubit>();
  await coins.claimDaily();
  if (!context.mounted) return false;
  if (feature.tier == CoinTier.free) return true;
  final cover = await coins.coverWithoutCoins(feature);
  if (cover == UnlockCover.freeDaily && context.mounted) showMessage(context, 'This is your free use of it for today');
  if (cover != UnlockCover.none) return true;

  while (true) {
    await coins.load();
    if (!context.mounted) return false;

    if (coins.state.balance >= feature.cost) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(trf('Use {cost}?', {'cost': _coins(feature.cost)})),
          content: Text(
            trf('{feature} costs {cost}. You have {balance}.', {'feature': tr(feature.label), 'cost': _coins(feature.cost), 'balance': coins.state.balance}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(trf('Use {cost}', {'cost': _coins(feature.cost)}))),
          ],
        ),
      );
      if (ok != true) return false;
      final paid = await coins.spend(feature.cost);
      if (paid) coins.markPaid(feature);
      if (!paid && context.mounted) showMessage(context, 'Not enough coins.');
      return paid;
    }

    final choice = await showDialog<_Choice>(
      context: context,
      builder: (ctx) => _NotEnough(feature: feature, balance: coins.state.balance, canWatch: coins.state.canWatch),
    );
    if (choice == _Choice.upgrade && context.mounted) {
      context.push('/paywall');
      return false;
    }
    if (choice == _Choice.passes) {
      if (!context.mounted) return false;
      await showPassesSheet(context);
      if (!context.mounted) return false;
      if (await coins.coverWithoutCoins(feature) != UnlockCover.none) return true;
      continue;
    }
    if (choice != _Choice.watch || !context.mounted) return false;

    final result = await runBusy(context, 'Loading video', coins.watchAd);
    if (!context.mounted) return false;
    switch (result) {
      case RewardResult.earned:
        showCoinsEarned(context, CoinRules.rewardPerAd);
      case RewardResult.dismissed:
        showMessage(context, 'Watch the video to the end to earn coins');
        return false;
      case RewardResult.unavailable:
        if (context.mounted) showMessage(context, 'No video could load. Turn on mobile data or Wi-Fi and try again. Coins you earn can be used offline.');
        return false;
      case RewardResult.consentNeeded:
        if (await showConsentNeeded(context)) continue;
        return false;
      case RewardResult.limitReached:
        showMessage(context, 'You have used today\'s videos. Come back tomorrow.');
        return false;
    }
  }
}

class _NotEnough extends StatelessWidget {
  const _NotEnough({required this.feature, required this.balance, required this.canWatch});
  final CoinFeature feature;
  final int balance;
  final bool canWatch;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Not enough coins'),
    content: Text(
      trf('{feature} costs {cost} and you have {balance}.', {'feature': tr(feature.label), 'cost': _coins(feature.cost), 'balance': balance}) +
          ' ' +
          (canWatch
              ? trf('Watch a short video to earn {n} coins, or watch several videos for a pass that opens every tool.', {'n': CoinRules.rewardPerAd})
              : tr('You have used today\'s videos; more are available tomorrow.')),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      if (AppConfig.billingEnabled) TextButton(onPressed: () => Navigator.pop(context, _Choice.upgrade), child: const Text('Go Premium')),
      if (canWatch) TextButton(key: const ValueKey('unlock-passes'), onPressed: () => Navigator.pop(context, _Choice.passes), child: const Text('Passes')),
      if (canWatch) FilledButton(onPressed: () => Navigator.pop(context, _Choice.watch), child: Text(trf('Watch video (+{n})', {'n': CoinRules.rewardPerAd}))),
    ],
  );
}

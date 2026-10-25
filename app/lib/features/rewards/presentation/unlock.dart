import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_config.dart';
import '../../../core/widgets/feedback.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import 'coin_burst.dart';
import 'coins_cubit.dart';

enum _Choice { watch, upgrade }

/// Asks a Free user to pay [feature]'s cost in coins, offering a rewarded video when the balance is short.
/// Returns true when the coins were taken and the feature may be used.
Future<bool> requestUnlock(BuildContext context, CoinFeature feature) async {
  final coins = context.read<CoinsCubit>();
  while (true) {
    await coins.load();
    if (!context.mounted) return false;

    if (coins.state.balance >= feature.cost) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Use ${feature.cost} coins?'),
          content: Text('${feature.label} costs ${feature.cost} coins. You have ${coins.state.balance}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Use ${feature.cost} coins')),
          ],
        ),
      );
      if (ok != true) return false;
      final paid = await coins.spend(feature.cost);
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
        showMessage(context, 'No video is available right now. Check your connection and try again.');
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
      '${feature.label} costs ${feature.cost} coins and you have $balance. '
      '${canWatch ? 'Watch a short video to earn ${CoinRules.rewardPerAd} coins.' : 'You have used today\'s videos; more are available tomorrow.'}',
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      if (AppConfig.billingEnabled) TextButton(onPressed: () => Navigator.pop(context, _Choice.upgrade), child: const Text('Go Premium')),
      if (canWatch) FilledButton(onPressed: () => Navigator.pop(context, _Choice.watch), child: Text('Watch video (+${CoinRules.rewardPerAd})')),
    ],
  );
}

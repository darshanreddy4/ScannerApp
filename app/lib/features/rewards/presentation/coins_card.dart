import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import 'coin_burst.dart';
import 'coins_cubit.dart';

/// Balance, a way to earn more, and what coins can buy.
class CoinsCard extends StatelessWidget {
  const CoinsCard({super.key});

  Future<void> _watch(BuildContext context) async {
    final coins = context.read<CoinsCubit>();
    final result = await runBusy(context, 'Loading video', coins.watchAd);
    if (!context.mounted) return;
    if (result == RewardResult.earned) {
      showCoinsEarned(context, CoinRules.rewardPerAd);
      return;
    }
    showMessage(context, switch (result) {
      RewardResult.earned => '',
      RewardResult.dismissed => 'Watch the video to the end to earn coins',
      RewardResult.unavailable => 'No video is available right now. Check your connection and try again.',
      RewardResult.limitReached => 'You have used today\'s videos. Come back tomorrow.',
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CoinsCubit>().state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(AppIcons.coins, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                // Counts up to the new balance when coins are added.
                TweenAnimationBuilder<double>(
                  tween: Tween(end: state.balance.toDouble()),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => Text('${v.round()} coins', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: !state.canWatch || state.watching ? null : () => _watch(context),
                  // The theme's buttons are full width; inside a Row they need a finite minimum.
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  icon: const Icon(AppIcons.video, size: 18),
                  label: Text('+${CoinRules.rewardPerAd}'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              !state.canWatch
                  ? 'You have watched all of today\'s videos. More tomorrow.'
                  : 'Watch a short video to earn ${CoinRules.rewardPerAd} coins${state.adsLeft == null ? '' : ' (${state.adsLeft} left today)'}. Coins pay for Premium features:',
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 4),
            for (final f in CoinFeature.values) Text('•  ${f.label}: ${f.cost} coins', style: const TextStyle(color: AppColors.inkMuted, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import 'coin_burst.dart';
import 'coins_cubit.dart';
import 'consent_needed.dart';
import 'passes_sheet.dart';
import '../../../core/widgets/text.dart';

/// Balance, a way to earn more, the passes, and what costs what.
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
    if (result == RewardResult.consentNeeded) {
      await showConsentNeeded(context);
      return;
    }
    showMessage(context, switch (result) {
      RewardResult.earned || RewardResult.consentNeeded => '',
      RewardResult.dismissed => 'Watch the video to the end to earn coins',
      RewardResult.unavailable => 'No video could load. Turn on mobile data or Wi-Fi and try again. Coins you earn can be used offline.',
      RewardResult.limitReached => 'You have used today\'s videos. Come back tomorrow.',
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CoinsCubit>().state;
    final until = state.passUntil;
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
                  builder: (_, v, _) => Text(trf('{n} coins', {'n': v.round()}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                  : trf(
                      state.adsLeft == null
                          ? 'Watch a short video to earn {n} coins. You also get {daily} free coins each day.'
                          : 'Watch a short video to earn {n} coins ({left} left today). You also get {daily} free coins each day.',
                      {'n': CoinRules.rewardPerAd, 'left': state.adsLeft ?? 0, 'daily': CoinRules.dailyCoins},
                    ),
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (until != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  trf('Your pass runs until {time}.', {'time': formatDateTime(until)}),
                  key: const ValueKey('coins-pass'),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            const Text(
              'Scanning, saving, viewing, searching and sharing a PDF are always free.',
              style: TextStyle(color: AppColors.inkMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 4),
            const Text('•  Light tools: 1 coin, and the first use of each is free every day', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
            const Text('•  All other tools: 5 coins each use', style: TextStyle(color: AppColors.inkMuted, fontSize: 13)),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('coins-passes'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => showPassesSheet(context),
              icon: const Icon(AppIcons.timer, size: 18),
              label: const Text('Passes: open every tool, no ads'),
            ),
          ],
        ),
      ),
    );
  }
}

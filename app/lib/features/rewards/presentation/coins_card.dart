import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/style_kit.dart';
import '../domain/coin_rules.dart';
import 'coin_burst.dart';
import 'coins_cubit.dart';
import 'passes_sheet.dart';
import 'watch_for_coins.dart';
import '../../../core/widgets/text.dart';

/// Balance, a way to earn more, the passes, and what costs what.
class CoinsCard extends StatelessWidget {
  const CoinsCard({super.key});

  Future<void> _watch(BuildContext context) => watchForCoins(context);

  Future<void> _claim(BuildContext context) async {
    final added = await context.read<CoinsCubit>().claimDaily();
    if (added > 0 && context.mounted) showCoinsEarned(context, added);
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
              key: const ValueKey('coins-daily'),
              children: [
                const GradientIconTile(icon: AppIcons.catGift, color: Color(0xFFDB2777), size: 38),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Daily bonus', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(trf('+{n} coins, once a day', {'n': CoinRules.dailyCoins}), style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  key: const ValueKey('coins-claim'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: state.dailyClaimed ? null : () => _claim(context),
                  child: Text(state.dailyClaimed ? 'Claimed' : 'Claim'),
                ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                const GradientIconTile(icon: AppIcons.coins, color: Color(0xFFF59E0B), size: 38),
                const SizedBox(width: AppSpacing.sm),
                // Counts up to the new balance when coins are added.
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: state.balance.toDouble()),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOut,
                    builder: (_, v, _) => Text(
                      trf('{n} coins', {'n': v.round()}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
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

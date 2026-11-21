import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/style_kit.dart';
import '../../../core/widgets/text.dart';
import '../../monetization/domain/entities/plan_status.dart';
import '../../monetization/presentation/plan_cubit.dart';
import '../domain/coin_rules.dart';
import 'coins_cubit.dart';
import 'watch_for_coins.dart';

/// A short strip on the Tools screen: the coin balance and a one-tap video for more.
/// Hidden for Premium, during a pass, when today's videos are used up, and where coins are off.
class EarnCoinsBar extends StatelessWidget {
  const EarnCoinsBar({super.key});

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.rewardsEnabled) return const SizedBox.shrink();
    final CoinsState state;
    try {
      if (context.watch<PlanCubit>().state == PlanStatus.premium) return const SizedBox.shrink();
      state = context.watch<CoinsCubit>().state;
    } on Object {
      return const SizedBox.shrink();
    }
    final until = state.passUntil;
    if (!state.canWatch || (until != null && until.isAfter(DateTime.now()))) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        key: const ValueKey('earn-coins-bar'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const GradientIconTile(icon: AppIcons.coins, color: Color(0xFFF59E0B), size: 34),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      trf('{n} coins', {'n': state.balance}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('earn-coins-watch'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: state.watching ? null : () => watchForCoins(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(AppIcons.video, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: Text(trf('Watch video (+{n})', {'n': CoinRules.rewardPerAd}), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

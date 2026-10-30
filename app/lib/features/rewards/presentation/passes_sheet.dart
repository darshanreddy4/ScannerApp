import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import 'coins_cubit.dart';
import 'consent_needed.dart';
import '../../../core/widgets/text.dart';

Future<void> showPassesSheet(BuildContext context) {
  final coins = context.read<CoinsCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(value: coins, child: const PassesSheet()),
  );
}

/// The passes on offer: how many videos each needs and what it opens, shown before any video is played.
class PassesSheet extends StatelessWidget {
  const PassesSheet({super.key});

  Future<void> _watch(BuildContext context, PassTier pass) async {
    final coins = context.read<CoinsCubit>();
    final before = coins.state.passUntil;
    final result = await runBusy(context, 'Loading video', () => coins.watchForPass(pass));
    if (!context.mounted) return;
    switch (result) {
      case RewardResult.earned:
        final until = coins.state.passUntil;
        if (until != null && until != before) {
          showMessage(context, trf('Pass started. Every tool is open and ads are off until {time}.', {'time': formatDateTime(until)}));
        } else {
          showMessage(context, trf('{done} of {needed} videos watched', {'done': coins.state.progressFor(pass), 'needed': pass.videos}));
        }
      case RewardResult.dismissed:
        showMessage(context, 'Watch the video to the end for it to count');
      case RewardResult.unavailable:
        showMessage(context, 'No video could load. Turn on mobile data or Wi-Fi and try again. Coins you earn can be used offline.');
      case RewardResult.consentNeeded:
        await showConsentNeeded(context);
      case RewardResult.limitReached:
        showMessage(context, 'You have used today\'s videos. Come back tomorrow.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CoinsCubit>().state;
    final until = state.passUntil;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Passes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Watch videos to open every tool and hide ads for a while. Nothing is charged.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
            if (until != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                trf('Your pass runs until {time}.', {'time': formatDateTime(until)}),
                key: const ValueKey('pass-running'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            for (final pass in passTiers)
              Card(
                key: ValueKey('pass-${pass.minutes}'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trf('{time} pass', {'time': tr(pass.label)}), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        trf('Watch {n} videos to unlock all tools and remove ads for {time}.', {'n': pass.videos, 'time': tr(pass.label)}),
                        style: const TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              trf('{done} of {needed} watched today', {'done': state.progressFor(pass), 'needed': pass.videos}),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                          FilledButton.icon(
                            key: ValueKey('pass-watch-${pass.minutes}'),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            onPressed: state.watching || !state.canWatch ? null : () => _watch(context, pass),
                            icon: const Icon(AppIcons.video, size: 18),
                            label: const Text('Watch'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

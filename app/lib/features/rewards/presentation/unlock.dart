import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_config.dart';
import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gold_coin.dart';
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
  if (feature.tier == CoinTier.free) return true;
  final cover = await coins.coverWithoutCoins(feature);
  if (cover == UnlockCover.freeDaily && context.mounted) showMessage(context, 'Free today');
  if (cover != UnlockCover.none) return true;

  while (true) {
    await coins.load();
    if (!context.mounted) return false;

    if (coins.state.balance >= feature.cost) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => _SpendDialog(feature: feature, balance: coins.state.balance),
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

/// The frame of both coin dialogs: a gold coin that pops in with a glint, a title, then the content.
class _CoinDialog extends StatelessWidget {
  const _CoinDialog({required this.title, required this.children, this.dim = false, this.titleKey});
  final String title;
  final Key? titleKey;
  final List<Widget> children;
  final bool dim;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 84,
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF1C2), Color(0xFFFFFBEB)]),
            ),
            alignment: Alignment.center,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 1000),
              builder: (_, t, _) => Transform.scale(
                scale: 0.55 + 0.45 * Curves.elasticOut.transform(t.clamp(0.0, 1.0)),
                child: GoldCoin(size: 62, dim: dim, glint: t),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  key: titleKey,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Shown when the balance covers the cost: the tool opens with a few of the person's coins, with no sums on screen.
class _SpendDialog extends StatelessWidget {
  const _SpendDialog({required this.feature, required this.balance});
  final CoinFeature feature;
  final int balance;

  @override
  Widget build(BuildContext context) => _CoinDialog(
    title: tr(feature.label),
    children: [
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFFFFF4D1), borderRadius: BorderRadius.circular(20)),
          child: Text(
            trf('Opens with {cost}', {'cost': _coins(feature.cost)}),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00)),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('You have', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          const SizedBox(width: 4),
          const GoldCoin(size: 14),
          const SizedBox(width: 2),
          Text(
            '$balance',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('unlock-use'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Open'),
      ),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
    ],
  );
}

class _NotEnough extends StatelessWidget {
  const _NotEnough({required this.feature, required this.balance, required this.canWatch});
  final CoinFeature feature;
  final int balance;
  final bool canWatch;

  @override
  Widget build(BuildContext context) => _CoinDialog(
    title: trf('Get free coins to open {feature}', {'feature': tr(feature.label)}),
    titleKey: const ValueKey('unlock-not-enough'),
    dim: true,
    children: [
      Text(
        canWatch
            ? trf('Watch a short video to get {n} free coins, or watch several videos for a pass that opens every tool.', {'n': CoinRules.rewardPerAd})
            : tr('You have used today\'s videos; more are available tomorrow.'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: (balance / feature.cost).clamp(0.0, 1.0),
          minHeight: 8,
          backgroundColor: const Color(0xFFE8ECF4),
          valueColor: const AlwaysStoppedAnimation(Color(0xFFF5B301)),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '$balance / ${feature.cost}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
      ),
      const SizedBox(height: 12),
      if (canWatch) ...[
        FilledButton(
          key: const ValueKey('unlock-watch'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: () => Navigator.pop(context, _Choice.watch),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(AppIcons.video, size: 20),
              const SizedBox(width: 8),
              Flexible(child: Text(trf('Watch video (+{n})', {'n': CoinRules.rewardPerAd}), textAlign: TextAlign.center)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const ValueKey('unlock-passes'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => Navigator.pop(context, _Choice.passes),
          child: const Text('Passes'),
        ),
      ],
      if (AppConfig.billingEnabled) TextButton(onPressed: () => Navigator.pop(context, _Choice.upgrade), child: const Text('Go Premium')),
      TextButton(
        style: TextButton.styleFrom(minimumSize: const Size(0, 36)),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}

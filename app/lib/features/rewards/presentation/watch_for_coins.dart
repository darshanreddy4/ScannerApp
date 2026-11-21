import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/widgets/feedback.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import 'coin_burst.dart';
import 'coins_cubit.dart';
import 'consent_needed.dart';

/// Plays a rewarded video for coins and tells the person what happened.
Future<void> watchForCoins(BuildContext context) async {
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

import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/rewards/domain/coin_wallet.dart';
import 'package:scanvault/features/rewards/presentation/coins_cubit.dart';

class MemoryWallet implements CoinWallet {
  MemoryWallet({this.balance = 0, this.adsToday = 0});
  int balance;
  int adsToday;

  @override
  Future<CoinSnapshot> read() async => CoinSnapshot(balance: balance, adsToday: adsToday);

  @override
  Future<CoinSnapshot> earnFromAd(int coins) async {
    balance += coins;
    adsToday++;
    return read();
  }

  @override
  Future<bool> spend(int coins) async {
    if (coins <= 0 || balance < coins) return false;
    balance -= coins;
    return true;
  }

  @override
  Future<void> refund(int coins) async => balance += coins;
}

/// Rewarded videos answer from a script; everything else does nothing.
class ScriptedAds implements AdService {
  ScriptedAds([List<RewardResult> script = const []]) : _script = [...script];
  final List<RewardResult> _script;
  int shown = 0;

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {}
  @override
  Future<RewardResult> showRewarded() async {
    shown++;
    return _script.isEmpty ? RewardResult.unavailable : _script.removeAt(0);
  }
}

CoinsCubit coinsCubit({MemoryWallet? wallet, ScriptedAds? ads, int? dailyAdCap}) =>
    CoinsCubit(wallet: wallet ?? MemoryWallet(), ads: ads ?? ScriptedAds(), dailyAdCap: dailyAdCap);

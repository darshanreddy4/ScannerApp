import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/rewards/domain/coin_wallet.dart';
import 'package:doculoom/features/rewards/presentation/coins_cubit.dart';

class MemoryWallet implements CoinWallet {
  MemoryWallet({this.balance = 0, this.adsToday = 0, this.dailyClaim = 0, this.passUntil, this.passMinutes, this.passProgress = 0});
  int balance;
  int adsToday;

  /// What the first claim of the day adds; 0 keeps older tests unchanged.
  int dailyClaim;
  bool claimed = false;
  DateTime? passUntil;
  int? passMinutes;
  int passProgress;
  final freeUsed = <String>{};
  DateTime Function() now = DateTime.now;

  CoinSnapshot get _s => CoinSnapshot(
    balance: balance,
    adsToday: adsToday,
    passUntil: passUntil != null && passUntil!.isAfter(now()) ? passUntil : null,
    passMinutes: passMinutes,
    passProgress: passProgress,
  );

  @override
  Future<CoinSnapshot> read() async => _s;

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

  @override
  Future<int> claimDaily(int coins) async {
    if (claimed || dailyClaim == 0) return 0;
    claimed = true;
    balance += dailyClaim;
    return dailyClaim;
  }

  @override
  Future<CoinSnapshot> countPassVideo({required int minutes, required int needed, required Duration length}) async {
    final count = (passMinutes == minutes ? passProgress : 0) + 1;
    passMinutes = minutes;
    if (count >= needed) {
      final running = passUntil != null && passUntil!.isAfter(now()) ? passUntil! : now();
      passUntil = running.add(length);
      passProgress = 0;
    } else {
      passProgress = count;
    }
    return read();
  }

  @override
  Future<bool> useFreeDaily(String id) async => freeUsed.add(id);
}

/// Rewarded videos answer from a script; everything else does nothing.
class ScriptedAds implements AdService {
  ScriptedAds([List<RewardResult> script = const []]) : _script = [...script];
  final List<RewardResult> _script;
  int shown = 0;
  int privacyOpened = 0;

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async => privacyOpened++;
  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {}
  @override
  Future<RewardResult> showRewarded() async {
    shown++;
    return _script.isEmpty ? RewardResult.unavailable : _script.removeAt(0);
  }
}

CoinsCubit coinsCubit({MemoryWallet? wallet, ScriptedAds? ads, int? dailyAdCap, DateTime Function()? clock}) =>
    CoinsCubit(wallet: wallet ?? MemoryWallet(), ads: ads ?? ScriptedAds(), dailyAdCap: dailyAdCap, clock: clock);

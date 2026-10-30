import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../monetization/domain/ad_pass.dart';
import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import '../domain/coin_wallet.dart';

/// How a tool was opened without paying coins.
enum UnlockCover { none, pass, grace, freeDaily }

class CoinsState extends Equatable {
  const CoinsState({this.balance = 0, this.adsToday = 0, this.watching = false, this.dailyCap, this.passUntil, this.passMinutes, this.passProgress = 0});
  final int balance;

  final int adsToday;

  /// True while a rewarded video is loading or playing.
  final bool watching;

  /// Videos allowed per day, or null when there is no limit.
  final int? dailyCap;

  final DateTime? passUntil;
  final int? passMinutes;
  final int passProgress;

  /// Videos still available today, or null when there is no limit.
  int? get adsLeft {
    final cap = dailyCap;
    return cap == null ? null : (cap - adsToday).clamp(0, cap);
  }

  bool get canWatch => adsLeft == null || adsLeft! > 0;

  /// Videos watched so far toward [pass] today.
  int progressFor(PassTier pass) => passMinutes == pass.minutes ? passProgress : 0;

  CoinsState copyWith({int? balance, int? adsToday, bool? watching, CoinSnapshot? snapshot}) => CoinsState(
    balance: snapshot?.balance ?? balance ?? this.balance,
    adsToday: snapshot?.adsToday ?? adsToday ?? this.adsToday,
    watching: watching ?? this.watching,
    dailyCap: dailyCap,
    passUntil: snapshot != null ? snapshot.passUntil : passUntil,
    passMinutes: snapshot != null ? snapshot.passMinutes : passMinutes,
    passProgress: snapshot?.passProgress ?? passProgress,
  );

  @override
  List<Object?> get props => [balance, adsToday, watching, dailyCap, passUntil, passMinutes, passProgress];
}

class CoinsCubit extends Cubit<CoinsState> {
  CoinsCubit({required CoinWallet wallet, required AdService ads, int? dailyAdCap = CoinRules.dailyAdCap, DateTime Function()? clock})
    : _wallet = wallet,
      _ads = ads,
      _now = clock ?? DateTime.now,
      super(CoinsState(dailyCap: dailyAdCap));

  final CoinWallet _wallet;
  final AdService _ads;
  final DateTime Function() _now;

  /// Set before the first await so two taps cannot start two videos.
  bool _playing = false;
  final _grace = <String, DateTime>{};

  Future<void> load() async {
    final s = await _wallet.read();
    AdPass.until.value = s.passUntil;
    if (!isClosed) emit(state.copyWith(snapshot: s));
  }

  /// Gives the day's free coins once; returns how many were added.
  Future<int> claimDaily() async {
    final added = await _wallet.claimDaily(CoinRules.dailyCoins);
    await load();
    return added;
  }

  bool get passActive {
    final until = state.passUntil;
    return until != null && until.isAfter(_now());
  }

  /// Plays a rewarded video and pays [CoinRules.rewardPerAd] coins only if it was watched to the end.
  Future<RewardResult> watchAd() => _watch((_) async {
    final s = await _wallet.earnFromAd(CoinRules.rewardPerAd);
    emit(state.copyWith(snapshot: s));
  });

  /// Plays a rewarded video that counts toward [pass]; the last one starts the pass.
  Future<RewardResult> watchForPass(PassTier pass) => _watch((_) async {
    final s = await _wallet.countPassVideo(minutes: pass.minutes, needed: pass.videos, length: pass.duration);
    AdPass.until.value = s.passUntil;
    emit(state.copyWith(snapshot: s));
  });

  Future<RewardResult> _watch(Future<void> Function(RewardResult) onEarned) async {
    if (_playing) return RewardResult.unavailable;
    _playing = true;
    try {
      await load();
      if (!state.canWatch) return RewardResult.limitReached;
      emit(state.copyWith(watching: true));
      final result = await _ads.showRewarded();
      if (result == RewardResult.earned) {
        await onEarned(result);
      }
      return result;
    } finally {
      _playing = false;
      if (!isClosed) emit(state.copyWith(watching: false));
    }
  }

  /// Opens a tool without coins when a pass is running, when it was paid for a moment ago, or on its free use of the day.
  Future<UnlockCover> coverWithoutCoins(CoinFeature feature) async {
    await load();
    if (passActive) return UnlockCover.pass;
    final until = _grace[feature.id];
    if (until != null && until.isAfter(_now())) return UnlockCover.grace;
    if (feature.hasFreeDailyUse && await _wallet.useFreeDaily(feature.id)) {
      _opened(feature);
      return UnlockCover.freeDaily;
    }
    return UnlockCover.none;
  }

  void _opened(CoinFeature feature) {
    if (feature.reopenFree) _grace[feature.id] = _now().add(CoinRules.reopenGrace);
  }

  /// Called after the coins were taken for [feature].
  void markPaid(CoinFeature feature) => _opened(feature);

  Future<void> refund(int coins) async {
    await _wallet.refund(coins);
    if (!isClosed) await load();
  }

  Future<bool> spend(int coins) async {
    final ok = await _wallet.spend(coins);
    await load();
    return ok;
  }
}

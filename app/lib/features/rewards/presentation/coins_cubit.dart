import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../monetization/domain/repositories/monetization_contracts.dart';
import '../domain/coin_rules.dart';
import '../domain/coin_wallet.dart';

class CoinsState extends Equatable {
  const CoinsState({this.balance = 0, this.adsToday = 0, this.watching = false, this.dailyCap});
  final int balance;
  final int adsToday;

  /// True while a rewarded video is loading or playing.
  final bool watching;

  /// Videos allowed per day, or null when there is no limit.
  final int? dailyCap;

  /// Videos still available today, or null when there is no limit.
  int? get adsLeft {
    final cap = dailyCap;
    return cap == null ? null : (cap - adsToday).clamp(0, cap);
  }

  bool get canWatch => adsLeft == null || adsLeft! > 0;

  CoinsState copyWith({int? balance, int? adsToday, bool? watching}) =>
      CoinsState(balance: balance ?? this.balance, adsToday: adsToday ?? this.adsToday, watching: watching ?? this.watching, dailyCap: dailyCap);

  @override
  List<Object?> get props => [balance, adsToday, watching, dailyCap];
}

class CoinsCubit extends Cubit<CoinsState> {
  CoinsCubit({required CoinWallet wallet, required AdService ads, int? dailyAdCap = CoinRules.dailyAdCap})
    : _wallet = wallet,
      _ads = ads,
      super(CoinsState(dailyCap: dailyAdCap));

  final CoinWallet _wallet;
  final AdService _ads;

  /// Set before the first await so two taps cannot start two videos.
  bool _playing = false;

  Future<void> load() async {
    final s = await _wallet.read();
    emit(state.copyWith(balance: s.balance, adsToday: s.adsToday));
  }

  /// Plays a rewarded video and pays [CoinRules.rewardPerAd] coins only if it was watched to the end.
  Future<RewardResult> watchAd() async {
    if (_playing) return RewardResult.unavailable;
    _playing = true;
    try {
      await load();
      if (!state.canWatch) return RewardResult.limitReached;
      emit(state.copyWith(watching: true));
      final result = await _ads.showRewarded();
      if (result == RewardResult.earned) {
        final s = await _wallet.earnFromAd(CoinRules.rewardPerAd);
        emit(state.copyWith(balance: s.balance, adsToday: s.adsToday));
      }
      return result;
    } finally {
      _playing = false;
      if (!isClosed) emit(state.copyWith(watching: false));
    }
  }

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

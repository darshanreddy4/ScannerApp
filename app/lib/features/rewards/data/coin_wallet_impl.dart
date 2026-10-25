import 'package:shared_preferences/shared_preferences.dart';

import '../domain/coin_wallet.dart';

class CoinWalletImpl implements CoinWallet {
  CoinWalletImpl({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  static const _coins = 'coins_balance';
  static const _day = 'coins_ad_day';
  static const _count = 'coins_ad_count';

  String get _today {
    final d = _now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  int _adsToday(SharedPreferences p) => p.getString(_day) == _today ? (p.getInt(_count) ?? 0) : 0;

  @override
  Future<CoinSnapshot> read() async {
    final p = await SharedPreferences.getInstance();
    return CoinSnapshot(balance: p.getInt(_coins) ?? 0, adsToday: _adsToday(p));
  }

  @override
  Future<CoinSnapshot> earnFromAd(int coins) async {
    final p = await SharedPreferences.getInstance();
    final next = (p.getInt(_coins) ?? 0) + coins;
    final ads = _adsToday(p) + 1;
    await p.setInt(_coins, next);
    await p.setString(_day, _today);
    await p.setInt(_count, ads);
    return CoinSnapshot(balance: next, adsToday: ads);
  }

  @override
  Future<bool> spend(int coins) async {
    final p = await SharedPreferences.getInstance();
    final balance = p.getInt(_coins) ?? 0;
    if (coins <= 0 || balance < coins) return false;
    await p.setInt(_coins, balance - coins);
    return true;
  }

  @override
  Future<void> refund(int coins) async {
    if (coins <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_coins, (p.getInt(_coins) ?? 0) + coins);
  }
}

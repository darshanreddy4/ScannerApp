import 'package:shared_preferences/shared_preferences.dart';

import '../domain/coin_wallet.dart';

class CoinWalletImpl implements CoinWallet {
  CoinWalletImpl({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;

  static const _coins = 'coins_balance';
  static const _day = 'coins_ad_day';
  static const _count = 'coins_ad_count';
  static const _claimDay = 'coins_claim_day';
  static const _freeDay = 'coins_free_day';
  static const _freeIds = 'coins_free_ids';
  static const _passUntil = 'coins_pass_until';
  static const _passMinutes = 'coins_pass_minutes';
  static const _passCount = 'coins_pass_count';
  static const _passDay = 'coins_pass_day';

  String get _today {
    final d = _now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  int _adsToday(SharedPreferences p) => p.getString(_day) == _today ? (p.getInt(_count) ?? 0) : 0;

  DateTime? _until(SharedPreferences p) {
    final ms = p.getInt(_passUntil);
    if (ms == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(_now()) ? until : null;
  }

  CoinSnapshot _snapshot(SharedPreferences p) {
    final today = p.getString(_passDay) == _today;
    return CoinSnapshot(
      balance: p.getInt(_coins) ?? 0,
      adsToday: _adsToday(p),
      passUntil: _until(p),
      passMinutes: today ? p.getInt(_passMinutes) : null,
      passProgress: today ? (p.getInt(_passCount) ?? 0) : 0,
    );
  }

  @override
  Future<CoinSnapshot> read() async => _snapshot(await SharedPreferences.getInstance());

  @override
  Future<CoinSnapshot> earnFromAd(int coins) async {
    final p = await SharedPreferences.getInstance();
    final next = (p.getInt(_coins) ?? 0) + coins;
    final ads = _adsToday(p) + 1;
    await p.setInt(_coins, next);
    await p.setString(_day, _today);
    await p.setInt(_count, ads);
    return _snapshot(p);
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

  @override
  Future<int> claimDaily(int coins) async {
    final p = await SharedPreferences.getInstance();
    if (p.getString(_claimDay) == _today) return 0;
    await p.setString(_claimDay, _today);
    await p.setInt(_coins, (p.getInt(_coins) ?? 0) + coins);
    return coins;
  }

  @override
  Future<CoinSnapshot> countPassVideo({required int minutes, required int needed, required Duration length}) async {
    final p = await SharedPreferences.getInstance();
    final sameDay = p.getString(_passDay) == _today;
    final same = sameDay && p.getInt(_passMinutes) == minutes;
    final count = (same ? (p.getInt(_passCount) ?? 0) : 0) + 1;
    await p.setString(_passDay, _today);
    await p.setInt(_passMinutes, minutes);
    if (count >= needed) {
      final now = _now();
      final running = _until(p);
      final start = running != null && running.isAfter(now) ? running : now;
      await p.setInt(_passUntil, start.add(length).millisecondsSinceEpoch);
      await p.setInt(_passCount, 0);
    } else {
      await p.setInt(_passCount, count);
    }
    return _snapshot(p);
  }

  @override
  Future<bool> useFreeDaily(String id) async {
    final p = await SharedPreferences.getInstance();
    final used = p.getString(_freeDay) == _today ? (p.getStringList(_freeIds) ?? const <String>[]) : const <String>[];
    if (used.contains(id)) return false;
    await p.setString(_freeDay, _today);
    await p.setStringList(_freeIds, [...used, id]);
    return true;
  }
}

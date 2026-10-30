import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/stamps.dart';

/// The stamps made by the person, kept on the phone only.
class StampStore {
  const StampStore();
  static const _key = 'custom_stamps';

  Future<List<Stamp>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      return [for (final o in jsonDecode(raw) as List) ?Stamp.fromJson(o)];
    } on Object {
      return const [];
    }
  }

  Future<void> _save(List<Stamp> stamps) async => (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final s in stamps) s.toJson()]));

  /// Adds a stamp at the front. The same stamp is not kept twice, and the oldest go beyond [maxCustomStamps].
  Future<List<Stamp>> add(Stamp stamp) async {
    final all = [stamp, ...(await load()).where((s) => s != stamp)].take(maxCustomStamps).toList();
    await _save(all);
    return all;
  }

  Future<List<Stamp>> remove(Stamp stamp) async {
    final all = (await load()).where((s) => s != stamp).toList();
    await _save(all);
    return all;
  }

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

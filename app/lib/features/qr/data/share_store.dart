import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/share_sessions.dart';

class SharedPrefsShareStore implements ShareStore {
  static const _key = 'active_internet_shares';

  @override
  Future<List<Map<String, Object?>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return [for (final item in jsonDecode(raw) as List<dynamic>) (item as Map<String, dynamic>).cast<String, Object?>()];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> save(List<Map<String, Object?>> shares) async {
    final prefs = await SharedPreferences.getInstance();
    if (shares.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(shares));
    }
  }
}

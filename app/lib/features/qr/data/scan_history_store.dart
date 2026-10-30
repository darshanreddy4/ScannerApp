import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scan_services.dart';

class SharedPrefsScanHistory implements ScanHistory {
  static const _key = 'qr_scan_history';
  static const _enabledKey = 'qr_scan_history_enabled';

  @override
  Future<List<ScanRecord>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final item in jsonDecode(raw) as List<dynamic>)
          if (item is Map && item['raw'] is String && item['at'] is int)
            ScanRecord(
              raw: item['raw'] as String,
              format: item['format'] is String ? item['format'] as String : '',
              at: DateTime.fromMillisecondsSinceEpoch(item['at'] as int),
            ),
      ];
    } on Object {
      return const [];
    }
  }

  Future<void> _write(List<ScanRecord> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
        _key,
        jsonEncode([
          for (final r in items) {'raw': r.raw, 'format': r.format, 'at': r.at.millisecondsSinceEpoch},
        ]),
      );
    }
  }

  @override
  Future<void> add(DetectedCode code, DateTime at) async {
    if (!await isEnabled() || code.raw.trim().isEmpty) return;
    final items = [...await list()];
    items.removeWhere((r) => r.raw == code.raw);
    items.insert(0, ScanRecord(raw: code.raw, format: code.format, at: at));
    await _write(items.take(ScanHistory.maxKept).toList());
  }

  @override
  Future<void> delete(String raw) async => _write([
    for (final r in await list())
      if (r.raw != raw) r,
  ]);

  @override
  Future<void> clear() => _write(const []);

  @override
  Future<bool> isEnabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;

  @override
  Future<void> setEnabled(bool value) async => (await SharedPreferences.getInstance()).setBool(_enabledKey, value);
}

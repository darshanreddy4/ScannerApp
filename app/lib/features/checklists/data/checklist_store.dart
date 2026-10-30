import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/checklists.dart';

/// The checklists, kept on the phone only.
class ChecklistStore {
  const ChecklistStore();
  static const _key = 'checklists';

  Future<List<Checklist>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      return [for (final o in jsonDecode(raw) as List) ?Checklist.fromJson(o)];
    } on Object {
      return const [];
    }
  }

  Future<List<Checklist>> _save(List<Checklist> lists) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final l in lists) l.toJson()]));
    return lists;
  }

  String newId(List<Checklist> lists, DateTime now) {
    var n = now.microsecondsSinceEpoch;
    while (lists.any((l) => l.id == '$n')) {
      n++;
    }
    return '$n';
  }

  /// Saves the list as a new one, or over the one with the same id.
  Future<List<Checklist>> put(Checklist list) async {
    final all = await load();
    final i = all.indexWhere((l) => l.id == list.id);
    if (i < 0) return _save([...all, list]);
    return _save([...all]..[i] = list);
  }

  Future<List<Checklist>> remove(String id) async => _save((await load()).where((l) => l.id != id).toList());

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

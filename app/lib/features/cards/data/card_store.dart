import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cards.dart';

/// The loyalty and membership cards, kept on the phone only.
class CardStore {
  const CardStore();
  static const _key = 'loyalty_cards';

  Future<List<LoyaltyCard>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const [];
    try {
      return [for (final o in jsonDecode(raw) as List) ?LoyaltyCard.fromJson(o)];
    } on Object {
      return const [];
    }
  }

  Future<List<LoyaltyCard>> _save(List<LoyaltyCard> cards) async {
    await (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final c in cards) c.toJson()]));
    return cards;
  }

  /// A new id that no saved card has.
  String newId(List<LoyaltyCard> cards, DateTime now) {
    var n = now.microsecondsSinceEpoch;
    while (cards.any((c) => c.id == '$n')) {
      n++;
    }
    return '$n';
  }

  /// Saves the card as a new one, or over the one with the same id.
  Future<List<LoyaltyCard>> put(LoyaltyCard card) async {
    final all = await load();
    final i = all.indexWhere((c) => c.id == card.id);
    if (i < 0) return _save([...all, card]);
    return _save([...all]..[i] = card);
  }

  Future<List<LoyaltyCard>> remove(String id) async => _save((await load()).where((c) => c.id != id).toList());

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

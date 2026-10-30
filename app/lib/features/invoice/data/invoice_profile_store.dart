import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../einvoice/domain/einvoice.dart' show InvoiceParty;

/// The details a person types once and reuses on every invoice. Kept on the phone only.
class InvoiceProfile {
  const InvoiceProfile({
    this.seller = const InvoiceParty(),
    this.iban = '',
    this.bic = '',
    this.currency = 'EUR',
    this.paymentDays = 14,
    this.lastNumber = '',
    this.language,
  });

  final InvoiceParty seller;
  final String iban;
  final String bic;
  final String currency;
  final int paymentDays;
  final String lastNumber;

  /// A language chosen on purpose; null follows the country of the seller.
  final String? language;

  Map<String, Object?> toJson() => {
    'name': seller.name,
    'street': seller.street,
    'postcode': seller.postcode,
    'city': seller.city,
    'country': seller.country,
    'vatId': seller.vatId,
    'email': seller.email,
    'iban': iban,
    'bic': bic,
    'currency': currency,
    'paymentDays': paymentDays,
    'lastNumber': lastNumber,
    'language': language,
  };

  static InvoiceProfile fromJson(Map<String, Object?> j) {
    String s(String k) => j[k] is String ? j[k]! as String : '';
    return InvoiceProfile(
      seller: InvoiceParty(
        name: s('name'),
        street: s('street'),
        postcode: s('postcode'),
        city: s('city'),
        country: s('country'),
        vatId: s('vatId'),
        email: s('email'),
      ),
      iban: s('iban'),
      bic: s('bic'),
      currency: s('currency').isEmpty ? 'EUR' : s('currency'),
      paymentDays: j['paymentDays'] is int ? j['paymentDays']! as int : 14,
      lastNumber: s('lastNumber'),
      language: j['language'] is String ? j['language']! as String : null,
    );
  }
}

class InvoiceProfileStore {
  const InvoiceProfileStore();
  static const _key = 'invoice_profile';

  Future<InvoiceProfile> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return const InvoiceProfile();
    try {
      return InvoiceProfile.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      return const InvoiceProfile();
    }
  }

  Future<void> save(InvoiceProfile profile) async => (await SharedPreferences.getInstance()).setString(_key, jsonEncode(profile.toJson()));

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

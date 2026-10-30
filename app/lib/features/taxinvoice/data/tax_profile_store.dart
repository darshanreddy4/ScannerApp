import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The details a person types once and reuses on every invoice of one kind, kept on the phone only.
class TaxProfileStore {
  const TaxProfileStore(this.key);
  final String key;

  Future<Map<String, String>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return const {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          if (e.value is String) e.key as String: e.value as String,
      };
    } on Object {
      return const {};
    }
  }

  Future<void> save(Map<String, String> values) async => (await SharedPreferences.getInstance()).setString(key, jsonEncode(values));

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(key);
}

const gstProfileKey = 'gst_profile';
const usInvoiceProfileKey = 'us_invoice_profile';
const zatcaProfileKey = 'zatca_profile';

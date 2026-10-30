import 'receipt_reader.dart';

/// Currencies offered for bills; the code is what the sheet shows.
const expenseCurrencies = [
  'INR',
  'USD',
  'EUR',
  'GBP',
  'AED',
  'SAR',
  'CAD',
  'AUD',
  'NZD',
  'SGD',
  'MYR',
  'THB',
  'JPY',
  'CNY',
  'CHF',
  'ZAR',
  'BRL',
  'MXN',
  'SEK',
  'NOK',
  'DKK',
  'PLN',
  'TRY',
  'PKR',
  'BDT',
  'LKR',
  'NPR',
];

const _byCountry = {
  'IN': 'INR',
  'US': 'USD',
  'GB': 'GBP',
  'AE': 'AED',
  'SA': 'SAR',
  'CA': 'CAD',
  'AU': 'AUD',
  'NZ': 'NZD',
  'SG': 'SGD',
  'MY': 'MYR',
  'TH': 'THB',
  'JP': 'JPY',
  'CN': 'CNY',
  'CH': 'CHF',
  'ZA': 'ZAR',
  'BR': 'BRL',
  'MX': 'MXN',
  'SE': 'SEK',
  'NO': 'NOK',
  'DK': 'DKK',
  'PL': 'PLN',
  'TR': 'TRY',
  'PK': 'PKR',
  'BD': 'BDT',
  'LK': 'LKR',
  'NP': 'NPR',
};

const _euro = {'DE', 'FR', 'ES', 'IT', 'NL', 'PT', 'IE', 'AT', 'BE', 'FI', 'GR', 'LU', 'SK', 'SI', 'EE', 'LV', 'LT', 'MT', 'CY', 'HR'};

/// The currency used where the phone is set, or empty when it is not one of the offered.
String currencyForCountry(String? country) {
  final c = country?.toUpperCase();
  if (c == null) return '';
  return _byCountry[c] ?? (_euro.contains(c) ? 'EUR' : '');
}

/// "₹1,23,456.50" (lakh grouping for rupees), "$1,234.50", "CHF 12.00"; without a currency just the number.
String formatMoney(double amount, String currency) {
  final negative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = fixed.substring(0, dot), cents = fixed.substring(dot + 1);
  final grouped = StringBuffer();
  final lakh = currency == 'INR' || currency == 'PKR' || currency == 'BDT' || currency == 'LKR' || currency == 'NPR';
  for (var i = 0; i < whole.length; i++) {
    final left = whole.length - i;
    grouped.write(whole[i]);
    if (left > 1 && (lakh ? (left == 4 || (left > 4 && (left - 3) % 2 == 1)) : left % 3 == 1)) grouped.write(',');
  }
  final sign = currency.isEmpty ? '' : currencySign(currency);
  final prefix = sign.length == 3 ? '$sign ' : sign;
  return '${negative ? '-' : ''}$prefix$grouped.$cents';
}

/// Where a tax-free purchase stands.
enum RefundStatus {
  toStamp('Needs the customs stamp'),
  stamped('Stamped at the border'),
  sent('Sent for refund'),
  refunded('Refunded');

  const RefundStatus(this.label);
  final String label;
}

class VatReceipt {
  const VatReceipt({
    required this.id,
    this.store = '',
    this.country = '',
    required this.date,
    this.totalCents = 0,
    this.vatCents = 0,
    this.currency = 'EUR',
    this.status = RefundStatus.toStamp,
    this.formNumber = '',
    this.note = '',
    this.photoPath,
  });

  final String id;
  final String store;

  /// The country of purchase, as a two-letter code.
  final String country;
  final DateTime date;

  /// What was paid, VAT included.
  final int totalCents;

  /// The VAT to be refunded, as written on the tax-free form; 0 when not known.
  final int vatCents;
  final String currency;
  final RefundStatus status;

  /// The number on the tax-free form, kept to find it again.
  final String formNumber;
  final String note;

  /// A picture of the receipt or form, kept in the app's private storage.
  final String? photoPath;

  VatReceipt copyWith({
    String? store,
    String? country,
    DateTime? date,
    int? totalCents,
    int? vatCents,
    String? currency,
    RefundStatus? status,
    String? formNumber,
    String? note,
    Object? photoPath = _keep,
  }) => VatReceipt(
    id: id,
    store: store ?? this.store,
    country: country ?? this.country,
    date: date ?? this.date,
    totalCents: totalCents ?? this.totalCents,
    vatCents: vatCents ?? this.vatCents,
    currency: currency ?? this.currency,
    status: status ?? this.status,
    formNumber: formNumber ?? this.formNumber,
    note: note ?? this.note,
    photoPath: identical(photoPath, _keep) ? this.photoPath : photoPath as String?,
  );

  static const _keep = Object();

  Map<String, Object?> toJson() => {
    'id': id,
    'store': store,
    'country': country,
    'date': date.millisecondsSinceEpoch,
    'total': totalCents,
    'vat': vatCents,
    'currency': currency,
    'status': status.name,
    'form': formNumber,
    'note': note,
    'photo': photoPath,
  };

  static VatReceipt? fromJson(Object? o) {
    if (o is! Map || o['id'] is! String || o['date'] is! int) return null;
    String s(String k) => o[k] is String ? o[k] as String : '';
    int n(String k) => o[k] is int ? o[k] as int : 0;
    return VatReceipt(
      id: o['id'] as String,
      store: s('store'),
      country: s('country'),
      date: DateTime.fromMillisecondsSinceEpoch(o['date'] as int),
      totalCents: n('total'),
      vatCents: n('vat'),
      currency: s('currency').isEmpty ? 'EUR' : s('currency'),
      status: RefundStatus.values.asNameMap()[o['status']] ?? RefundStatus.toStamp,
      formNumber: s('form'),
      note: s('note'),
      photoPath: o['photo'] is String ? o['photo'] as String : null,
    );
  }
}

/// Countries with a tax-free shopping scheme that people commonly use, with their usual currency and standard VAT rate.
/// Rates change and some goods have lower ones, so the rate is a starting point the person can overrule.
class RefundCountry {
  const RefundCountry(this.code, this.name, this.currency, this.vatRate);
  final String code;
  final String name;
  final String currency;
  final double vatRate;
}

const refundCountries = [
  RefundCountry('AT', 'Austria', 'EUR', 20),
  RefundCountry('BE', 'Belgium', 'EUR', 21),
  RefundCountry('BG', 'Bulgaria', 'EUR', 20),
  RefundCountry('HR', 'Croatia', 'EUR', 25),
  RefundCountry('CY', 'Cyprus', 'EUR', 19),
  RefundCountry('CZ', 'Czechia', 'CZK', 21),
  RefundCountry('DK', 'Denmark', 'DKK', 25),
  RefundCountry('EE', 'Estonia', 'EUR', 24),
  RefundCountry('FI', 'Finland', 'EUR', 25.5),
  RefundCountry('FR', 'France', 'EUR', 20),
  RefundCountry('DE', 'Germany', 'EUR', 19),
  RefundCountry('GR', 'Greece', 'EUR', 24),
  RefundCountry('HU', 'Hungary', 'HUF', 27),
  RefundCountry('IE', 'Ireland', 'EUR', 23),
  RefundCountry('IT', 'Italy', 'EUR', 22),
  RefundCountry('LV', 'Latvia', 'EUR', 21),
  RefundCountry('LT', 'Lithuania', 'EUR', 21),
  RefundCountry('LU', 'Luxembourg', 'EUR', 17),
  RefundCountry('MT', 'Malta', 'EUR', 18),
  RefundCountry('NL', 'Netherlands', 'EUR', 21),
  RefundCountry('PL', 'Poland', 'PLN', 23),
  RefundCountry('PT', 'Portugal', 'EUR', 23),
  RefundCountry('RO', 'Romania', 'RON', 21),
  RefundCountry('SK', 'Slovakia', 'EUR', 23),
  RefundCountry('SI', 'Slovenia', 'EUR', 22),
  RefundCountry('ES', 'Spain', 'EUR', 21),
  RefundCountry('SE', 'Sweden', 'SEK', 25),
  RefundCountry('CH', 'Switzerland', 'CHF', 8.1),
  RefundCountry('NO', 'Norway', 'NOK', 25),
];

RefundCountry? refundCountry(String code) => refundCountries.where((c) => c.code == code.toUpperCase()).firstOrNull;

/// The VAT inside a price that already includes it: `total * rate / (100 + rate)`, rounded to the cent.
int vatInPrice(int totalCents, double ratePercent) => ((totalCents * ratePercent * 100) / (100 + ratePercent) / 100).round();

/// The last day goods may leave: in the usual EU rule the end of the third month after the month of purchase.
/// The tax-free form of the shop is what counts, so the person can check it against this.
DateTime exportDeadline(DateTime purchase) => DateTime(purchase.year, purchase.month + 4, 0);

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [now] to the deadline; negative once it has passed.
int daysLeft(DateTime purchase, DateTime now) => _day(exportDeadline(purchase)).difference(_day(now)).inDays;

/// A receipt that still needs its stamp but whose deadline has passed.
bool isExpired(VatReceipt r, DateTime now) => r.status == RefundStatus.toStamp && daysLeft(r.date, now) < 0;

class CurrencyTotal {
  const CurrencyTotal({required this.currency, this.waitingCents = 0, this.stampedCents = 0, this.refundedCents = 0, this.lostCents = 0});
  final String currency;

  /// VAT on receipts that still need the stamp.
  final int waitingCents;

  /// VAT on receipts that are stamped or sent, so a refund is on its way.
  final int stampedCents;
  final int refundedCents;

  /// VAT on receipts whose deadline passed without a stamp.
  final int lostCents;
}

/// VAT amounts per currency, by where each receipt stands.
List<CurrencyTotal> summarize(Iterable<VatReceipt> receipts, DateTime now) {
  final byCurrency = <String, List<int>>{};
  for (final r in receipts) {
    final t = byCurrency.putIfAbsent(r.currency, () => [0, 0, 0, 0]);
    if (isExpired(r, now)) {
      t[3] += r.vatCents;
    } else {
      switch (r.status) {
        case RefundStatus.toStamp:
          t[0] += r.vatCents;
        case RefundStatus.stamped || RefundStatus.sent:
          t[1] += r.vatCents;
        case RefundStatus.refunded:
          t[2] += r.vatCents;
      }
    }
  }
  final currencies = byCurrency.keys.toList()..sort();
  return [
    for (final c in currencies)
      CurrencyTotal(
        currency: c,
        waitingCents: byCurrency[c]![0],
        stampedCents: byCurrency[c]![1],
        refundedCents: byCurrency[c]![2],
        lostCents: byCurrency[c]![3],
      ),
  ];
}

String _csv(String v) => v.contains(RegExp('[",\n;]')) ? '"${v.replaceAll('"', '""')}"' : v;

String _amount(int cents) => '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The receipts as a table for a spreadsheet, newest first.
String receiptsCsv(Iterable<VatReceipt> receipts) {
  final rows = receipts.toList()..sort((a, b) => b.date.compareTo(a.date));
  final out = StringBuffer('Date,Store,Country,Currency,Total,VAT,Status,Deadline,Form number,Note\n');
  for (final r in rows) {
    out.writeln(
      [
        _date(r.date),
        _csv(r.store),
        r.country,
        r.currency,
        _amount(r.totalCents),
        _amount(r.vatCents),
        r.status.name,
        _date(exportDeadline(r.date)),
        _csv(r.formNumber),
        _csv(r.note),
      ].join(','),
    );
  }
  return out.toString();
}

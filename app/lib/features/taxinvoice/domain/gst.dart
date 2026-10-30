import 'tax_common.dart';

class GstState {
  const GstState(this.code, this.name, {this.unionTerritory = false});
  final String code;
  final String name;

  /// A union territory without a legislature, which charges UTGST in place of SGST.
  final bool unionTerritory;
}

/// The state and union territory codes of the first two digits of a GSTIN, and of the place of supply on an invoice.
const gstStates = <GstState>[
  GstState('01', 'Jammu and Kashmir'),
  GstState('02', 'Himachal Pradesh'),
  GstState('03', 'Punjab'),
  GstState('04', 'Chandigarh', unionTerritory: true),
  GstState('05', 'Uttarakhand'),
  GstState('06', 'Haryana'),
  GstState('07', 'Delhi'),
  GstState('08', 'Rajasthan'),
  GstState('09', 'Uttar Pradesh'),
  GstState('10', 'Bihar'),
  GstState('11', 'Sikkim'),
  GstState('12', 'Arunachal Pradesh'),
  GstState('13', 'Nagaland'),
  GstState('14', 'Manipur'),
  GstState('15', 'Mizoram'),
  GstState('16', 'Tripura'),
  GstState('17', 'Meghalaya'),
  GstState('18', 'Assam'),
  GstState('19', 'West Bengal'),
  GstState('20', 'Jharkhand'),
  GstState('21', 'Odisha'),
  GstState('22', 'Chhattisgarh'),
  GstState('23', 'Madhya Pradesh'),
  GstState('24', 'Gujarat'),
  GstState('26', 'Dadra and Nagar Haveli and Daman and Diu', unionTerritory: true),
  GstState('27', 'Maharashtra'),
  GstState('28', 'Andhra Pradesh (old code)'),
  GstState('29', 'Karnataka'),
  GstState('30', 'Goa'),
  GstState('31', 'Lakshadweep', unionTerritory: true),
  GstState('32', 'Kerala'),
  GstState('33', 'Tamil Nadu'),
  GstState('34', 'Puducherry'),
  GstState('35', 'Andaman and Nicobar Islands', unionTerritory: true),
  GstState('36', 'Telangana'),
  GstState('37', 'Andhra Pradesh'),
  GstState('38', 'Ladakh', unionTerritory: true),
  GstState('97', 'Other Territory'),
  GstState('99', 'Centre Jurisdiction'),
];

GstState? gstStateOf(String code) => gstStates.where((s) => s.code == code).firstOrNull;

const _gstChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// The last character of a GSTIN, worked out from the first 14.
String gstinCheckChar(String first14) {
  var sum = 0;
  for (var i = 0; i < first14.length; i++) {
    final product = _gstChars.indexOf(first14[i]) * (i.isEven ? 1 : 2);
    sum += product ~/ 36 + product % 36;
  }
  return _gstChars[(36 - sum % 36) % 36];
}

final _gstinShape = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
final _panShape = RegExp(r'^[A-Z]{5}\d{4}[A-Z]$');

/// What is wrong with a GSTIN, or null when it is a well-formed number whose check character is right.
TaxIssue? gstinIssue(String field, String gstin) {
  final g = gstin.trim().toUpperCase();
  if (g.length != 15) return TaxIssue(field, 'A GSTIN has 15 characters, for example 27AAPFU0939F1ZV.');
  if (!_gstinShape.hasMatch(g))
    return TaxIssue(field, 'This is not the shape of a GSTIN: two digits for the state, the 10 characters of the PAN, then 1Z and a check character.');
  if (gstStateOf(g.substring(0, 2)) == null)
    return TaxIssue(field, 'The first two digits of a GSTIN are a state code, and {code} is not one.', {'code': g.substring(0, 2)});
  if (gstinCheckChar(g.substring(0, 14)) != g[14])
    return TaxIssue(field, 'The last character of this GSTIN is not right. Check it against your registration certificate.');
  return null;
}

/// The PAN inside a GSTIN.
String? panOfGstin(String gstin) => gstin.trim().length == 15 ? gstin.trim().toUpperCase().substring(2, 12) : null;

bool isValidPan(String pan) => _panShape.hasMatch(pan.trim().toUpperCase());

bool isValidPin(String pin) => RegExp(r'^[1-9]\d{5}$').hasMatch(pin.trim());

bool isValidIfsc(String ifsc) => RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifsc.trim().toUpperCase());

/// An HSN code (goods) is 4, 6 or 8 digits and a SAC (services) is 6; left empty it is allowed for small sellers.
bool isValidHsn(String hsn) => RegExp(r'^(\d{4}|\d{6}|\d{8})$').hasMatch(hsn.trim());

/// Up to 16 letters, digits, / and -, as the GST rules say, and no more.
bool isValidGstInvoiceNumber(String n) => RegExp(r'^[A-Za-z0-9/\-]{1,16}$').hasMatch(n.trim());

/// The financial year of a date as `25-26`: April to March.
String financialYear(DateTime d) {
  final start = d.month >= 4 ? d.year : d.year - 1;
  String two(int y) => (y % 100).toString().padLeft(2, '0');
  return '${two(start)}-${two(start + 1)}';
}

/// The number after [last]; a new financial year starts again at 1. With nothing before it: INV/25-26/001.
String nextGstInvoiceNumber(String last, DateTime now) {
  final fy = financialYear(now);
  final t = last.trim();
  final m = RegExp(r'^(.*?)(\d{2}-\d{2})([/-])(\d+)$').firstMatch(t);
  if (m != null) {
    final width = m[4]!.length;
    final n = m[2] == fy ? int.parse(m[4]!) + 1 : 1;
    return '${m[1]}$fy${m[3]}${n.toString().padLeft(width, '0')}';
  }
  final tail = RegExp(r'^(.*?)(\d+)$').firstMatch(t);
  if (tail != null) return '${tail[1]}${(int.parse(tail[2]!) + 1).toString().padLeft(tail[2]!.length, '0')}';
  return 'INV/$fy/001';
}

enum GstDocument { taxInvoice, billOfSupply }

class GstParty {
  const GstParty({this.name = '', this.address = '', this.city = '', this.pin = '', this.stateCode = '', this.gstin = '', this.phone = '', this.email = ''});
  final String name;
  final String address;
  final String city;
  final String pin;
  final String stateCode;
  final String gstin;
  final String phone;
  final String email;

  String get stateName => gstStateOf(stateCode)?.name ?? '';

  /// The postal address in lines.
  String get addressText => [
    address.trim(),
    [city.trim(), pin.trim()].where((s) => s.isNotEmpty).join(' - '),
  ].where((s) => s.isNotEmpty).join(', ');
}

class GstLine {
  const GstLine({required this.description, this.hsn = '', required this.quantity, this.unit = '', required this.unitPriceCents, this.rateHundredths = 0});
  final String description;
  final String hsn;
  final double quantity;
  final String unit;
  final int unitPriceCents;

  /// GST in hundredths of a percent: 18% is 1800.
  final int rateHundredths;

  /// The value before tax, in paise, rounded half up.
  int get taxableCents => ((quantity * 1000).round() * unitPriceCents + 500) ~/ 1000;
}

class GstDraft {
  const GstDraft({
    this.document = GstDocument.taxInvoice,
    this.seller = const GstParty(),
    this.buyer = const GstParty(),
    this.number = '',
    required this.date,
    this.placeOfSupply = '',
    this.reverseCharge = false,
    this.items = const [],
    this.notes = '',
    this.bankName = '',
    this.accountNumber = '',
    this.ifsc = '',
    this.upiId = '',
  });

  final GstDocument document;
  final GstParty seller;
  final GstParty buyer;
  final String number;
  final DateTime date;

  /// The state code the goods or services are supplied in.
  final String placeOfSupply;
  final bool reverseCharge;
  final List<GstLine> items;
  final String notes;
  final String bankName;
  final String accountNumber;
  final String ifsc;
  final String upiId;

  bool get isTax => document == GstDocument.taxInvoice;

  /// Supply from one state to another: IGST in place of CGST and SGST.
  bool get interState => placeOfSupply.isNotEmpty && placeOfSupply != seller.stateCode;

  bool get sellerIsUt => gstStateOf(seller.stateCode)?.unionTerritory ?? false;
}

class GstLineTax {
  const GstLineTax({required this.taxable, required this.cgst, required this.sgst, required this.igst});
  final int taxable;
  final int cgst;
  final int sgst;
  final int igst;
  int get tax => cgst + sgst + igst;
  int get total => taxable + tax;
}

class GstTotals {
  const GstTotals({
    required this.lines,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.total,
    required this.roundOff,
  });
  final List<GstLineTax> lines;
  final int taxable;
  final int cgst;
  final int sgst;
  final int igst;

  /// Before rounding to the rupee.
  final int total;

  /// What is added to reach the whole rupee, from -49 to 50 paise.
  final int roundOff;

  int get tax => cgst + sgst + igst;
  int get grand => total + roundOff;
}

/// Tax per line: half of the rate as CGST and half as SGST (or UTGST) inside a state, the whole rate as IGST between states.
/// A bill of supply carries no tax.
GstTotals computeGst(GstDraft d) {
  final lines = <GstLineTax>[];
  for (final i in d.items) {
    final taxable = i.taxableCents;
    if (!d.isTax || i.rateHundredths == 0) {
      lines.add(GstLineTax(taxable: taxable, cgst: 0, sgst: 0, igst: 0));
    } else if (d.interState) {
      lines.add(GstLineTax(taxable: taxable, cgst: 0, sgst: 0, igst: percentOf(taxable, i.rateHundredths)));
    } else {
      final half = (taxable * i.rateHundredths + 10000) ~/ 20000;
      lines.add(GstLineTax(taxable: taxable, cgst: half, sgst: half, igst: 0));
    }
  }
  final taxable = lines.fold(0, (a, l) => a + l.taxable);
  final cgst = lines.fold(0, (a, l) => a + l.cgst);
  final sgst = lines.fold(0, (a, l) => a + l.sgst);
  final igst = lines.fold(0, (a, l) => a + l.igst);
  final total = taxable + cgst + sgst + igst;
  final rounded = ((total + 50) ~/ 100) * 100;
  return GstTotals(lines: lines, taxable: taxable, cgst: cgst, sgst: sgst, igst: igst, total: total, roundOff: rounded - total);
}

/// One row of the tax summary: lines with the same HSN and rate added together.
class HsnRow {
  const HsnRow({required this.hsn, required this.rateHundredths, required this.taxable, required this.cgst, required this.sgst, required this.igst});
  final String hsn;
  final int rateHundredths;
  final int taxable;
  final int cgst;
  final int sgst;
  final int igst;
}

List<HsnRow> hsnSummary(GstDraft d, GstTotals t) {
  final rows = <String, List<int>>{};
  for (var i = 0; i < d.items.length; i++) {
    final item = d.items[i];
    final key = '${item.hsn.trim()}|${item.rateHundredths}';
    final r = rows.putIfAbsent(key, () => [0, 0, 0, 0]);
    r[0] += t.lines[i].taxable;
    r[1] += t.lines[i].cgst;
    r[2] += t.lines[i].sgst;
    r[3] += t.lines[i].igst;
  }
  return [
    for (final e in rows.entries)
      HsnRow(
        hsn: e.key.split('|').first,
        rateHundredths: int.parse(e.key.split('|').last),
        taxable: e.value[0],
        cgst: e.value[1],
        sgst: e.value[2],
        igst: e.value[3],
      ),
  ];
}

/// How a rate in hundredths of a percent is written: 1800 is 18, 250 is 2.5, 25 is 0.25.
String rateText(int hundredths) {
  if (hundredths % 100 == 0) return '${hundredths ~/ 100}';
  if (hundredths % 10 == 0) return (hundredths / 100).toStringAsFixed(1);
  return (hundredths / 100).toStringAsFixed(2);
}

/// The rates offered to tap. The GST Council sets and changes them, so the person can always type another.
const gstRateChips = [0, 5, 18, 40, 3, 0.25];

const maxGstItems = 50;

/// Everything wrong with the invoice, each with the field it belongs to; empty when it can be made.
List<TaxIssue> gstIssues(GstDraft d) {
  final out = <TaxIssue>[];
  final s = d.seller, b = d.buyer;
  if (s.name.trim().isEmpty) out.add(const TaxIssue('seller.name', 'Enter your business name.'));
  if (s.address.trim().isEmpty) out.add(const TaxIssue('seller.address', 'Enter your address.'));
  if (s.pin.trim().isNotEmpty && !isValidPin(s.pin)) out.add(const TaxIssue('seller.pin', 'A PIN code has 6 digits and does not start with 0.'));
  if (s.stateCode.isEmpty) out.add(const TaxIssue('seller.state', 'Choose your state.'));
  if (s.gstin.trim().isEmpty) {
    if (d.isTax) out.add(const TaxIssue('seller.gstin', 'Enter your GSTIN. A tax invoice can only be issued by a registered seller.'));
  } else {
    final issue = gstinIssue('seller.gstin', s.gstin);
    if (issue != null) {
      out.add(issue);
    } else if (s.stateCode.isNotEmpty && s.gstin.trim().substring(0, 2) != s.stateCode) {
      out.add(
        TaxIssue('seller.gstin', 'Your GSTIN starts with {code}, the code of {state}, but your state is {chosen}.', {
          'code': s.gstin.trim().substring(0, 2),
          'state': gstStateOf(s.gstin.trim().substring(0, 2))?.name ?? '',
          'chosen': s.stateName,
        }),
      );
    }
  }
  if (s.email.trim().isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.email.trim()))
    out.add(const TaxIssue('seller.email', 'The email address is not valid.'));
  if (b.name.trim().isEmpty) out.add(const TaxIssue('buyer.name', 'Enter the customer\'s name.'));
  if (b.pin.trim().isNotEmpty && !isValidPin(b.pin)) out.add(const TaxIssue('buyer.pin', 'A PIN code has 6 digits and does not start with 0.'));
  if (b.gstin.trim().isNotEmpty) {
    final issue = gstinIssue('buyer.gstin', b.gstin);
    if (issue != null) {
      out.add(issue);
    } else if (b.stateCode.isNotEmpty && b.gstin.trim().substring(0, 2) != b.stateCode) {
      out.add(
        TaxIssue('buyer.gstin', 'The customer\'s GSTIN starts with {code}, the code of {state}, but the state chosen is {chosen}.', {
          'code': b.gstin.trim().substring(0, 2),
          'state': gstStateOf(b.gstin.trim().substring(0, 2))?.name ?? '',
          'chosen': b.stateName,
        }),
      );
    }
  }
  if (d.placeOfSupply.isEmpty) out.add(const TaxIssue('place', 'Choose the place of supply: the state the goods or services go to.'));
  if (d.number.trim().isEmpty) {
    out.add(const TaxIssue('number', 'Enter an invoice number.'));
  } else if (!isValidGstInvoiceNumber(d.number)) {
    out.add(const TaxIssue('number', 'An invoice number has up to 16 letters, digits, / or -, with no spaces.'));
  }
  if (d.items.isEmpty) out.add(const TaxIssue('items', 'Add at least one item.'));
  if (d.items.length > maxGstItems) out.add(const TaxIssue('items', 'An invoice has up to 50 items.'));
  for (final (n, i) in d.items.indexed) {
    if (i.description.trim().isEmpty) out.add(TaxIssue('item.$n.description', 'Item {n}: describe what was sold.', {'n': n + 1}));
    if (i.hsn.trim().isNotEmpty && !isValidHsn(i.hsn)) out.add(TaxIssue('item.$n.hsn', 'An HSN or SAC code is 4, 6 or 8 digits.'));
    if (i.rateHundredths > 4000) out.add(TaxIssue('item.$n.rate', 'The GST rate of item {n} is above 40%.', {'n': n + 1}));
  }
  if (d.upiId.trim().isNotEmpty && !RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-_]{1,255}@[A-Za-z][A-Za-z0-9]{1,63}$').hasMatch(d.upiId.trim())) {
    out.add(const TaxIssue('upi', 'A UPI ID looks like name@bank.'));
  }
  if (d.ifsc.trim().isNotEmpty && !isValidIfsc(d.ifsc)) out.add(const TaxIssue('ifsc', 'An IFSC code has 4 letters, a 0, then 6 letters or digits.'));
  if (d.accountNumber.trim().isNotEmpty && !RegExp(r'^\d{9,18}$').hasMatch(d.accountNumber.trim())) {
    out.add(const TaxIssue('account', 'An account number has 9 to 18 digits.'));
  }
  return out;
}

/// The words that say what the document is.
String gstTitle(GstDraft d) => d.isTax ? 'TAX INVOICE' : 'BILL OF SUPPLY';

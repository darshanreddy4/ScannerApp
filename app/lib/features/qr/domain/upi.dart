import 'payments.dart';

/// UPI payment codes of India: `upi://pay?pa=name@bank&pn=Name&am=250.00&cu=INR&tn=Note`.
final _upiIdRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-_]{1,255}@[A-Za-z][A-Za-z0-9]{1,63}$');

/// The bank handles (the part after the @) of the apps and banks that take UPI. Not complete: an unknown one is only a warning.
const upiHandles = {
  'abfspay',
  'airtel',
  'allbank',
  'apl',
  'aubank',
  'axisb',
  'axisbank',
  'axl',
  'barodampay',
  'boi',
  'cboi',
  'cmsidfc',
  'cnrb',
  'csbpay',
  'dbs',
  'dcb',
  'dlb',
  'equitas',
  'fam',
  'fbl',
  'federal',
  'freecharge',
  'hdfcbank',
  'hsbc',
  'ibl',
  'icici',
  'idbi',
  'idfcbank',
  'idfcfirst',
  'indbank',
  'indianbank',
  'indus',
  'iob',
  'ippb',
  'jio',
  'jsb',
  'jupiter',
  'karb',
  'kbl',
  'kotak',
  'kvb',
  'kvbl',
  'naviaxis',
  'okaxis',
  'okhdfcbank',
  'okicici',
  'oksbi',
  'paytm',
  'pingpay',
  'pnb',
  'postbank',
  'psb',
  'ptaxis',
  'pthdfc',
  'ptsbi',
  'ptyes',
  'pz',
  'rbl',
  'sbi',
  'sc',
  'sib',
  'slice',
  'superyes',
  'tapicici',
  'tjsb',
  'ubi',
  'uboi',
  'ucobank',
  'upi',
  'utbi',
  'waaxis',
  'wahdfcbank',
  'waicici',
  'wasbi',
  'yapl',
  'ybl',
  'yesbank',
};

/// The most one UPI payment can be for in any category; most apps and banks stop at 1,00,000.
const upiMaxAmount = 500000;
const upiUsualLimit = 100000;

bool isUpiId(String id) => _upiIdRe.hasMatch(id.trim());

bool isKnownUpiHandle(String id) {
  final at = id.lastIndexOf('@');
  return at >= 0 && upiHandles.contains(id.substring(at + 1).trim().toLowerCase());
}

/// What is wrong with a UPI ID, or null when it is fine.
String? upiIdProblem(String id) {
  final t = id.trim();
  if (t.isEmpty) return 'Enter the UPI ID.';
  if (!isUpiId(t)) return 'A UPI ID looks like name@bank or 9876543210@upi: letters, numbers, dots or dashes, then @ and the bank.';
  return null;
}

/// A warning for a UPI ID that is well formed but has a bank handle the app does not know; null when there is nothing to say.
String? upiIdWarning(String id) {
  if (!isUpiId(id) || isKnownUpiHandle(id.trim())) return null;
  return 'This bank handle is not one Doculoom knows. Check the spelling: a UPI app only accepts its own handles.';
}

/// What is wrong with an amount for a UPI payment (empty is fine: the payer types it), or null.
String? upiAmountProblem(String amount) {
  if (amount.trim().isEmpty) return null;
  final n = normalizeAmount(amount);
  if (n == null) return 'The amount is not valid. Use numbers such as 250 or 250.50.';
  if (double.parse(n) > upiMaxAmount) return 'UPI does not allow more than 5,00,000 rupees in one payment.';
  return null;
}

String? upiAmountWarning(String amount) {
  final n = normalizeAmount(amount);
  if (n == null || double.parse(n) <= upiUsualLimit) return null;
  return 'Most UPI apps allow up to 1,00,000 rupees in one payment. Tax, hospital and education payments can be more.';
}

const upiMaxName = 50;
const upiMaxNote = 50;

/// What is wrong with the details for a UPI code, or null when it can be made.
String? upiProblem({required String id, required String name, String amount = '', String note = ''}) {
  final i = upiIdProblem(id);
  if (i != null) return i;
  if (name.trim().isEmpty) return 'Enter who is paid.';
  if (name.trim().length > upiMaxName) return 'The name is too long (50 letters at most).';
  final a = upiAmountProblem(amount);
  if (a != null) return a;
  if (note.trim().length > upiMaxNote) return 'The note is too long (50 characters at most).';
  return null;
}

/// The text of a UPI payment QR code. Call [upiProblem] first.
String upiPayload({required String id, required String name, String amount = '', String note = ''}) {
  final b = StringBuffer('upi://pay?pa=${id.trim()}&pn=${Uri.encodeComponent(name.trim())}');
  final a = normalizeAmount(amount);
  if (a != null) b.write('&am=$a');
  b.write('&cu=INR');
  if (note.trim().isNotEmpty) b.write('&tn=${Uri.encodeComponent(note.trim())}');
  return b.toString();
}

/// Reads a UPI payment code; null when the text is not one. An ID that is not valid is kept as written, so the card can say so.
PaymentRequest? parseUpi(String raw) {
  final t = raw.trim();
  if (!RegExp(r'^upi://pay\?', caseSensitive: false).hasMatch(t)) return null;
  final uri = Uri.tryParse(t);
  if (uri == null) return null;
  final q = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value.trim()};
  final pa = q['pa'] ?? '';
  if (pa.isEmpty) return null;
  final am = q['am'] ?? '';
  return PaymentRequest(
    scheme: 'UPI',
    name: q['pn'] ?? '',
    iban: '',
    vpa: pa,
    currency: (q['cu'] ?? 'INR').toUpperCase(),
    amount: RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(am) ? am : '',
    reference: q['tr'] ?? '',
    message: q['tn'] ?? '',
  );
}

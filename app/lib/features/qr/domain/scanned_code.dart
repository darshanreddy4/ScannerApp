import '../../contacts/domain/contact_parser.dart';
import 'payments.dart';
import 'upi.dart';
import 'qr_payloads.dart';

/// What a scanned QR code or barcode holds, which decides the actions offered for it.
enum CodeKind { link, wifi, contact, email, phone, sms, location, payment, product, text }

class WifiNetwork {
  const WifiNetwork({required this.ssid, this.password = '', this.security = WifiSecurity.wpa, this.hidden = false});
  final String ssid;
  final String password;
  final WifiSecurity security;
  final bool hidden;
}

class ScannedCode {
  const ScannedCode({
    required this.raw,
    required this.kind,
    this.format = '',
    this.link,
    this.wifi,
    this.contact,
    this.payment,
    this.address,
    this.number,
    this.subject,
    this.body,
    this.latitude,
    this.longitude,
  });

  /// The text exactly as read from the code.
  final String raw;
  final CodeKind kind;

  /// The name of the code type, such as `qrCode` or `ean13`.
  final String format;

  /// A web address that can be opened (always http or https).
  final String? link;
  final WifiNetwork? wifi;
  final ContactDraft? contact;
  final PaymentRequest? payment;

  /// An email address.
  final String? address;

  /// A phone number, for calling or texting.
  final String? number;
  final String? subject;
  final String? body;
  final double? latitude;
  final double? longitude;

  String? get host => link == null ? null : Uri.tryParse(link!)?.host;

  /// A short line for lists: the most telling part of the code.
  String get summary => switch (kind) {
    CodeKind.link => link!,
    CodeKind.wifi => wifi!.ssid,
    CodeKind.contact => contact!.name.isNotEmpty ? contact!.name : (contact!.phones.firstOrNull ?? contact!.emails.firstOrNull ?? raw),
    CodeKind.email => address!,
    CodeKind.phone || CodeKind.sms => number!,
    CodeKind.location => '${_coord(latitude!)}, ${_coord(longitude!)}',
    CodeKind.payment => payment!.amountText.isEmpty ? payment!.name : '${payment!.name}, ${payment!.amountText}',
    CodeKind.product || CodeKind.text => raw,
  };

  static String _coord(double v) => v.toStringAsFixed(5).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  /// Where a map app can show a location, as a standard `geo:` address.
  String? get geoUri => kind == CodeKind.location ? 'geo:${_coord(latitude!)},${_coord(longitude!)}' : null;
}

const _oneDimensional = {'ean13', 'ean8', 'upca', 'upce', 'code39', 'code93', 'code128', 'codabar', 'itf', 'itf14', 'itf2of5', 'itf2of5withchecksum'};

final _emailOnly = RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$');
final _webOnly = RegExp(r'^https?://[^\s/$.?#][^\s]*$', caseSensitive: false);
final _wwwOnly = RegExp(r'^www\.[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)+(?:[/?#]\S*)?$', caseSensitive: false);
final _phoneOnly = RegExp(r'^\+?[\d\s().\-]{3,}$');

/// Works out what a code is. Anything not recognised is plain text, so nothing is ever lost.
ScannedCode parseCode(String input, {String format = ''}) {
  final raw = input.trim();
  final f = format.toLowerCase();
  ScannedCode text() => ScannedCode(raw: raw, kind: _oneDimensional.contains(f) ? CodeKind.product : CodeKind.text, format: format);
  if (raw.isEmpty) return text();
  final lower = raw.toLowerCase();

  if (raw.startsWith('BCD')) {
    final pay = parseEpc(raw);
    if (pay != null) return ScannedCode(raw: raw, kind: CodeKind.payment, format: format, payment: pay);
  }
  if (lower.startsWith('upi://pay')) {
    final pay = parseUpi(raw);
    if (pay != null) return ScannedCode(raw: raw, kind: CodeKind.payment, format: format, payment: pay);
  }
  if (raw.startsWith('SPC')) {
    final pay = parseSwissQrBill(raw);
    if (pay != null) return ScannedCode(raw: raw, kind: CodeKind.payment, format: format, payment: pay);
  }
  if (lower.startsWith('wifi:')) {
    final wifi = _parseWifi(raw.substring(5));
    if (wifi != null) return ScannedCode(raw: raw, kind: CodeKind.wifi, format: format, wifi: wifi);
    return text();
  }
  if (lower.startsWith('mecard:')) {
    final c = _parseMeCard(raw.substring(7));
    if (!c.isEmpty) return ScannedCode(raw: raw, kind: CodeKind.contact, format: format, contact: c);
    return text();
  }
  if (lower.startsWith('begin:vcard')) {
    final c = _parseVCard(raw);
    if (!c.isEmpty) return ScannedCode(raw: raw, kind: CodeKind.contact, format: format, contact: c);
    return text();
  }
  if (lower.startsWith('mailto:')) {
    final uri = Uri.tryParse(raw);
    final address = uri == null ? '' : Uri.decodeComponent(uri.path).trim();
    if (_emailOnly.hasMatch(address)) {
      return ScannedCode(
        raw: raw,
        kind: CodeKind.email,
        format: format,
        address: address,
        subject: uri!.queryParameters['subject'],
        body: uri.queryParameters['body'],
      );
    }
    return text();
  }
  if (lower.startsWith('tel:')) {
    final number = raw.substring(4).trim();
    if (_phoneOnly.hasMatch(number)) return ScannedCode(raw: raw, kind: CodeKind.phone, format: format, number: number);
    return text();
  }
  if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
    final rest = raw.substring(lower.startsWith('smsto:') ? 6 : 4);
    String number, body = '';
    if (lower.startsWith('smsto:')) {
      final i = rest.indexOf(':');
      number = (i < 0 ? rest : rest.substring(0, i)).trim();
      body = i < 0 ? '' : rest.substring(i + 1);
    } else {
      final i = rest.indexOf('?');
      number = (i < 0 ? rest : rest.substring(0, i)).trim();
      if (i >= 0) body = Uri.tryParse('x://x?${rest.substring(i + 1)}')?.queryParameters['body'] ?? '';
    }
    if (_phoneOnly.hasMatch(number)) {
      return ScannedCode(raw: raw, kind: CodeKind.sms, format: format, number: number, body: body.isEmpty ? null : body);
    }
    return text();
  }
  if (lower.startsWith('geo:')) {
    final parts = raw.substring(4).split(RegExp(r'[?;]')).first.split(',');
    final lat = parts.length >= 2 ? double.tryParse(parts[0]) : null, lng = parts.length >= 2 ? double.tryParse(parts[1]) : null;
    if (lat != null && lng != null && lat.abs() <= 90 && lng.abs() <= 180) {
      return ScannedCode(raw: raw, kind: CodeKind.location, format: format, latitude: lat, longitude: lng);
    }
    return text();
  }
  if (_webOnly.hasMatch(raw)) return ScannedCode(raw: raw, kind: CodeKind.link, format: format, link: raw);
  if (_wwwOnly.hasMatch(raw)) return ScannedCode(raw: raw, kind: CodeKind.link, format: format, link: 'https://$raw');
  if (_emailOnly.hasMatch(raw)) return ScannedCode(raw: raw, kind: CodeKind.email, format: format, address: raw);
  return text();
}

String _unescape(String v) => v.replaceAllMapped(RegExp(r'\\(.)', dotAll: true), (m) => m[1]!);

WifiNetwork? _parseWifi(String body) {
  final fields = <String, String>{};
  var i = 0;
  while (i < body.length) {
    final colon = body.indexOf(':', i);
    if (colon < 0) break;
    final key = body.substring(i, colon).trim().toUpperCase();
    final value = StringBuffer();
    var j = colon + 1;
    while (j < body.length && body[j] != ';') {
      if (body[j] == r'\' && j + 1 < body.length) {
        value.write(body[j + 1]);
        j += 2;
      } else {
        value.write(body[j]);
        j++;
      }
    }
    if (key.isNotEmpty) fields.putIfAbsent(key, value.toString);
    i = j + 1;
  }
  var ssid = fields['S'] ?? '';
  if (ssid.length >= 2 && ssid.startsWith('"') && ssid.endsWith('"')) ssid = ssid.substring(1, ssid.length - 1);
  if (ssid.isEmpty) return null;
  final type = (fields['T'] ?? '').toUpperCase();
  final security = switch (type) {
    'NOPASS' || '' => (fields['P'] ?? '').isEmpty ? WifiSecurity.open : WifiSecurity.wpa,
    'WEP' => WifiSecurity.wep,
    _ => WifiSecurity.wpa,
  };
  return WifiNetwork(ssid: ssid, password: fields['P'] ?? '', security: security, hidden: (fields['H'] ?? '').toLowerCase() == 'true');
}

ContactDraft _parseMeCard(String body) {
  final fields = <String, List<String>>{};
  var i = 0;
  while (i < body.length) {
    final colon = body.indexOf(':', i);
    if (colon < 0) break;
    final key = body.substring(i, colon).trim().toUpperCase();
    final value = StringBuffer();
    var j = colon + 1;
    while (j < body.length && body[j] != ';') {
      if (body[j] == r'\' && j + 1 < body.length) {
        value.write(body[j + 1]);
        j += 2;
      } else {
        value.write(body[j]);
        j++;
      }
    }
    if (key.isNotEmpty && value.isNotEmpty) fields.putIfAbsent(key, () => []).add(value.toString().trim());
    i = j + 1;
  }
  // The name is written "Last,First".
  final n = (fields['N']?.first ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final name = n.length > 1 ? '${n.sublist(1).join(' ')} ${n.first}' : n.join(' ');
  return ContactDraft(
    name: name,
    organization: fields['ORG']?.first ?? '',
    phones: fields['TEL'] ?? const [],
    emails: fields['EMAIL'] ?? const [],
    websites: fields['URL'] ?? const [],
    address: (fields['ADR']?.first ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', '),
  );
}

ContactDraft _parseVCard(String text) {
  final lines = <String>[];
  for (final line in text.split(RegExp(r'\r\n|\n|\r'))) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] += line.substring(1);
    } else {
      lines.add(line);
    }
  }
  String name = '', fn = '', org = '', title = '', address = '';
  final phones = <String>[], emails = <String>[], sites = <String>[];
  for (final line in lines) {
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    var key = line.substring(0, colon).toUpperCase();
    final semi = key.indexOf(';');
    if (semi >= 0) key = key.substring(0, semi);
    if (key.contains('.')) key = key.substring(key.indexOf('.') + 1);
    final value = line.substring(colon + 1).trim();
    if (value.isEmpty) continue;
    List<String> parts() => value.split(';').map(_unescape).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    switch (key) {
      case 'FN':
        fn = _unescape(value);
      case 'N':
        // Family;Given;Additional;Prefix;Suffix
        final raw = value.split(';').map(_unescape).map((s) => s.trim()).toList();
        name = [if (raw.length > 1) raw[1], if (raw.isNotEmpty) raw[0]].where((s) => s.isNotEmpty).join(' ');
      case 'ORG':
        org = parts().join(', ');
      case 'TITLE':
        title = _unescape(value);
      case 'TEL':
        phones.add(_unescape(value));
      case 'EMAIL':
        emails.add(_unescape(value));
      case 'URL':
        sites.add(_unescape(value));
      case 'ADR':
        address = parts().join(', ');
    }
  }
  return ContactDraft(name: fn.isNotEmpty ? fn : name, organization: org, title: title, phones: phones, emails: emails, websites: sites, address: address);
}

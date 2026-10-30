import 'dart:convert';

enum WifiSecurity {
  wpa('WPA/WPA2/WPA3', 'WPA'),
  wep('WEP', 'WEP'),
  open('None', 'nopass');

  const WifiSecurity(this.label, this.code);
  final String label;
  final String code;
}

abstract final class QrPayloads {
  /// A QR code holds about 2,900 bytes at the lowest error correction; keep well below it.
  static const maxChars = 1000;

  static String _escape(String v) => v.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');

  /// Standard `WIFI:` payload understood by the Android and iOS camera apps.
  static String wifi({required String ssid, String password = '', WifiSecurity security = WifiSecurity.wpa, bool hidden = false}) {
    final b = StringBuffer('WIFI:T:${security.code};S:${_escape(ssid)};');
    if (security != WifiSecurity.open) b.write('P:${_escape(password)};');
    if (hidden) b.write('H:true;');
    b.write(';');
    return b.toString();
  }

  /// What is wrong with the Wi-Fi details, or null when the code can be made.
  static String? wifiProblem({required String ssid, String password = '', WifiSecurity security = WifiSecurity.wpa}) {
    final name = ssid.trim();
    if (name.isEmpty) return 'Enter the network name.';
    if (utf8.encode(name).length > 32) return 'The network name is too long (32 characters at most).';
    if (security == WifiSecurity.open) return null;
    if (password.isEmpty) return 'Enter the password, or choose None for an open network.';
    final hex = RegExp(r'^[0-9A-Fa-f]+$').hasMatch(password);
    if (security == WifiSecurity.wpa) {
      final ok = (password.length >= 8 && password.length <= 63) || (password.length == 64 && hex);
      return ok ? null : 'A WPA password has 8 to 63 characters.';
    }
    final ok = password.length == 5 || password.length == 13 || ((password.length == 10 || password.length == 26) && hex);
    return ok ? null : 'A WEP password has 5 or 13 characters, or 10 or 26 hexadecimal digits.';
  }
}

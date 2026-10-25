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
}

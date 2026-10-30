import 'scanned_code.dart';

/// A code the camera or a picture gave, before it is understood.
class DetectedCode {
  const DetectedCode({required this.raw, this.format = ''});
  final String raw;
  final String format;
}

/// One entry of the list of scans kept on the phone.
class ScanRecord {
  const ScanRecord({required this.raw, required this.format, required this.at});
  final String raw;
  final String format;
  final DateTime at;

  ScannedCode get code => parseCode(raw, format: format);
}

/// Scans kept on this phone only. A code that is scanned again moves to the top instead of repeating.
abstract interface class ScanHistory {
  static const maxKept = 200;

  /// Newest first.
  Future<List<ScanRecord>> list();

  /// Keeps the scan, unless saving is switched off.
  Future<void> add(DetectedCode code, DateTime at);

  Future<void> delete(String raw);

  Future<void> clear();

  /// Whether new scans are kept. On by default.
  Future<bool> isEnabled();

  Future<void> setEnabled(bool value);
}

/// Reads the codes in a picture (a screenshot or a photo from the gallery), without a network.
abstract interface class CodeImageReader {
  /// Throws nothing: a picture without a code, or one that cannot be read, gives an empty list.
  Future<List<DetectedCode>> read(String path);
}

enum WifiJoinResult {
  /// The system accepted the network and will connect to it.
  added,

  /// This phone cannot add it directly: Wi-Fi settings were opened and the person picks the network there.
  openedSettings,

  /// The person said no.
  cancelled,
  failed,
}

abstract interface class WifiJoiner {
  Future<WifiJoinResult> join(WifiNetwork network);
}

/// Opens web addresses and other links in the app that handles them.
abstract interface class LinkOpener {
  Future<bool> open(String uri);
}

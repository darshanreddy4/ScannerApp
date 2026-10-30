import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/scan_services.dart';
import '../domain/scanned_code.dart' show WifiNetwork;

List<DetectedCode> detectedFrom(BarcodeCapture? capture) => [
  for (final b in capture?.barcodes ?? const <Barcode>[])
    if ((b.rawValue ?? '').trim().isNotEmpty) DetectedCode(raw: b.rawValue!, format: b.format.name),
];

/// Reads codes from a picture with the scanner built into the phone's Google services library; works offline.
class MlKitCodeImageReader implements CodeImageReader {
  const MlKitCodeImageReader();

  @override
  Future<List<DetectedCode>> read(String path) async {
    final controller = MobileScannerController(autoStart: false);
    try {
      return detectedFrom(await controller.analyzeImage(path));
    } on Object {
      return const [];
    } finally {
      await controller.dispose();
    }
  }
}

class SystemLinkOpener implements LinkOpener {
  const SystemLinkOpener();

  @override
  Future<bool> open(String uri) async {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return false;
    try {
      return await launchUrl(parsed, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

/// Android 11 and newer ask the person to confirm adding the network; older phones are taken to Wi-Fi settings.
class SystemWifiJoiner implements WifiJoiner {
  const SystemWifiJoiner();

  static const _channel = MethodChannel('doculoom/wifi');

  @override
  Future<WifiJoinResult> join(WifiNetwork network) async {
    if (!Platform.isAndroid) return WifiJoinResult.failed;
    try {
      final r = await _channel.invokeMethod<String>('join', {
        'ssid': network.ssid,
        'password': network.password,
        'security': network.security.code,
        'hidden': network.hidden,
      });
      return switch (r) {
        'added' => WifiJoinResult.added,
        'settings' => WifiJoinResult.openedSettings,
        'cancelled' => WifiJoinResult.cancelled,
        _ => WifiJoinResult.failed,
      };
    } on PlatformException {
      return WifiJoinResult.failed;
    } on MissingPluginException {
      return WifiJoinResult.failed;
    }
  }
}

String codeFormatLabel(String format) => switch (format) {
  'qrCode' || 'microQrCode' => 'QR code',
  'dataMatrix' => 'Data Matrix',
  'pdf417' => 'PDF417',
  'aztec' => 'Aztec',
  'ean13' => 'EAN-13',
  'ean8' => 'EAN-8',
  'upcA' => 'UPC-A',
  'upcE' => 'UPC-E',
  'code128' => 'Code 128',
  'code39' => 'Code 39',
  'code93' => 'Code 93',
  'codabar' => 'Codabar',
  'itf' || 'itf14' || 'itf2of5' || 'itf2of5WithChecksum' => 'ITF',
  _ => '',
};

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// [blocked] means the system will no longer ask, so the person has to allow it in the phone's Settings.
enum CameraAccessStatus { granted, denied, blocked }

abstract interface class CameraAccess {
  /// What is allowed right now, without asking.
  Future<CameraAccessStatus> status();

  /// Shows the system question, unless the system no longer allows asking.
  Future<CameraAccessStatus> request();

  Future<bool> openSettings();
}

class SystemCameraAccess implements CameraAccess {
  const SystemCameraAccess();

  static const _channel = MethodChannel('scanvault/camera_access');

  // iOS asks once when the camera is first opened and reports a refusal then, so only Android is checked up front.
  bool get _checksFirst => Platform.isAndroid;

  CameraAccessStatus _map(String? s) => switch (s) {
    'granted' => CameraAccessStatus.granted,
    'blocked' => CameraAccessStatus.blocked,
    _ => CameraAccessStatus.denied,
  };

  @override
  Future<CameraAccessStatus> status() async {
    if (!_checksFirst) return CameraAccessStatus.granted;
    try {
      return _map(await _channel.invokeMethod<String>('status'));
    } on PlatformException {
      return CameraAccessStatus.denied;
    }
  }

  @override
  Future<CameraAccessStatus> request() async {
    if (!_checksFirst) return CameraAccessStatus.granted;
    try {
      return _map(await _channel.invokeMethod<String>('request'));
    } on PlatformException {
      return CameraAccessStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      if (Platform.isAndroid) return await _channel.invokeMethod<bool>('openSettings') ?? false;
      return await launchUrl(Uri.parse('app-settings:'));
    } catch (_) {
      return false;
    }
  }
}

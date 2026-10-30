import 'package:flutter/services.dart';

/// Makes the screen as bright as it goes and keeps it on while a code is held to a scanner, then puts both back.
class ScreenBoost {
  const ScreenBoost();
  static const _channel = MethodChannel('doculoom/screen');

  Future<void> on() => _set(true);

  Future<void> off() => _set(false);

  // A phone or a test without the native side just keeps its own brightness.
  Future<void> _set(bool on) async {
    try {
      await _channel.invokeMethod<void>('boost', on);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}

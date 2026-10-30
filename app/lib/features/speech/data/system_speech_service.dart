import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/speech_service.dart';

/// The phone's own text-to-speech engine (Android). On other systems it reports that it is not available.
class SystemSpeechService implements SpeechService {
  SystemSpeechService() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'chunk':
          _events.add(SpeechChunk((call.arguments as num).toInt()));
        case 'done':
          _events.add(const SpeechDone());
        case 'error':
          _events.add(SpeechFailed(call.arguments as String? ?? 'The phone\'s voice stopped working.'));
      }
    });
  }

  static const _channel = MethodChannel('doculoom/speech');
  final _events = StreamController<SpeechEvent>.broadcast();

  @override
  Stream<SpeechEvent> get events => _events.stream;

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<SpeechStart> speak(List<String> chunks, {required int from, String? language, required double rate}) async {
    if (!Platform.isAndroid) return SpeechStart.unavailable;
    try {
      final r = await _channel.invokeMethod<String>('speak', {'chunks': chunks, 'from': from, 'language': language, 'rate': rate});
      return switch (r) {
        'ok' => SpeechStart.started,
        'language' => SpeechStart.languageMissing,
        _ => SpeechStart.unavailable,
      };
    } on PlatformException {
      return SpeechStart.unavailable;
    } on MissingPluginException {
      return SpeechStart.unavailable;
    }
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Already stopped.
    } on MissingPluginException {
      // No engine, nothing to stop.
    }
  }

  @override
  Future<bool> openVoiceSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

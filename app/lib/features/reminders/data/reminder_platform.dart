import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../domain/reminder_plan.dart';

/// [unsupported] where the phone cannot show these reminders (the app then only shows the box on the Documents screen).
enum ReminderAccess { granted, denied, blocked, unsupported }

abstract interface class ReminderPlatform {
  Future<ReminderAccess> status();

  /// Shows the system question when it is still allowed.
  Future<ReminderAccess> request();

  /// Replaces all scheduled reminders with [reminders].
  Future<void> schedule(List<Reminder> reminders);

  /// Shows a notification now.
  Future<void> showNow(Reminder reminder);

  Future<void> cancelAll();
  Future<bool> openSettings();

  /// One notification in about two minutes, to check that the phone shows reminders while the app is closed.
  Future<bool> scheduleTest();

  /// The phone's list of apps that may be put to sleep, or the app's own settings page.
  Future<bool> openBatterySettings();

  /// The maker's autostart or background screen, or the app's own settings page when the phone has none.
  Future<bool> openAutostartSettings();

  /// The phone maker in lower case, such as `samsung` or `xiaomi`; empty when unknown.
  Future<String> maker();
}

class AndroidReminderPlatform implements ReminderPlatform {
  const AndroidReminderPlatform();

  static const _channel = MethodChannel('doculoom/reminders');

  bool get _supported => Platform.isAndroid;

  ReminderAccess _map(String? s) => switch (s) {
    'granted' => ReminderAccess.granted,
    'blocked' => ReminderAccess.blocked,
    _ => ReminderAccess.denied,
  };

  @override
  Future<ReminderAccess> status() async {
    if (!_supported) return ReminderAccess.unsupported;
    try {
      return _map(await _channel.invokeMethod<String>('status'));
    } on PlatformException {
      return ReminderAccess.unsupported;
    } on MissingPluginException {
      return ReminderAccess.unsupported;
    }
  }

  @override
  Future<ReminderAccess> request() async {
    if (!_supported) return ReminderAccess.unsupported;
    try {
      return _map(await _channel.invokeMethod<String>('request'));
    } on PlatformException {
      return ReminderAccess.unsupported;
    } on MissingPluginException {
      return ReminderAccess.unsupported;
    }
  }

  @override
  Future<void> schedule(List<Reminder> reminders) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<int>('schedule', [for (final r in reminders) r.toMap()]);
    } on PlatformException {
      // Reminders are a convenience; the box on the Documents screen still works.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on PlatformException {
      // Nothing to cancel.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  Future<void> showNow(Reminder reminder) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('showNow', reminder.toMap());
    } on PlatformException {
      // The box on the Documents screen still shows it.
    } on MissingPluginException {
      // Same.
    }
  }

  @override
  Future<bool> openSettings() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _bool(String method) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> scheduleTest() => _bool('scheduleTest');

  @override
  Future<bool> openBatterySettings() => _bool('openBatterySettings');

  @override
  Future<bool> openAutostartSettings() => _bool('openAutostartSettings');

  @override
  Future<String> maker() async {
    if (!_supported) return '';
    try {
      return await _channel.invokeMethod<String>('maker') ?? '';
    } catch (_) {
      return '';
    }
  }
}

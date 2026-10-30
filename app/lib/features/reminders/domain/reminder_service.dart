import 'package:shared_preferences/shared_preferences.dart';

import '../../documents/domain/entities/scanned_document.dart';
import '../data/reminder_platform.dart';
import 'reminder_plan.dart';

/// Keeps the phone's scheduled reminders in step with the documents and the person's choices.
class ReminderService {
  ReminderService(this._platform, {DateTime Function()? clock, this.extras}) : _now = clock ?? DateTime.now;

  final ReminderPlatform _platform;
  final DateTime Function() _now;

  /// Other reminders to schedule with the document ones, such as saved Hijri dates. Every schedule replaces the last, so they must
  /// all be planned together.
  final Future<List<Reminder>> Function(DateTime now, bool showNames)? extras;

  List<ScannedDocument> _lastDocuments = const [];
  bool _lastEnabled = false;
  bool _lastShowNames = false;

  static const _askedKey = 'reminders_permission_asked';
  static const _shownKey = 'reminders_shown_now';

  /// Notifications shown at once for passed reminder times, per run.
  static const maxCatchUps = 5;

  Future<void> _queue = Future.value();

  Future<ReminderAccess> status() => _platform.status();
  Future<bool> openSettings() => _platform.openSettings();
  Future<bool> scheduleTest() => _platform.scheduleTest();
  Future<bool> openBatterySettings() => _platform.openBatterySettings();
  Future<bool> openAutostartSettings() => _platform.openAutostartSettings();
  Future<String> maker() => _platform.maker();

  /// Schedules reminders for [documents], or removes them all when reminders are off or not allowed.
  Future<ReminderAccess> sync(Iterable<ScannedDocument> documents, {required bool enabled, required bool showNames}) {
    // One run at a time, so two quick changes cannot both show the same notification.
    _lastDocuments = documents.toList();
    _lastEnabled = enabled;
    _lastShowNames = showNames;
    return _enqueue();
  }

  /// Plans everything again with the documents and settings of the last [sync], after a saved date was added or removed.
  Future<ReminderAccess> refresh() => _enqueue();

  Future<ReminderAccess> _enqueue() {
    final documents = _lastDocuments, enabled = _lastEnabled, showNames = _lastShowNames;
    final run = _queue.then((_) => _sync(documents, enabled: enabled, showNames: showNames));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<ReminderAccess> _sync(List<ScannedDocument> documents, {required bool enabled, required bool showNames}) async {
    final access = await _platform.status();
    final more = access == ReminderAccess.granted && extras != null ? await extras!(_now(), showNames) : const <Reminder>[];
    if ((!enabled && more.isEmpty) || access != ReminderAccess.granted) {
      if (access != ReminderAccess.unsupported) await _platform.cancelAll();
      return access;
    }
    final all = [...(enabled ? planReminders(documents, _now(), showNames: showNames) : const <Reminder>[]), ...more]..sort((a, b) => a.at.compareTo(b.at));
    await _platform.schedule(all.take(maxReminders).toList());
    if (enabled) await _showCatchUps(documents, showNames);
    return access;
  }

  /// A date set for today or the coming days has no future reminder time left, so it is shown now, once.
  Future<void> _showCatchUps(List<ScannedDocument> documents, bool showNames) async {
    final p = await SharedPreferences.getInstance();
    final done = [...?p.getStringList(_shownKey)];
    final fresh = [
      for (final c in planCatchUps(documents, _now(), showNames: showNames))
        if (!done.contains(c.key)) c,
    ].take(maxCatchUps).toList();
    if (fresh.isEmpty) return;
    for (final c in fresh) {
      await _platform.showNow(c.reminder);
      done.add(c.key);
    }
    await p.setStringList(_shownKey, done.length > 300 ? done.sublist(done.length - 300) : done);
  }

  /// True when the system question has not been shown yet and could be.
  Future<bool> shouldExplain() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_askedKey) ?? false) return false;
    return await _platform.status() == ReminderAccess.denied;
  }

  /// Shows the system question (once per install) and returns the answer.
  Future<ReminderAccess> askOnce() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_askedKey, true);
    return _platform.request();
  }
}

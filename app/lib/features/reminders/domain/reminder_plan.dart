import '../../documents/domain/entities/scanned_document.dart';
import '../../documents/domain/expiry.dart';

/// A notification to show at [at], with a stable [id] for the document and the day it is about.
class Reminder {
  const Reminder({required this.id, required this.at, required this.title, required this.text});
  final int id;
  final DateTime at;
  final String title;
  final String text;

  Map<String, Object> toMap() => {'id': id, 'at': at.millisecondsSinceEpoch, 'title': title, 'text': text};
}

/// How many days before the expiry day a reminder is shown; 0 is the day itself.
const reminderDaysBefore = [30, 7, 0];

/// The hour (local time) reminders are shown at.
const reminderHour = 9;

/// Android allows 500 alarms per app; this stays well below that.
const maxReminders = 200;

int _hash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Reminder ids stay below 2^31 so they fit an Android int.
int reminderId(String documentId, int slot) => (_hash(documentId) & 0x1FFFFFFF) * 3 + slot;

String _when(int days) => switch (days) {
  0 => 'today',
  1 => 'tomorrow',
  _ => 'in $days days',
};

/// The reminders to schedule: for every document that has an expiry date, one a month before, one a week before and
/// one on the day, each at 9:00. Times that have passed are left out. With [showNames] false the text never names the document.
List<Reminder> planReminders(Iterable<ScannedDocument> documents, DateTime now, {bool showNames = false}) {
  final out = <Reminder>[];
  for (final d in documents) {
    final expires = d.expiresAt;
    if (expires == null) continue;
    for (var slot = 0; slot < reminderDaysBefore.length; slot++) {
      final days = reminderDaysBefore[slot];
      final at = DateTime(expires.year, expires.month, expires.day - days, reminderHour);
      if (!at.isAfter(now)) continue;
      out.add(
        Reminder(
          id: reminderId(d.id, slot),
          at: at,
          title: days == 0 ? 'A document expires today' : 'A document expires ${_when(days)}',
          text: showNames ? '${d.title} expires ${_when(days)}.' : 'Open Doculoom to see which one.',
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.take(maxReminders).toList();
}

/// A reminder to show at once, with a [key] that says it was shown for this document and expiry date.
class CatchUp {
  const CatchUp(this.key, this.reminder);
  final String key;
  final Reminder reminder;
}

/// Documents that end within a month whose reminder time has already passed (an expiry set for today, or for
/// next week): one notification each, right away, worded with the real number of days left.
List<CatchUp> planCatchUps(Iterable<ScannedDocument> documents, DateTime now, {bool showNames = false}) {
  final out = <CatchUp>[];
  for (final d in documents) {
    final expires = d.expiresAt;
    if (expires == null) continue;
    final left = daysUntil(expires, now);
    if (left < 0 || left > reminderDaysBefore.first) continue;
    var slot = -1;
    for (var s = 0; s < reminderDaysBefore.length; s++) {
      final at = DateTime(expires.year, expires.month, expires.day - reminderDaysBefore[s], reminderHour);
      if (!at.isAfter(now)) slot = s;
    }
    // Before 9:00 on the day itself the normal reminder is still ahead.
    if (slot < 0 || (left == 0 && slot < reminderDaysBefore.length - 1)) continue;
    out.add(
      CatchUp(
        '${d.id}|$slot|${expires.year}-${expires.month}-${expires.day}',
        Reminder(
          id: reminderId(d.id, slot),
          at: now,
          title: left == 0 ? 'A document expires today' : 'A document expires ${_when(left)}',
          text: showNames ? '${d.title} expires ${_when(left)}.' : 'Open Doculoom to see which one.',
        ),
      ),
    );
  }
  return out;
}

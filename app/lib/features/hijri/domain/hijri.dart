import 'dart:convert';

import 'package:hijri/hijri_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../reminders/domain/reminder_plan.dart';

/// A date in the Islamic (Hijri) calendar.
class HijriDate {
  const HijriDate(this.year, this.month, this.day);
  final int year;
  final int month;
  final int day;

  @override
  bool operator ==(Object other) => other is HijriDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$day ${hijriMonthNames[month - 1]} $year';
}

/// The Umm al-Qura calendar, which Saudi Arabia uses, is tabulated from 1356 AH to 1500 AH. Outside that the dates are not known.
const hijriFirstYear = 1356;
const hijriLastYear = 1500;

final hijriFirstDay = DateTime(1937, 3, 14);
final hijriLastDay = DateTime(2077, 11, 16);

const hijriMonthNames = [
  'Muharram',
  'Safar',
  'Rabi\u2019 al-Awwal',
  'Rabi\u2019 al-Thani',
  'Jumada al-Awwal',
  'Jumada al-Thani',
  'Rajab',
  'Sha\u2019ban',
  'Ramadan',
  'Shawwal',
  'Dhu al-Qi\u2019dah',
  'Dhu al-Hijjah',
];

/// The Hijri date of a day, or null when it is outside the years the table covers.
HijriDate? toHijri(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  if (d.isBefore(hijriFirstDay) || d.isAfter(hijriLastDay)) return null;
  try {
    final h = HijriCalendar.fromDate(d);
    return HijriDate(h.hYear, h.hMonth, h.hDay);
  } on Object {
    return null;
  }
}

/// How many days the month has, 29 or 30, or null outside the table.
int? hijriMonthLength(int year, int month) {
  if (year < hijriFirstYear || year > hijriLastYear || month < 1 || month > 12) return null;
  try {
    return HijriCalendar().getDaysInMonth(year, month);
  } on Object {
    return null;
  }
}

/// The Gregorian day of a Hijri date, or null when the date does not exist or is outside the table.
DateTime? toGregorian(int year, int month, int day) {
  final length = hijriMonthLength(year, month);
  if (length == null || day < 1 || day > length) return null;
  try {
    final g = HijriCalendar().hijriToGregorian(year, month, day);
    return DateTime(g.year, g.month, g.day);
  } on Object {
    return null;
  }
}

/// The first day of a Hijri month, and what weekday it falls on (1 Monday to 7 Sunday).
DateTime? hijriMonthStart(int year, int month) => toGregorian(year, month, 1);

/// An occasion kept each year: the name, and the day and month in the Hijri calendar.
class HijriOccasion {
  const HijriOccasion(this.key, this.name, this.month, this.day);
  final String key;
  final String name;
  final int month;
  final int day;
}

/// Dates that Muslims mark. The day is the one in the calculated calendar; where the new moon is sighted, the start of a month can be a
/// day later, and a few of these (Laylat al-Qadr, Mawlid) are marked on different nights by different communities.
const hijriOccasions = <HijriOccasion>[
  HijriOccasion('newyear', 'Islamic New Year', 1, 1),
  HijriOccasion('ashura', 'Day of Ashura', 1, 10),
  HijriOccasion('mawlid', 'Mawlid al-Nabi', 3, 12),
  HijriOccasion('isra', 'Isra and Mi\u2019raj', 7, 27),
  HijriOccasion('shaban', 'Mid-Sha\u2019ban', 8, 15),
  HijriOccasion('ramadan', 'First day of Ramadan', 9, 1),
  HijriOccasion('qadr', 'Laylat al-Qadr (27th night)', 9, 27),
  HijriOccasion('fitr', 'Eid al-Fitr', 10, 1),
  HijriOccasion('arafah', 'Day of Arafah', 12, 9),
  HijriOccasion('adha', 'Eid al-Adha', 12, 10),
];

HijriOccasion? hijriOccasionOf(String key) {
  for (final o in hijriOccasions) {
    if (o.key == key) return o;
  }
  return null;
}

/// How many days before the day a reminder is shown.
const hijriDaysBefore = [0, 1, 3, 7];

/// A date that comes back every Hijri year, with a reminder some days before it.
class HijriReminder {
  const HijriReminder({required this.id, required this.title, required this.month, required this.day, this.daysBefore = 1, this.occasion});
  final String id;
  final String title;
  final int month;
  final int day;
  final int daysBefore;

  /// The key of a ready-made occasion; null for a date the person chose.
  final String? occasion;

  Map<String, Object?> toJson() => {'id': id, 'title': title, 'month': month, 'day': day, 'daysBefore': daysBefore, 'occasion': occasion};

  static HijriReminder? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'], month = j['month'], day = j['day'];
    if (id is! String || title is! String || month is! int || day is! int || month < 1 || month > 12 || day < 1 || day > 30) return null;
    final before = j['daysBefore'];
    return HijriReminder(
      id: id,
      title: title,
      month: month,
      day: day,
      daysBefore: before is int && hijriDaysBefore.contains(before) ? before : 1,
      occasion: j['occasion'] is String ? j['occasion'] as String : null,
    );
  }
}

/// The days this date falls on from [now] on, in the Gregorian calendar, soonest first; at most [count]. A date of the 30th is
/// kept to the last day of a month that has only 29.
List<DateTime> hijriOccurrences(int month, int day, DateTime now, {int count = 3}) {
  final today = DateTime(now.year, now.month, now.day);
  final here = toHijri(today);
  if (here == null) return const [];
  final out = <DateTime>[];
  for (var y = here.year; y <= hijriLastYear && out.length < count; y++) {
    final length = hijriMonthLength(y, month);
    if (length == null) continue;
    final g = toGregorian(y, month, day > length ? length : day);
    if (g != null && !g.isBefore(today)) out.add(g);
  }
  return out;
}

int _hash(String s) {
  var h = 0x811C9DC5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// An id below 2^31 for the occurrence [slot] (0 to 7) of a reminder.
int hijriReminderId(String id, int slot) => (_hash('hijri|$id') & 0x0FFFFFFF) * 8 + slot;

String _when(int days) => switch (days) {
  0 => 'today',
  1 => 'tomorrow',
  _ => 'in $days days',
};

const maxHijriReminders = 40;

/// The notifications for the next occurrences of each date, at the usual hour. The name of a date the person made up is left out of
/// the notification unless [showNames] is on; a ready-made occasion is always named.
List<Reminder> planHijriReminders(Iterable<HijriReminder> reminders, DateTime now, {bool showNames = false}) {
  final out = <Reminder>[];
  for (final r in reminders) {
    final named = r.occasion != null || showNames;
    final name = r.occasion != null ? (hijriOccasionOf(r.occasion!)?.name ?? r.title) : r.title;
    final days = hijriOccurrences(r.month, r.day, now);
    for (var slot = 0; slot < days.length && slot < 4; slot++) {
      final d = days[slot];
      final at = DateTime(d.year, d.month, d.day - r.daysBefore, reminderHour);
      if (!at.isAfter(now)) continue;
      final h = HijriDate(toHijri(d)?.year ?? 0, r.month, r.day);
      out.add(
        Reminder(
          id: hijriReminderId(r.id, slot),
          at: at,
          title: named ? '$name is ${_when(r.daysBefore)}' : 'A date you saved is ${_when(r.daysBefore)}',
          text: named ? '${h.day} ${hijriMonthNames[h.month - 1]} ${h.year} AH' : 'Open Doculoom to see which one.',
        ),
      );
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// The saved dates, kept on the phone only.
class HijriReminderStore {
  const HijriReminderStore();

  static const key = 'hijri_reminders';

  Future<List<HijriReminder>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return const [];
    try {
      return [...(jsonDecode(raw) as List).map(HijriReminder.fromJson).nonNulls];
    } on Object {
      return const [];
    }
  }

  Future<void> save(List<HijriReminder> all) async => (await SharedPreferences.getInstance()).setString(key, jsonEncode([for (final r in all) r.toJson()]));

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(key);
}

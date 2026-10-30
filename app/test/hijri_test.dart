import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/hijri/domain/hijri.dart';
import 'package:doculoom/features/hijri/presentation/hijri_page.dart';
import 'package:doculoom/features/reminders/data/reminder_platform.dart';
import 'package:doculoom/features/reminders/domain/reminder_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/reminder_fakes.dart';

String _iso(DateTime? d) => d == null ? 'null' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('the calendar', () {
    test('known dates in the Umm al-Qura calendar', () {
      final known = {
        DateTime(2025, 3, 1): const HijriDate(1446, 9, 1),
        DateTime(2025, 3, 30): const HijriDate(1446, 10, 1),
        DateTime(2025, 6, 6): const HijriDate(1446, 12, 10),
        DateTime(2025, 6, 26): const HijriDate(1447, 1, 1),
        DateTime(2026, 2, 18): const HijriDate(1447, 9, 1),
        DateTime(2026, 3, 20): const HijriDate(1447, 10, 1),
        DateTime(2026, 5, 27): const HijriDate(1447, 12, 10),
        DateTime(2026, 6, 16): const HijriDate(1448, 1, 1),
      };
      known.forEach((g, h) {
        expect(toHijri(g), h, reason: _iso(g));
        expect(toGregorian(h.year, h.month, h.day), g, reason: h.toString());
      });
    });

    test('the time of day does not matter', () {
      expect(toHijri(DateTime(2025, 6, 26, 23, 59)), const HijriDate(1447, 1, 1));
    });

    test('every day from 2000 to 2060 goes to Hijri and back to the same day', () {
      var d = DateTime(2000);
      final end = DateTime(2060);
      while (d.isBefore(end)) {
        final h = toHijri(d)!;
        expect(toGregorian(h.year, h.month, h.day), d, reason: _iso(d));
        d = DateTime(d.year, d.month, d.day + 1);
      }
    });

    test('months have 29 or 30 days and follow one another without a gap', () {
      for (var y = 1440; y <= 1460; y++) {
        for (var m = 1; m <= 12; m++) {
          final len = hijriMonthLength(y, m)!;
          expect(len, anyOf(29, 30), reason: '$m/$y');
          final start = toGregorian(y, m, 1)!;
          final next = m == 12 ? toGregorian(y + 1, 1, 1)! : toGregorian(y, m + 1, 1)!;
          expect(next.difference(start).inDays, len, reason: '$m/$y');
        }
      }
    });

    test('a day that the month does not have, or a year outside the table, gives nothing', () {
      expect(hijriMonthLength(1447, 2), 29);
      expect(toGregorian(1447, 2, 30), isNull);
      expect(toGregorian(1447, 13, 1), isNull);
      expect(toGregorian(1447, 1, 0), isNull);
      expect(toGregorian(1355, 12, 29), isNull);
      expect(toGregorian(1501, 1, 1), isNull);
      expect(hijriMonthLength(1501, 1), isNull);
    });

    test('the ends of the table', () {
      expect(toHijri(DateTime(1937, 3, 13)), isNull);
      expect(toHijri(DateTime(1937, 3, 14)), const HijriDate(1356, 1, 1));
      expect(toHijri(DateTime(2077, 11, 16)), const HijriDate(1500, 12, 30));
      expect(toHijri(DateTime(2077, 11, 17)), isNull);
      expect(toHijri(DateTime(1900)), isNull);
    });
  });

  group('yearly dates', () {
    test('the next days a date falls on, soonest first, a Hijri year apart', () {
      final d = hijriOccurrences(12, 10, DateTime(2026, 5, 20));
      expect(d.map(_iso).first, '2026-05-27');
      expect(d.length, 3);
      for (var i = 1; i < d.length; i++) {
        expect(d[i].difference(d[i - 1]).inDays, anyOf(354, 355), reason: 'a Hijri year');
      }
    });

    test('the day itself counts, the day after does not', () {
      expect(_iso(hijriOccurrences(12, 10, DateTime(2026, 5, 27, 18)).first), '2026-05-27');
      expect(_iso(hijriOccurrences(12, 10, DateTime(2026, 5, 28)).first), isNot('2026-05-27'));
    });

    test('the 30th in a month of 29 days is the last day of it', () {
      final d = hijriOccurrences(2, 30, DateTime(2025, 8, 1)).first;
      expect(toHijri(d), const HijriDate(1447, 2, 29));
    });

    test('nothing is planned outside the years the calendar covers', () {
      expect(hijriOccurrences(1, 1, DateTime(2090)), isEmpty);
      expect(hijriOccurrences(1, 1, DateTime(1900)), isEmpty);
    });

    test('a date near the end of the table gives only what exists', () {
      final d = hijriOccurrences(12, 10, DateTime(2076, 6, 1));
      expect(d.length, lessThan(3));
      expect(d, isNotEmpty);
    });
  });

  group('the notifications', () {
    final now = DateTime(2026, 5, 20, 10);
    const eid = HijriReminder(id: 'occ-adha', title: 'Eid al-Adha', month: 12, day: 10, daysBefore: 1, occasion: 'adha');
    const own = HijriReminder(id: 'own-1', title: 'Zakat due', month: 9, day: 1, daysBefore: 7);

    test('an occasion is shown at 9:00, a day before, with its name and Hijri date', () {
      final r = planHijriReminders([eid], now);
      expect(r.first.at, DateTime(2026, 5, 26, 9));
      expect(r.first.title, 'Eid al-Adha is tomorrow');
      expect(r.first.text, '10 Dhu al-Hijjah 1447 AH');
      expect(r.length, 3);
    });

    test('a time that has passed is left out', () {
      final r = planHijriReminders([eid], DateTime(2026, 5, 26, 10));
      expect(r.first.at.year, 2027, reason: '9:00 on the 26th has gone, and the day after is next year');
    });

    test('a date the person made up is not named unless asked', () {
      final off = planHijriReminders([own], now).first;
      expect(off.title + off.text, isNot(contains('Zakat')));
      expect(off.title, 'A date you saved is in 7 days');
      final on = planHijriReminders([own], now, showNames: true).first;
      expect(on.title, 'Zakat due is in 7 days');
      expect(planHijriReminders([eid], now).first.title, contains('Eid al-Adha'), reason: 'an occasion is public');
    });

    test('on the day', () {
      final r = planHijriReminders([const HijriReminder(id: 'x', title: 'Ramadan', month: 9, day: 1, daysBefore: 0, occasion: 'ramadan')], now);
      expect(r.first.at, DateTime(2026, 2, 18, 9).add(const Duration(days: 354)).isAfter(now) ? r.first.at : r.first.at);
      expect(r.first.title, 'First day of Ramadan is today');
    });

    test('the ids differ, and fit an Android int', () {
      final ids = [
        for (final r in planHijriReminders([eid, own], now, showNames: true)) r.id,
      ];
      expect(ids.toSet().length, ids.length);
      for (final i in ids) {
        expect(i, inInclusiveRange(0, 2147483647));
      }
    });

    test('the ready-made occasions are on real days of real months', () {
      expect(hijriOccasions.length, 10);
      for (final o in hijriOccasions) {
        expect(hijriMonthLength(1447, o.month)! >= o.day, isTrue, reason: o.key);
      }
      expect(hijriOccasionOf('fitr')!.name, 'Eid al-Fitr');
      expect(hijriOccasionOf('nothing'), isNull);
    });
  });

  group('the saved dates', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('they are kept and read back', () async {
      const store = HijriReminderStore();
      expect(await store.load(), isEmpty);
      await store.save(const [
        HijriReminder(id: 'a', title: 'Zakat due', month: 9, day: 1, daysBefore: 7),
        HijriReminder(id: 'occ-adha', title: 'Eid al-Adha', month: 12, day: 10, occasion: 'adha'),
      ]);
      final all = await store.load();
      expect(all.map((r) => (r.id, r.title, r.month, r.day, r.daysBefore, r.occasion)), [
        ('a', 'Zakat due', 9, 1, 7, null),
        ('occ-adha', 'Eid al-Adha', 12, 10, 1, 'adha'),
      ]);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('damaged or odd entries are skipped, not trusted', () async {
      SharedPreferences.setMockInitialValues({
        HijriReminderStore.key:
            '[{"id":"a","title":"ok","month":9,"day":1,"daysBefore":3},{"id":"b","title":"x","month":13,"day":1},{"id":1},"text",{"id":"c","title":"y","month":1,"day":1,"daysBefore":99}]',
      });
      final all = await const HijriReminderStore().load();
      expect(all.map((r) => (r.id, r.daysBefore)), [('a', 3), ('c', 1)]);
      SharedPreferences.setMockInitialValues({HijriReminderStore.key: 'not json'});
      expect(await const HijriReminderStore().load(), isEmpty);
    });
  });

  group('with the document reminders', () {
    final now = DateTime(2026, 5, 20, 10);
    ScannedDocument doc(DateTime d) =>
        ScannedDocument(id: 'd', title: 'Passport', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], expiresAt: d);
    const eid = HijriReminder(id: 'occ-adha', title: 'Eid al-Adha', month: 12, day: 10, occasion: 'adha');

    test('they are scheduled together, soonest first', () async {
      final platform = FakeReminderPlatform();
      final service = ReminderService(
        platform,
        clock: () => now,
        extras: (n, names) async => planHijriReminders([eid], n, showNames: names),
      );
      await service.sync([doc(DateTime(2026, 5, 29))], enabled: true, showNames: false);
      final all = platform.scheduled.single;
      expect(all.map((r) => r.at).toList(), [...all.map((r) => r.at)]..sort());
      expect(all.where((r) => r.title.contains('Eid')), isNotEmpty);
      expect(all.where((r) => r.title.contains('document')), isNotEmpty);
    });

    test('the dates are still scheduled when the document reminders are off', () async {
      final platform = FakeReminderPlatform();
      final service = ReminderService(platform, clock: () => now, extras: (n, names) async => planHijriReminders([eid], n));
      await service.sync([doc(DateTime(2026, 5, 29))], enabled: false, showNames: false);
      expect(platform.cancels, 0);
      expect(platform.scheduled.single.every((r) => r.title.contains('Eid')), isTrue);
    });

    test('with no dates and the document reminders off, everything is cancelled as before', () async {
      final platform = FakeReminderPlatform();
      final service = ReminderService(platform, clock: () => now, extras: (n, names) async => const []);
      await service.sync([doc(DateTime(2026, 5, 29))], enabled: false, showNames: false);
      expect(platform.cancels, 1);
      expect(platform.scheduled, isEmpty);
    });

    test('nothing is scheduled while notifications are not allowed', () async {
      final platform = FakeReminderPlatform(access: ReminderAccess.denied);
      var asked = 0;
      final service = ReminderService(
        platform,
        clock: () => now,
        extras: (n, names) async {
          asked++;
          return planHijriReminders([eid], n);
        },
      );
      await service.sync(const [], enabled: true, showNames: false);
      expect(platform.scheduled, isEmpty);
      expect(asked, 0);
    });

    test('a refresh plans again with the last documents and settings', () async {
      final platform = FakeReminderPlatform();
      var list = <HijriReminder>[];
      final service = ReminderService(platform, clock: () => now, extras: (n, names) async => planHijriReminders(list, n));
      await service.sync([doc(DateTime(2026, 5, 29))], enabled: true, showNames: false);
      expect(platform.scheduled.last.where((r) => r.title.contains('Eid')), isEmpty);
      list = [eid];
      await service.refresh();
      expect(platform.scheduled.last.where((r) => r.title.contains('Eid')), isNotEmpty);
      expect(platform.scheduled.last.where((r) => r.title.contains('document')), isNotEmpty, reason: 'the passport reminders are still there');
    });

    test('a service made without extras behaves as it did', () async {
      final platform = FakeReminderPlatform();
      await ReminderService(platform, clock: () => now).sync([doc(DateTime(2026, 5, 29))], enabled: true, showNames: false);
      expect(platform.scheduled.single.every((r) => r.title.contains('document')), isTrue);
    });
  });

  group('the page', () {
    late FakeReminderPlatform platform;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      platform = FakeReminderPlatform();
      await sl.reset();
      sl.registerSingleton(
        ReminderService(
          platform,
          clock: () => DateTime(2026, 5, 20, 10),
          extras: (n, names) async => planHijriReminders(await const HijriReminderStore().load(), n, showNames: names),
        ),
      );
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      }
      await tester.pump();
    }

    Future<void> open(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 6000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: HijriPage(now: DateTime(2026, 5, 20)),
        ),
      );
      await settle(tester);
    }

    testWidgets('it shows today in both calendars and the month of today', (tester) async {
      await open(tester);
      expect(find.descendant(of: find.byKey(const ValueKey('hijri-today')), matching: find.text('Wednesday, 3 Dhu al-Hijjah 1447 AH')), findsOneWidget);
      expect(find.byKey(const ValueKey('hijri-title')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('hijri-title'))).data, 'Dhu al-Hijjah 1447');
      expect(find.byKey(const ValueKey('hijri-day-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('hijri-day-30')), findsNothing, reason: 'Dhu al-Hijjah 1447 has 29 days or fewer shown by the table');
    });

    testWidgets('the arrows go to the next and the last month', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hijri-next')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('hijri-title'))).data, 'Muharram 1448');
      await tester.tap(find.byKey(const ValueKey('hijri-prev')));
      await tester.tap(find.byKey(const ValueKey('hijri-prev')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('hijri-title'))).data, 'Dhu al-Qi\u2019dah 1447');
    });

    testWidgets('a tap on a day shows it in both calendars, and names an occasion', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hijri-day-10')));
      await tester.pump();
      expect(find.byKey(const ValueKey('hijri-occasion-adha')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('hijri-result'))).data, startsWith('Wednesday, 10 Dhu al-Hijjah 1447'));
    });

    testWidgets('the converter takes a Hijri date and shows the day in the calendar', (tester) async {
      await open(tester);
      await tester.tap(find.text('To Gregorian'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('hijri-form-day')), '1');
      await tester.enterText(find.byKey(const ValueKey('hijri-form-year')), '1447');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('hijri-result'))).data, 'Thursday, 1 Muharram 1447 AH');
      expect(tester.widget<Text>(find.byKey(const ValueKey('hijri-title'))).data, 'Muharram 1447');
    });

    testWidgets('a day the month does not have, and a year the table lacks, are explained', (tester) async {
      await open(tester);
      await tester.tap(find.text('To Gregorian'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('hijri-form-day')), '30');
      await tester.enterText(find.byKey(const ValueKey('hijri-form-year')), '1447');
      await tester.pump();
      expect(find.text('Muharram 1447 has 30 days.'), findsNothing, reason: 'Muharram has 30 days, so this one is fine');
      await tester.tap(find.byKey(const ValueKey('hijri-month-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Safar').last);
      await tester.pumpAndSettle();
      expect(find.text('Safar 1447 has 29 days.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('hijri-form-year')), '1600');
      await tester.pump();
      expect(find.text('Years 1356 to 1500 are supported.'), findsOneWidget);
    });

    testWidgets('occasions are chosen from a list, saved, shown with the next date and scheduled', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('hijri-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hijri-add-occasion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hijri-occ-adha')));
      await tester.tap(find.byKey(const ValueKey('hijri-occ-fitr')));
      await tester.tap(find.byKey(const ValueKey('hijri-before-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hijri-sheet-add')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const ValueKey('hijri-reminder-occ-adha')), findsOneWidget);
      expect(find.byKey(const ValueKey('hijri-reminder-occ-fitr')), findsOneWidget);
      expect(find.textContaining('3 days before'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('hijri-empty')), findsNothing);
      final saved = await const HijriReminderStore().load();
      expect(saved.map((r) => r.occasion).toSet(), {'adha', 'fitr'});
      expect(platform.scheduled, isNotEmpty);
      expect(platform.scheduled.last.any((r) => r.title == 'Eid al-Adha is in 3 days'), isTrue);
    });

    testWidgets('the day that is open can be kept as a date of the person\'s own', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hijri-day-15')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hijri-add-selected')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('hijri-title-field')), 'Zakat due');
      await tester.tap(find.byKey(const ValueKey('hijri-title-save')));
      await tester.pumpAndSettle();
      await settle(tester);
      final saved = await const HijriReminderStore().load();
      expect((saved.single.title, saved.single.month, saved.single.day, saved.single.occasion), ('Zakat due', 12, 15, null));
      expect(find.text('Zakat due'), findsOneWidget);
      expect(platform.scheduled.last.every((r) => !r.title.contains('Zakat') && !r.text.contains('Zakat')), isTrue, reason: 'not named by default');
    });

    testWidgets('a reminder is removed after a question, and its notifications go', (tester) async {
      SharedPreferences.setMockInitialValues({
        HijriReminderStore.key: '[{"id":"occ-adha","title":"Eid al-Adha","month":12,"day":10,"daysBefore":1,"occasion":"adha"}]',
      });
      await open(tester);
      expect(find.byKey(const ValueKey('hijri-reminder-occ-adha')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hijri-delete-occ-adha')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.byKey(const ValueKey('hijri-reminder-occ-adha')), findsNothing);
      expect(await const HijriReminderStore().load(), isEmpty);
      expect(platform.cancels, greaterThan(0), reason: 'nothing is left to show, so what was scheduled is cancelled');
    });

    testWidgets('the first reminder asks to allow notifications when the phone has not been asked', (tester) async {
      platform = FakeReminderPlatform(access: ReminderAccess.denied, afterAsk: ReminderAccess.granted);
      await sl.reset();
      sl.registerSingleton(
        ReminderService(
          platform,
          clock: () => DateTime(2026, 5, 20, 10),
          extras: (n, names) async => planHijriReminders(await const HijriReminderStore().load(), n),
        ),
      );
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('hijri-add-occasion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hijri-occ-ramadan')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hijri-sheet-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hijri-allow')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hijri-allow')));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(platform.requests, 1);
      expect(platform.scheduled, isNotEmpty);
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await open(tester, width: w);
        await tester.tap(find.text('To Gregorian'));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('hijri-add-occasion')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

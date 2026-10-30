import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/reminders/data/reminder_platform.dart';
import 'package:doculoom/features/reminders/domain/reminder_plan.dart';
import 'package:doculoom/features/reminders/domain/reminder_service.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/reminder_fakes.dart';

ScannedDocument _doc(String id, String title, DateTime? expires) =>
    ScannedDocument(id: id, title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], expiresAt: expires);

void main() {
  final now = DateTime(2026, 10, 25, 14, 30);

  group('planning', () {
    test('a month before, a week before and on the day, each at 9:00', () {
      final r = planReminders([_doc('a', 'Passport', DateTime(2027, 3, 10, 12))], now);
      expect(r.map((e) => e.at), [DateTime(2027, 2, 8, 9), DateTime(2027, 3, 3, 9), DateTime(2027, 3, 10, 9)]);
      expect(r.map((e) => e.title), ['A document expires in 30 days', 'A document expires in 7 days', 'A document expires today']);
    });

    test('the month arithmetic crosses month and year ends correctly', () {
      final r = planReminders([_doc('a', 'x', DateTime(2027, 1, 5, 12))], now);
      expect(r.first.at, DateTime(2026, 12, 6, 9));
      expect(r[1].at, DateTime(2026, 12, 29, 9));
    });

    test('times that have passed are left out', () {
      final soon = planReminders([_doc('a', 'x', DateTime(2026, 11, 2, 12))], now);
      expect(soon.map((e) => e.at), [DateTime(2026, 10, 26, 9), DateTime(2026, 11, 2, 9)], reason: 'the 30 day slot is in the past, the week slot is tomorrow');
      expect(planReminders([_doc('a', 'x', DateTime(2026, 10, 25, 12))], now), isEmpty, reason: '9:00 today has passed');
      expect(planReminders([_doc('a', 'x', DateTime(2026, 10, 25, 12))], DateTime(2026, 10, 25, 8)).single.title, 'A document expires today');
      expect(planReminders([_doc('a', 'x', DateTime(2020, 1, 1))], now), isEmpty);
    });

    test('documents without a date give nothing', () {
      expect(planReminders([_doc('a', 'x', null)], now), isEmpty);
      expect(planReminders(const [], now), isEmpty);
    });

    test('names appear only when asked for', () {
      final off = planReminders([_doc('a', 'Passport of Anna', DateTime(2027, 3, 10))], now).first;
      expect(off.title + off.text, isNot(contains('Passport')));
      final on = planReminders([_doc('a', 'Passport of Anna', DateTime(2027, 3, 10))], now, showNames: true);
      expect(on.first.text, 'Passport of Anna expires in 30 days.');
      expect(on.last.text, 'Passport of Anna expires today.');
    });

    test('ids are stable, different per document and day, and fit an Android int', () {
      final a = planReminders([_doc('doc-a', 'x', DateTime(2027, 3, 10))], now);
      final again = planReminders([_doc('doc-a', 'x', DateTime(2027, 5, 1))], now);
      expect(a.map((e) => e.id).toSet().length, 3);
      expect(again.map((e) => e.id), a.map((e) => e.id), reason: 'moving the date replaces the old reminders');
      final ids = <int>{};
      for (var i = 0; i < 500; i++) {
        for (final r in planReminders([_doc('document-$i', 'x', DateTime(2028, 1, 1))], now)) {
          expect(r.id, inInclusiveRange(0, 2147483647));
          ids.add(r.id);
        }
      }
      expect(ids.length, greaterThan(1480), reason: 'hardly any collisions');
    });

    test('the nearest reminders win when there are more than the phone should hold', () {
      final docs = [for (var i = 0; i < 150; i++) _doc('d$i', 't', DateTime(2027, 1, 1).add(Duration(days: i)))];
      final r = planReminders(docs, now);
      expect(r.length, maxReminders);
      expect(r.first.at.isBefore(r.last.at) || r.first.at == r.last.at, isTrue);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].at.isBefore(r[i - 1].at), isFalse, reason: 'sorted');
      }
    });

    test('the map sent to the phone holds exactly what it needs', () {
      final m = planReminders([_doc('a', 'x', DateTime(2027, 3, 10))], now).first.toMap();
      expect(m.keys.toSet(), {'id', 'at', 'title', 'text'});
      expect(m['at'], DateTime(2027, 2, 8, 9).millisecondsSinceEpoch);
    });
  });

  group('service', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    final doc = _doc('a', 'Passport', DateTime(2027, 3, 10));

    test('with permission and reminders on, the reminders are scheduled', () async {
      final platform = FakeReminderPlatform();
      final access = await ReminderService(platform, clock: () => now).sync([doc], enabled: true, showNames: false);
      expect(access, ReminderAccess.granted);
      expect(platform.scheduled.single.length, 3);
      expect(platform.cancels, 0);
    });

    test('switching reminders off removes every scheduled one', () async {
      final platform = FakeReminderPlatform();
      await ReminderService(platform, clock: () => now).sync([doc], enabled: false, showNames: false);
      expect(platform.scheduled, isEmpty);
      expect(platform.cancels, 1);
    });

    test('without permission nothing is scheduled and old ones are removed', () async {
      for (final a in [ReminderAccess.denied, ReminderAccess.blocked]) {
        final platform = FakeReminderPlatform(access: a);
        await ReminderService(platform, clock: () => now).sync([doc], enabled: true, showNames: false);
        expect(platform.scheduled, isEmpty, reason: a.name);
        expect(platform.cancels, 1, reason: a.name);
      }
    });

    test('where reminders are not possible nothing is called at all', () async {
      final platform = FakeReminderPlatform(access: ReminderAccess.unsupported);
      final access = await ReminderService(platform, clock: () => now).sync([doc], enabled: true, showNames: false);
      expect(access, ReminderAccess.unsupported);
      expect(platform.scheduled, isEmpty);
      expect(platform.cancels, 0);
    });

    test('deleting the last document with a date clears the schedule', () async {
      final platform = FakeReminderPlatform();
      await ReminderService(platform, clock: () => now).sync(const [], enabled: true, showNames: false);
      expect(platform.scheduled.single, isEmpty);
    });

    test('the question is explained only once, and only when the system can still ask', () async {
      final platform = FakeReminderPlatform(access: ReminderAccess.denied, afterAsk: ReminderAccess.blocked);
      final service = ReminderService(platform);
      expect(await service.shouldExplain(), isTrue);
      expect(await service.askOnce(), ReminderAccess.blocked);
      expect(platform.requests, 1);
      expect(await service.shouldExplain(), isFalse, reason: 'already asked');

      SharedPreferences.setMockInitialValues({});
      expect(await ReminderService(FakeReminderPlatform(access: ReminderAccess.granted)).shouldExplain(), isFalse, reason: 'nothing to ask');
      expect(await ReminderService(FakeReminderPlatform(access: ReminderAccess.blocked)).shouldExplain(), isFalse, reason: 'only Settings can help');
      expect(await ReminderService(FakeReminderPlatform(access: ReminderAccess.unsupported)).shouldExplain(), isFalse);
    });
  });

  group('shown at once when the reminder time has already passed', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a date set for today is announced now, in the hours after 9:00', () {
      final c = planCatchUps([_doc('a', 'Passport', DateTime(2026, 10, 25, 12))], now);
      expect(c.single.reminder.title, 'A document expires today');
      expect(c.single.reminder.text, 'Open Doculoom to see which one.');
    });

    test('the document name appears only when the person allowed it', () {
      expect(planCatchUps([_doc('a', 'Passport', DateTime(2026, 10, 25, 12))], now, showNames: true).single.reminder.text, 'Passport expires today.');
    });

    test('a date a few days away says the real number of days, not 7', () {
      final c = planCatchUps([_doc('a', 'x', DateTime(2026, 10, 28, 12))], now);
      expect(c.single.reminder.title, 'A document expires in 3 days');
      expect(planCatchUps([_doc('a', 'x', DateTime(2026, 10, 26, 12))], now).single.reminder.title, 'A document expires tomorrow');
    });

    test('before 9:00 on the day the normal reminder is still ahead, so nothing is shown now', () {
      expect(planCatchUps([_doc('a', 'x', DateTime(2026, 10, 25, 12))], DateTime(2026, 10, 25, 8)), isEmpty);
    });

    test('far away, expired or undated documents are not announced', () {
      expect(planCatchUps([_doc('a', 'x', DateTime(2027, 3, 10))], now), isEmpty, reason: 'its first reminder is months ahead');
      expect(planCatchUps([_doc('a', 'x', DateTime(2026, 10, 24))], now), isEmpty, reason: 'already over: the Documents screen shows it');
      expect(planCatchUps([_doc('a', 'x', null)], now), isEmpty);
    });

    test('the service shows it once, however many times the library is reloaded', () async {
      final platform = FakeReminderPlatform();
      final service = ReminderService(platform, clock: () => now);
      final docs = [_doc('a', 'Passport', DateTime(2026, 10, 25, 12))];
      await Future.wait([service.sync(docs, enabled: true, showNames: false), service.sync(docs, enabled: true, showNames: false)]);
      await service.sync(docs, enabled: true, showNames: false);
      expect(platform.shown.length, 1);
      expect(platform.shown.single.title, 'A document expires today');
    });

    test('a new date for the same document is announced again', () async {
      final platform = FakeReminderPlatform();
      final service = ReminderService(platform, clock: () => now);
      await service.sync([_doc('a', 'x', DateTime(2026, 10, 25, 12))], enabled: true, showNames: false);
      await service.sync([_doc('a', 'x', DateTime(2026, 10, 26, 12))], enabled: true, showNames: false);
      expect(platform.shown.length, 2);
    });

    test('nothing is shown when reminders are off or not allowed', () async {
      for (final a in [ReminderAccess.denied, ReminderAccess.blocked, ReminderAccess.unsupported]) {
        final platform = FakeReminderPlatform(access: a);
        await ReminderService(platform, clock: () => now).sync([_doc('a', 'x', DateTime(2026, 10, 25, 12))], enabled: true, showNames: false);
        expect(platform.shown, isEmpty, reason: a.name);
      }
      final off = FakeReminderPlatform();
      await ReminderService(off, clock: () => now).sync([_doc('a', 'x', DateTime(2026, 10, 25, 12))], enabled: false, showNames: false);
      expect(off.shown, isEmpty);
    });

    test('allowing notifications later shows what was missed, and it is not shown before', () async {
      final platform = FakeReminderPlatform(access: ReminderAccess.denied, afterAsk: ReminderAccess.granted);
      final service = ReminderService(platform, clock: () => now);
      final docs = [_doc('a', 'x', DateTime(2026, 10, 25, 12))];
      await service.sync(docs, enabled: true, showNames: false);
      expect(platform.shown, isEmpty);
      await service.askOnce();
      await service.sync(docs, enabled: true, showNames: false);
      expect(platform.shown.length, 1);
    });

    test('at most five are shown in one go, the rest on the next run', () async {
      final platform = FakeReminderPlatform();
      final service = ReminderService(platform, clock: () => now);
      final docs = [for (var i = 0; i < 8; i++) _doc('d$i', 'x', DateTime(2026, 10, 25, 12))];
      await service.sync(docs, enabled: true, showNames: false);
      expect(platform.shown.length, 5);
      await service.sync(docs, enabled: true, showNames: false);
      expect(platform.shown.length, 8);
    });
  });

  group('settings', () {
    test('reminders are on and names off by default, and both are saved', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = SettingsRepositoryImpl();
      final first = await repo.load();
      expect(first.expiryReminders, isTrue);
      expect(first.reminderShowNames, isFalse);
      await repo.save(first.copyWith(expiryReminders: false, reminderShowNames: true));
      final again = await repo.load();
      expect(again.expiryReminders, isFalse);
      expect(again.reminderShowNames, isTrue);
      expect(const AppSettings(), isNot(equals(again)));
    });
  });
}

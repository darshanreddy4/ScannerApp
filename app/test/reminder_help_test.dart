import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/reminders/data/reminder_platform.dart';
import 'package:doculoom/features/reminders/domain/reminder_help.dart';
import 'package:doculoom/features/reminders/domain/reminder_service.dart';
import 'package:doculoom/features/reminders/presentation/reminder_help_page.dart';

import 'support/reminder_fakes.dart';

void main() {
  group('advice by maker', () {
    test('makers with their own background screen are named', () {
      final names = {
        'xiaomi': 'Xiaomi',
        'Redmi': 'Xiaomi',
        'POCO': 'Xiaomi',
        'oppo': 'Oppo',
        'realme': 'Realme',
        'OnePlus': 'OnePlus',
        'vivo': 'Vivo',
        'iQOO': 'Vivo',
        'HUAWEI': 'Huawei',
        'HONOR': 'Honor',
        'samsung': 'Samsung',
        'asus': 'Asus',
        'TECNO': 'Tecno, Infinix or Itel',
        'infinix': 'Tecno, Infinix or Itel',
        'itel': 'Tecno, Infinix or Itel',
      };
      names.forEach((maker, name) {
        final h = reminderHelpFor(maker);
        expect((h.maker, h.hasMakerScreen), (name, true), reason: maker);
        expect(h.hint, isNotEmpty);
      });
    });

    test('other phones get the general advice and no maker button', () {
      for (final maker in ['google', 'motorola', 'nothing', '']) {
        final h = reminderHelpFor(maker);
        expect((h.maker, h.hasMakerScreen), ('', false), reason: maker);
        expect(h.hint, contains('run in the background'));
      }
    });
  });

  group('the page', () {
    Future<FakeReminderPlatform> open(WidgetTester tester, {String maker = '', ReminderAccess access = ReminderAccess.granted, double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 4000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final platform = FakeReminderPlatform(access: access)..makerName = maker;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ReminderHelpPage(service: ReminderService(platform)),
        ),
      );
      await tester.pumpAndSettle();
      return platform;
    }

    testWidgets('a phone with a maker screen offers battery, maker and test steps', (tester) async {
      final p = await open(tester, maker: 'xiaomi');
      expect(find.text('Step 1: Battery'), findsOneWidget);
      expect(find.text('Step 2: Xiaomi settings'), findsOneWidget);
      expect(find.text('Step 3: Test'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('help-battery')));
      await tester.tap(find.byKey(const ValueKey('help-maker')));
      await tester.tap(find.byKey(const ValueKey('help-test')));
      await tester.pump();
      expect((p.batteryOpened, p.autostartOpened, p.tests), (1, 1, 1));
      expect(find.text('Test set. Close Doculoom now and wait 2 minutes.'), findsOneWidget);
    });

    testWidgets('a phone without one shows the general advice instead', (tester) async {
      await open(tester, maker: 'google');
      expect(find.byKey(const ValueKey('help-maker')), findsNothing);
      expect(find.byKey(const ValueKey('help-generic')), findsOneWidget);
      expect(find.text('Step 2: Test'), findsOneWidget);
    });

    testWidgets('with notifications off the first step is to allow them', (tester) async {
      final p = await open(tester, maker: 'samsung', access: ReminderAccess.blocked);
      expect(find.text('Step 1: Allow notifications'), findsOneWidget);
      expect(find.text('Step 4: Test'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('help-notifications')));
      await tester.pump();
      expect(p.settingsOpened, 1);
    });

    testWidgets('a phone that cannot show reminders says so and offers nothing to try', (tester) async {
      await open(tester, access: ReminderAccess.unsupported);
      expect(find.byKey(const ValueKey('help-unsupported')), findsOneWidget);
      expect(find.byKey(const ValueKey('help-test')), findsNothing);
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await open(tester, maker: 'huawei', access: ReminderAccess.blocked, width: w);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

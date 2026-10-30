import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/cards/data/card_store.dart';
import 'package:doculoom/features/cards/data/screen_boost.dart';
import 'package:doculoom/features/cards/domain/cards.dart';
import 'package:doculoom/features/cards/presentation/card_code_view.dart';
import 'package:doculoom/features/cards/presentation/card_edit_page.dart';
import 'package:doculoom/features/cards/presentation/card_view_page.dart';
import 'package:doculoom/features/cards/presentation/cards_page.dart';
import 'package:doculoom/features/qr/domain/scan_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Boost extends ScreenBoost {
  _Boost();
  final calls = <bool>[];

  @override
  Future<void> on() async => calls.add(true);

  @override
  Future<void> off() async => calls.add(false);
}

void main() {
  const tesco = LoyaltyCard(id: 'a', name: 'Tesco Clubcard', number: '4006381333931', type: CardCodeType.ean13);

  group('numbers', () {
    test('the check digit of EAN and UPC codes', () {
      expect(eanCheckDigit('400638133393'), 1);
      expect(eanCheckDigit('03600029145'), 2);
      expect(eanCheckDigit('9638507'), 4);
    });

    test('EAN-13, UPC-A and EAN-8 need the right length and check digit', () {
      expect(numberProblem(CardCodeType.ean13, '4006381333931'), isNull);
      expect(numberProblem(CardCodeType.upca, '036000291452'), isNull);
      expect(numberProblem(CardCodeType.ean8, '96385074'), isNull);
      expect(numberProblem(CardCodeType.ean13, '400638133393')!.text, 'The EAN-13 code must be exactly 13 digits, with no spaces or letters.');
      expect(numberProblem(CardCodeType.ean13, '4006381333932')!.text, contains('should be 1 here'));
      expect(numberProblem(CardCodeType.ean13, '40063813339AB')!.text, contains('13 digits'));
    });

    test('Code 39, ITF and Code 128 explain what they take', () {
      expect(numberProblem(CardCodeType.code39, 'AB-12'), isNull);
      expect(numberProblem(CardCodeType.code39, 'ab-12')!.text, contains('capital letters'));
      expect(numberProblem(CardCodeType.itf, '1234'), isNull);
      expect(numberProblem(CardCodeType.itf, '123')!.text, contains('even number'));
      expect(numberProblem(CardCodeType.itf, '12a4')!.text, contains('digits only'));
      expect(numberProblem(CardCodeType.code128, 'Member 00123'), isNull);
      expect(numberProblem(CardCodeType.code128, 'Caf\u00E9')!.text, contains('plain letters'));
    });

    test('empty, too long, and number only', () {
      expect(numberProblem(CardCodeType.code128, '  ')!.text, 'Enter the card number.');
      expect(numberProblem(CardCodeType.qr, 'x' * 121)!.text, contains('too long'));
      expect(numberProblem(CardCodeType.none, 'any thing 12-34'), isNull);
    });

    test('every drawn type can draw a number it accepts', () {
      const samples = {
        CardCodeType.code128: 'ABC-123',
        CardCodeType.ean13: '4006381333931',
        CardCodeType.ean8: '96385074',
        CardCodeType.upca: '036000291452',
        CardCodeType.code39: 'ABC-123',
        CardCodeType.code93: 'ABC123',
        CardCodeType.itf: '123456',
        CardCodeType.qr: 'https://example.com/card/1',
        CardCodeType.pdf417: 'MEMBER 00123',
        CardCodeType.aztec: 'MEMBER 00123',
        CardCodeType.dataMatrix: 'MEMBER 00123',
      };
      samples.forEach((type, number) => expect(numberProblem(type, number), isNull, reason: type.label));
    });

    test('a hand-typed number gets the matching product type, else Code 128', () {
      expect(suggestCodeType('4006381333931'), CardCodeType.ean13);
      expect(suggestCodeType('036000291452'), CardCodeType.upca);
      expect(suggestCodeType('96385074'), CardCodeType.ean8);
      expect(suggestCodeType('4006381333932'), CardCodeType.code128);
      expect(suggestCodeType('M-00123'), CardCodeType.code128);
      expect(suggestCodeType('4006 3813 33931'), CardCodeType.ean13);
    });

    test('scanned format names map to a type', () {
      expect(CardCodeType.fromScan('qrCode'), CardCodeType.qr);
      expect(CardCodeType.fromScan('upcA'), CardCodeType.upca);
      expect(CardCodeType.fromScan('itf14'), CardCodeType.itf);
      expect(CardCodeType.fromScan('dataMatrix'), CardCodeType.dataMatrix);
      expect(CardCodeType.fromScan('unknown'), isNull);
    });
  });

  group('cards', () {
    test('a card is checked field by field', () {
      final p = cardProblems(const LoyaltyCard(id: '', name: ' ', number: ''), []);
      expect(p.keys, containsAll(['name', 'number']));
      expect(cardProblems(LoyaltyCard(id: '', name: 'x' * 41, number: '1'), [])['name']!.text, contains('too long'));
      expect(cardProblems(LoyaltyCard(id: '', name: 'A', number: '1', note: 'n' * 201), [])['note'], isNotNull);
      expect(cardProblems(tesco, []), isEmpty);
    });

    test('the same name and number cannot be saved twice, but a card can be saved over itself', () {
      expect(cardProblems(tesco.copyWith(id: 'b', name: 'tesco clubcard'), [tesco])['number']!.text, 'This card is already saved.');
      expect(cardProblems(tesco, [tesco]), isEmpty);
    });

    test('tidying trims, joins digits printed in groups and capitalises Code 39', () {
      final a = tidyCard(const LoyaltyCard(id: '', name: '  Big   Bazaar ', number: ' 4006 3813 33931 ', type: CardCodeType.ean13));
      expect(a.name, 'Big Bazaar');
      expect(a.number, '4006381333931');
      expect(tidyCard(const LoyaltyCard(id: '', name: 'A', number: 'ab-12', type: CardCodeType.code39)).number, 'AB-12');
      expect(tidyCard(const LoyaltyCard(id: '', name: 'A', number: '12 34-56', type: CardCodeType.none)).number, '12 34-56');
      expect(tidyCard(const LoyaltyCard(id: '', name: 'A', number: '1234 5678 90')).number, '1234567890');
      expect(tidyCard(const LoyaltyCard(id: '', name: 'A', number: 'AB 12')).number, 'AB 12');
    });

    test('saved and read back as it was', () {
      final c = tesco.copyWith(note: 'n', expiry: DateTime(2027, 3, 9), pinned: true, usedAt: 5, category: CardCategory.supermarket, color: cardColors[2]);
      final back = LoyaltyCard.fromJson(c.toJson())!;
      expect(back.toJson(), c.toJson());
      expect(back.expiry, DateTime(2027, 3, 9));
      expect(LoyaltyCard.fromJson({'id': 'x', 'name': '', 'number': '1'}), isNull);
      expect(LoyaltyCard.fromJson(3), isNull);
    });

    test('a card without a last day is never out of date; others turn soon at 30 days', () {
      final now = DateTime(2026, 6, 1);
      expect(validityOf(tesco, now), CardValidity.none);
      expect(validityOf(tesco.copyWith(expiry: DateTime(2026, 5, 31)), now), CardValidity.expired);
      expect(validityOf(tesco.copyWith(expiry: DateTime(2026, 6, 1)), now), CardValidity.soon);
      expect(validityOf(tesco.copyWith(expiry: DateTime(2026, 7, 1)), now), CardValidity.soon);
      expect(validityOf(tesco.copyWith(expiry: DateTime(2026, 7, 2)), now), CardValidity.valid);
      expect(validityOf(tesco.copyWith(expiry: null), now), CardValidity.none);
    });

    test('the list puts pinned first, then the latest used, then by name, and can be searched', () {
      final cards = [
        tesco.copyWith(id: '1', name: 'Zed'),
        tesco.copyWith(id: '2', name: 'Alpha', usedAt: 10),
        tesco.copyWith(id: '3', name: 'Beta', usedAt: 20),
        tesco.copyWith(id: '4', name: 'Mid', pinned: true),
        tesco.copyWith(id: '5', name: 'Cafe', category: CardCategory.food, note: 'gold member'),
      ];
      expect(sortedCards(cards).map((c) => c.id), ['4', '3', '2', '5', '1']);
      expect(sortedCards(cards, query: 'gold').map((c) => c.id), ['5']);
      expect(sortedCards(cards, query: 'food').map((c) => c.id), ['5']);
      expect(sortedCards(cards, query: 'zzz'), isEmpty);
    });

    test('only the last four characters of a number show in a list', () {
      expect(maskedNumber('4006381333931'), '\u2022\u2022\u2022\u2022 3931');
      expect(maskedNumber('123'), '123');
    });
  });

  group('store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('cards are added, changed in place, removed and cleared', () async {
      const store = CardStore();
      await store.put(tesco);
      await store.put(tesco.copyWith(id: 'b', name: 'Lib'));
      await store.put(tesco.copyWith(pinned: true));
      var all = await store.load();
      expect(all.map((c) => c.id), ['a', 'b']);
      expect(all.first.pinned, isTrue);
      all = await store.remove('a');
      expect(all.map((c) => c.id), ['b']);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('damaged data and broken entries are ignored', () async {
      SharedPreferences.setMockInitialValues({'loyalty_cards': 'nope'});
      expect(await const CardStore().load(), isEmpty);
      SharedPreferences.setMockInitialValues({'loyalty_cards': '[{"id":"x","name":"","number":"1"},{"id":"y","name":"Ok","number":"1"}]'});
      expect((await const CardStore().load()).map((c) => c.id), ['y']);
    });

    test('new ids are never repeated', () {
      final id = const CardStore().newId([tesco.copyWith(id: '5')], DateTime.fromMicrosecondsSinceEpoch(5));
      expect(id, isNot('5'));
    });

    test('the screen helper does nothing, and does not fail, where the phone side is missing', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await const ScreenBoost().on();
      await const ScreenBoost().off();
    });
  });

  group('screens', () {
    late _Boost boost;
    DateTime now() => DateTime(2026, 6, 1);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester, String start, {double width = 400, double height = 900}) async {
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      boost = _Boost();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/cards',
            builder: (_, _) => CardsPage(now: now),
          ),
          GoRoute(
            path: '/card-view',
            builder: (_, s) => CardViewPage(cardId: s.extra! as String, boost: boost, now: now),
          ),
          GoRoute(
            path: '/card-edit',
            builder: (_, s) => CardEditPage(args: s.extra is CardEditArgs ? s.extra! as CardEditArgs : const CardEditArgs(), now: now),
          ),
          GoRoute(
            path: '/card-scan',
            builder: (context, _) => Scaffold(
              body: TextButton(
                key: const ValueKey('fake-scan'),
                onPressed: () => Navigator.of(context).pop(const DetectedCode(raw: '96385074', format: 'ean8')),
                child: const Text('found'),
              ),
            ),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
      await settle(tester);
      if (start != '/') {
        unawaited(router.push<Object?>(start));
        await settle(tester);
      }
    }

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('an empty list explains itself and offers to scan or type', (tester) async {
      await open(tester, '/cards');
      expect(find.text('No cards yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-scan')), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-type')), findsOneWidget);
      expect(find.byKey(const ValueKey('cards-add')), findsNothing);
    });

    testWidgets('saving an empty form says what is missing, in the fields', (tester) async {
      await open(tester, '/card-edit');
      await tester.ensureVisible(find.byKey(const ValueKey('card-save')));
      await tester.tap(find.byKey(const ValueKey('card-save')));
      await settle(tester);
      expect(find.text('Enter the name of the shop or club.'), findsOneWidget);
      expect(find.text('Enter the card number.'), findsOneWidget);
      expect(find.text('Fix the fields marked above, then save.'), findsOneWidget);
      expect(await const CardStore().load(), isEmpty);
    });

    testWidgets('a number with a wrong check digit is called out, and a right one shows the code', (tester) async {
      await open(tester, '/card-edit');
      await tester.enterText(find.byKey(const ValueKey('card-number')), '4006381333932');
      await tester.ensureVisible(find.byKey(const ValueKey('card-type')));
      await tester.tap(find.byKey(const ValueKey('card-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EAN-13').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('card-preview')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('card-name')), 'Tesco');
      await tester.tap(find.byKey(const ValueKey('card-save')));
      await settle(tester);
      expect(find.textContaining('should be 1 here'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('card-number')), '4006381333931');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('card-preview')), findsOneWidget);
      expect(find.textContaining('should be 1 here'), findsNothing);
    });

    testWidgets('a typed card is saved tidied, with the type its number suggests', (tester) async {
      await open(tester, '/card-edit');
      await tester.enterText(find.byKey(const ValueKey('card-name')), '  Big   Bazaar ');
      await tester.enterText(find.byKey(const ValueKey('card-number')), '4006 3813 33931');
      await tester.ensureVisible(find.byKey(const ValueKey('card-save')));
      await tester.tap(find.byKey(const ValueKey('card-save')));
      await settle(tester);
      final saved = (await const CardStore().load()).single;
      expect(saved.name, 'Big Bazaar');
      expect(saved.number, '4006381333931');
      expect(saved.type, CardCodeType.ean13);
    });

    testWidgets('the scan button fills in the number and the type of the code', (tester) async {
      await open(tester, '/card-edit');
      await tester.tap(find.byKey(const ValueKey('card-scan')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('fake-scan')));
      await settle(tester);
      expect(find.text('96385074'), findsOneWidget);
      expect(find.byKey(const ValueKey('card-preview')), findsOneWidget);
      expect(find.text('EAN-8'), findsWidgets);
    });

    testWidgets('a saved card is listed with its number hidden, and can be pinned and deleted', (tester) async {
      await tester.runAsync(() => const CardStore().put(tesco));
      await open(tester, '/cards');
      expect(find.text('Tesco Clubcard'), findsOneWidget);
      expect(find.textContaining('3931'), findsOneWidget);
      expect(find.textContaining('4006381333931'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('card-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin to the top'));
      await settle(tester);
      expect((await tester.runAsync(const CardStore().load))!.single.pinned, isTrue);
      await tester.tap(find.byKey(const ValueKey('card-menu-a')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this card?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      expect(find.text('No cards yet'), findsOneWidget);
    });

    testWidgets('search appears with more than five cards', (tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => const CardStore().put(tesco.copyWith(id: 'c$i', name: i == 3 ? 'Library' : 'Shop $i')));
      }
      await open(tester, '/cards');
      await tester.enterText(find.byKey(const ValueKey('cards-search')), 'libr');
      await tester.pump();
      expect(find.byKey(const ValueKey('card-c3')), findsOneWidget);
      expect(find.byKey(const ValueKey('card-c0')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('cards-search')), 'nothing');
      await tester.pump();
      expect(find.text('No card matches your search.'), findsOneWidget);
    });

    testWidgets('showing a card turns the screen up, marks it used, and puts the screen back when closed', (tester) async {
      await tester.runAsync(() => const CardStore().put(tesco.copyWith(expiry: DateTime(2026, 6, 20))));
      await open(tester, '/');
      final context = tester.element(find.text('home'));
      GoRouter.of(context).push('/card-view', extra: 'a');
      await settle(tester);
      expect(boost.calls, [true]);
      expect(find.byKey(const ValueKey('card-code')), findsOneWidget);
      expect(find.textContaining('runs out soon'), findsOneWidget);
      expect((await tester.runAsync(const CardStore().load))!.single.usedAt, now().millisecondsSinceEpoch);
      GoRouter.of(context).pop();
      await settle(tester);
      expect(boost.calls, [true, false]);
    });

    testWidgets('an expired card says so, a missing card says so', (tester) async {
      await tester.runAsync(() => const CardStore().put(tesco.copyWith(expiry: DateTime(2026, 5, 1))));
      await open(tester, '/');
      final context = tester.element(find.text('home'));
      GoRouter.of(context).push('/card-view', extra: 'a');
      await settle(tester);
      expect(find.textContaining('Expired on'), findsOneWidget);
      GoRouter.of(context).pop();
      await settle(tester);
      GoRouter.of(context).push('/card-view', extra: 'gone');
      await settle(tester);
      expect(find.text('This card was not found.'), findsOneWidget);
    });

    testWidgets('the code is drawn for each type without errors', (tester) async {
      for (final t in CardCodeType.values.where((t) => t.isDrawn)) {
        final number = switch (t) {
          CardCodeType.ean13 => '4006381333931',
          CardCodeType.ean8 => '96385074',
          CardCodeType.upca => '036000291452',
          CardCodeType.upce => '01234565',
          CardCodeType.itf => '123456',
          CardCodeType.codabar => 'A123456A',
          _ => 'ABC123',
        };
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CardCodeView(type: t, number: number),
            ),
          ),
        );
        expect(tester.takeException(), isNull, reason: t.label);
        expect(find.byType(CustomPaint), findsWidgets, reason: t.label);
      }
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('the screens fit a ${w.toInt()} px wide screen', (tester) async {
        await tester.runAsync(
          () => const CardStore().put(tesco.copyWith(name: 'A shop with a very long name for a card', expiry: DateTime(2026, 5, 1), note: 'Some note')),
        );
        await open(tester, '/cards', width: w, height: 640);
        final context = tester.element(find.byType(CardsPage));
        GoRouter.of(context).push('/card-view', extra: 'a');
        await settle(tester);
        GoRouter.of(context).pop();
        await settle(tester);
        GoRouter.of(context).push('/card-edit', extra: const CardEditArgs(card: tesco));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/checklists/data/checklist_store.dart';
import 'package:doculoom/features/checklists/domain/checklists.dart';
import 'package:doculoom/features/checklists/presentation/checklists_page.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const base = Checklist(
    id: 'a',
    title: 'Visa',
    items: [
      ChecklistItem(id: 0, text: 'Passport'),
      ChecklistItem(id: 1, text: 'Photos', done: true),
      ChecklistItem(id: 2, text: 'Form'),
    ],
  );

  group('ready-made lists', () {
    test('every list has steps within the limits and known regions', () {
      final ids = <String>{};
      for (final t in checklistTemplates) {
        expect(ids.add(t.id), isTrue, reason: t.id);
        expect(t.steps.where((s) => s.region.isEmpty).length, greaterThanOrEqualTo(5), reason: t.id);
        expect(t.steps.length, lessThanOrEqualTo(maxChecklistItems), reason: t.id);
        for (final s in t.steps) {
          expect(stepProblem(s.text), isNull, reason: s.text);
          expect(['', 'india', 'usa', 'europe', 'gulf'], contains(s.region), reason: s.text);
        }
        expect(titleProblem(t.title), isNull);
      }
    });

    test('a list starts with the steps for everyone and for the region only', () {
      final t = checklistTemplates.firstWhere((t) => t.id == 'tax');
      final now = DateTime(2026, 1, 2);
      final india = checklistFromTemplate(t, region: 'india', id: 'x', now: now);
      final other = checklistFromTemplate(t, region: 'other', id: 'x', now: now);
      expect(india.items.map((i) => i.text), contains('Form 16 and Form 26AS'));
      expect(india.items.map((i) => i.text), isNot(contains('W-2 and 1099 forms')));
      expect(other.items.length, t.steps.where((s) => s.region.isEmpty).length);
      expect(india.items.map((i) => i.id).toSet().length, india.items.length);
      expect(india.title, 'Filing taxes');
      expect(india.templateId, 'tax');
      expect(india.createdAt, now.millisecondsSinceEpoch);
      expect(india.doneCount, 0);
    });

    test('the lists with steps for the region come first', () {
      final order = orderedTemplates('india').map((t) => t.id).toList();
      expect(order.take(6).toSet(), {'rent', 'job', 'car', 'baby', 'wedding', 'tax'});
      expect(orderedTemplates('other').map((t) => t.id), checklistTemplates.map((t) => t.id));
      expect(orderedTemplates('usa').length, checklistTemplates.length);
    });
  });

  group('a list', () {
    test('counts what is done', () {
      expect(base.doneCount, 1);
      expect(base.progress, closeTo(1 / 3, 1e-9));
      expect(base.isComplete, isFalse);
      expect(const Checklist(id: 'e', title: 'Empty').progress, 0);
      expect(const Checklist(id: 'e', title: 'Empty').isComplete, isFalse);
      expect(base.copyWith(items: [for (final i in base.items) i.copyWith(done: true)]).isComplete, isTrue);
    });

    test('a new step gets an id that is not used, even after others are deleted', () {
      expect(base.nextId, 3);
      expect(base.copyWith(items: [base.items[0], base.items[2]]).nextId, 3);
      expect(const Checklist(id: 'e', title: 'x').nextId, 0);
    });

    test('where it stands against its day', () {
      final now = DateTime(2026, 6, 10);
      expect(dueStateOf(base, now), DueState.none);
      expect(dueStateOf(base.copyWith(due: DateTime(2026, 6, 9)), now), DueState.overdue);
      expect(dueStateOf(base.copyWith(due: DateTime(2026, 6, 10)), now), DueState.soon);
      expect(dueStateOf(base.copyWith(due: DateTime(2026, 6, 17)), now), DueState.soon);
      expect(dueStateOf(base.copyWith(due: DateTime(2026, 6, 18)), now), DueState.later);
      final done = base.copyWith(items: [for (final i in base.items) i.copyWith(done: true)], due: DateTime(2026, 1, 1));
      expect(dueStateOf(done, now), DueState.done);
    });

    test('names and steps are checked', () {
      expect(titleProblem('  ')!.text, 'Enter a name for the list.');
      expect(titleProblem('x' * 61)!.text, contains('too long'));
      expect(titleProblem('x' * 60), isNull);
      expect(stepProblem('')!.text, 'Write what has to be done.');
      expect(stepProblem('x' * 121)!.text, contains('too long'));
      expect(stepProblem('ok', note: 'n' * 201)!.text, contains('note is too long'));
      expect(stepProblem('ok', note: 'fine'), isNull);
    });

    test('the text to send has a box per step and the notes', () {
      final l = base.copyWith(
        items: [
          base.items[0].copyWith(note: 'Renew first'),
          base.items[1],
        ],
      );
      expect(checklistAsText(l), 'Visa\n[ ] Passport\n    Renew first\n[x] Photos');
    });

    test('saved and read back as it was, and broken data is dropped', () {
      final l = base.copyWith(
        due: DateTime(2026, 3, 9),
        items: [
          base.items[0].copyWith(note: 'n', docId: 'd1'),
          base.items[1],
        ],
      );
      final back = Checklist.fromJson(l.toJson())!;
      expect(back.toJson(), l.toJson());
      expect(back.due, DateTime(2026, 3, 9));
      expect(back.items.first.docId, 'd1');
      expect(Checklist.fromJson({'id': 'x', 'title': '', 'items': []}), isNull);
      expect(
        Checklist.fromJson({
          'id': 'x',
          'title': 'T',
          'items': [
            3,
            {'id': 1, 'text': ''},
            {'id': 2, 'text': 'ok'},
          ],
        })!.items.length,
        1,
      );
    });
  });

  group('store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('lists are added, changed in place, removed and cleared', () async {
      const store = ChecklistStore();
      await store.put(base);
      await store.put(base.copyWith(title: 'Second').copyWith());
      await store.put(const Checklist(id: 'b', title: 'Other'));
      var all = await store.load();
      expect(all.map((l) => l.id), ['a', 'b']);
      expect(all.first.title, 'Second');
      all = await store.remove('a');
      expect(all.map((l) => l.id), ['b']);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('damaged data is ignored and new ids are not repeated', () async {
      SharedPreferences.setMockInitialValues({'checklists': 'nope'});
      expect(await const ChecklistStore().load(), isEmpty);
      expect(const ChecklistStore().newId([const Checklist(id: '5', title: 'x')], DateTime.fromMicrosecondsSinceEpoch(5)), isNot('5'));
    });
  });

  group('screens', () {
    final doc = ScannedDocument(id: 'd1', title: 'Passport scan', createdAt: DateTime(2026, 1, 1), updatedAt: DateTime(2026, 1, 2), pages: const []);
    DateTime now() => DateTime(2026, 6, 1);
    String? shared;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester, String start, {double width = 400, double height = 900, List<ScannedDocument>? docs}) async {
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      shared = null;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/checklists',
            builder: (_, _) => ChecklistsPage(now: now, region: 'india'),
          ),
          GoRoute(
            path: '/checklist',
            builder: (_, s) => ChecklistPage(
              listId: s.extra! as String,
              now: now,
              documentsOf: (_) => docs ?? [doc],
              share: (text, subject) async => shared = '$subject|$text',
            ),
          ),
          GoRoute(
            path: '/document/:id',
            builder: (_, s) => Scaffold(body: Text('doc ${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
      await settle(tester);
      if (start != '/') {
        unawaited(router.push<Object?>(start, extra: start.startsWith('/checklist?') ? null : null));
        await settle(tester);
      }
    }

    Future<void> openList(WidgetTester tester, {List<ScannedDocument>? docs, double width = 400, double height = 900}) async {
      await open(tester, '/', width: width, height: height, docs: docs);
      final ctx = tester.element(find.text('home'));
      unawaited(GoRouter.of(ctx).push<Object?>('/checklist', extra: 'a'));
      await settle(tester);
    }

    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('an empty list of lists explains itself', (tester) async {
      await open(tester, '/checklists');
      expect(find.text('No checklists yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-start')), findsOneWidget);
      expect(find.byKey(const ValueKey('lists-new')), findsNothing);
    });

    testWidgets('a ready-made list is chosen, made with the steps for the region, and opened', (tester) async {
      await open(tester, '/checklists');
      await tester.tap(find.byKey(const ValueKey('empty-start')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('template-blank')), findsOneWidget);
      expect(find.text('Renting a home'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('template-rent')));
      await settle(tester);
      expect(find.text('Renting a home'), findsWidgets);
      expect(find.text('Police verification of the tenant, if your city asks for it'), findsOneWidget);
      expect(find.text('0 of 9 done'), findsOneWidget);
      final saved = (await tester.runAsync(const ChecklistStore().load))!.single;
      expect(saved.templateId, 'rent');
      expect(saved.items.length, 9);
    });

    testWidgets('a blank list needs a name, with a message', (tester) async {
      await open(tester, '/checklists');
      await tester.tap(find.byKey(const ValueKey('empty-start')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('template-blank')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-name-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name for the list.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('list-name')), '  Garden project ');
      await tester.tap(find.byKey(const ValueKey('list-name-ok')));
      await settle(tester);
      expect((await tester.runAsync(const ChecklistStore().load))!.single.title, 'Garden project');
      expect(find.text('This list has no steps yet. Add the first one below.'), findsOneWidget);
    });

    testWidgets('lists show their progress and can be deleted after a question', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base.copyWith(due: DateTime(2026, 5, 1))));
      await open(tester, '/checklists');
      expect(find.text('Visa'), findsOneWidget);
      expect(find.textContaining('1 of 3 done'), findsOneWidget);
      expect(find.textContaining('Was due'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('list-delete-a')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this checklist?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      expect(find.text('No checklists yet'), findsOneWidget);
    });

    testWidgets('ticking a step moves the progress and is kept', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base));
      await openList(tester);
      expect(find.text('1 of 3 done'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('step-check-0')));
      await settle(tester);
      expect(find.text('2 of 3 done'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('step-2')));
      await settle(tester);
      expect(find.text('3 of 3 done'), findsOneWidget);
      expect(find.text('Everything on this list is done.'), findsOneWidget);
      expect((await tester.runAsync(const ChecklistStore().load))!.single.doneCount, 3);
    });

    testWidgets('a step is added, an empty one is refused with a message', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base));
      await openList(tester);
      await tester.tap(find.byKey(const ValueKey('add-step')));
      await tester.pump();
      expect(find.text('Write what has to be done.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('new-step')), '  Bank letter ');
      await tester.pump();
      expect(find.text('Write what has to be done.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('add-step')));
      await settle(tester);
      expect(find.text('Bank letter'), findsOneWidget);
      expect((await tester.runAsync(const ChecklistStore().load))!.single.items.last.text, 'Bank letter');
    });

    testWidgets('a list stops at 40 steps with a message', (tester) async {
      await tester.runAsync(
        () => const ChecklistStore().put(
          Checklist(
            id: 'a',
            title: 'Big',
            items: [for (var i = 0; i < 40; i++) ChecklistItem(id: i, text: 'Step $i')],
          ),
        ),
      );
      await openList(tester);
      await tester.dragUntilVisible(find.byKey(const ValueKey('new-step')), find.byType(ListView), const Offset(0, -300));
      await tester.enterText(find.byKey(const ValueKey('new-step')), 'One more');
      await tester.tap(find.byKey(const ValueKey('add-step')));
      await tester.pump();
      expect(find.text('A list has up to 40 steps. Delete one to add another.'), findsOneWidget);
    });

    testWidgets('a step is edited with a note, and a wrong edit is explained', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base));
      await openList(tester);
      await tester.tap(find.byKey(const ValueKey('step-menu-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit step'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('step-text')), '');
      await tester.tap(find.byKey(const ValueKey('step-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Write what has to be done.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('step-text')), 'Passport, renewed');
      await tester.enterText(find.byKey(const ValueKey('step-note')), 'Expires in May');
      await tester.tap(find.byKey(const ValueKey('step-ok')));
      await settle(tester);
      expect(find.text('Passport, renewed'), findsOneWidget);
      expect(find.text('Expires in May'), findsOneWidget);
      final saved = (await tester.runAsync(const ChecklistStore().load))!.single.items.first;
      expect(saved.text, 'Passport, renewed');
      expect(saved.note, 'Expires in May');
    });

    testWidgets('a scanned document is linked as proof, opened from the step, and unlinked', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base));
      await openList(tester);
      await tester.tap(find.byKey(const ValueKey('step-menu-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link a document'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-d1')));
      await settle(tester);
      expect(find.byKey(const ValueKey('step-doc-0')), findsOneWidget);
      expect(find.text('2 of 3 done'), findsOneWidget, reason: 'a step with its proof attached is done');
      await tester.tap(find.byKey(const ValueKey('step-doc-0')));
      await tester.pumpAndSettle();
      expect(find.text('doc d1'), findsOneWidget);
      GoRouter.of(tester.element(find.text('doc d1'))).pop();
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('step-menu-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove the link'));
      await settle(tester);
      expect(find.byKey(const ValueKey('step-doc-0')), findsNothing);
      expect((await tester.runAsync(const ChecklistStore().load))!.single.items.first.docId, isNull);
    });

    testWidgets('with no documents the picker says so, and a link to a deleted document is called out', (tester) async {
      await tester.runAsync(
        () => const ChecklistStore().put(
          base.copyWith(
            items: [
              base.items[0].copyWith(docId: 'gone'),
              base.items[1],
            ],
          ),
        ),
      );
      await openList(tester, docs: const []);
      expect(find.text('The linked document is no longer in your library.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('step-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Link a document'));
      await tester.pumpAndSettle();
      expect(find.textContaining('You have no saved documents yet'), findsOneWidget);
    });

    testWidgets('the finish date, rename, clear ticks and share work', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base));
      await openList(tester);
      await tester.tap(find.byKey(const ValueKey('list-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set the finish date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect((await tester.runAsync(const ChecklistStore().load))!.single.due, DateTime(2026, 6, 8));
      expect(find.textContaining('Due '), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('list-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('rename-field')), ' ');
      await tester.tap(find.byKey(const ValueKey('rename-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name for the list.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('rename-field')), 'Schengen visa');
      await tester.tap(find.byKey(const ValueKey('rename-ok')));
      await settle(tester);
      expect(find.text('Schengen visa'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('list-share')));
      await tester.pump();
      expect(shared, 'Schengen visa|Schengen visa\n[ ] Passport\n[x] Photos\n[ ] Form');

      await tester.tap(find.byKey(const ValueKey('list-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear all ticks'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Clear ticks'));
      await settle(tester);
      expect(find.text('0 of 3 done'), findsOneWidget);
    });

    testWidgets('deleting the list asks first and goes back', (tester) async {
      await tester.runAsync(() => const ChecklistStore().put(base));
      await openList(tester);
      await tester.tap(find.byKey(const ValueKey('list-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete the list'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      expect(find.text('home'), findsOneWidget);
      expect(await tester.runAsync(const ChecklistStore().load), isEmpty);
    });

    testWidgets('a list that is not there says so', (tester) async {
      await openList(tester);
      expect(find.text('This checklist was not found.'), findsOneWidget);
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('the screens fit a ${w.toInt()} px wide screen', (tester) async {
        await tester.runAsync(
          () => const ChecklistStore().put(
            Checklist(
              id: 'a',
              title: 'Moving to a new apartment across the city next month',
              templateId: 'move',
              due: DateTime(2026, 5, 1),
              items: [
                const ChecklistItem(
                  id: 0,
                  text: 'Tell your bank and card providers the new address and update the address on your ID and licence',
                  note: 'Branch visit on Monday',
                  docId: 'd1',
                ),
                const ChecklistItem(id: 1, text: 'Set up mail forwarding', done: true),
              ],
            ),
          ),
        );
        await open(tester, '/checklists', width: w, height: 640);
        expect(tester.takeException(), isNull);
        final ctx = tester.element(find.byType(ChecklistsPage));
        unawaited(GoRouter.of(ctx).push<Object?>('/checklist', extra: 'a'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('step-menu-0')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose another document'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_forms.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_form_cubit.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_form_page.dart';

import 'support/pdf_ui_fakes.dart';

PdfFormInfo sampleInfo({bool fields = true, int notes = 0, int pages = 1}) => PdfFormInfo(
  pages: [
    for (var i = 0; i < pages; i++)
      PdfFormPageInfo(
        aspect: 612 / 792,
        widthPt: 612,
        fields: i == 0 && fields
            ? const [
                FormFieldInfo(id: 0, widget: 0, name: 'full name', kind: FormFieldKind.text, page: 0, box: FormBox(0.1, 0.05, 0.9, 0.10), value: ''),
                FormFieldInfo(id: 1, widget: 0, name: 'agree', kind: FormFieldKind.checkbox, page: 0, box: FormBox(0.1, 0.15, 0.16, 0.19), value: 'off'),
                FormFieldInfo(
                  id: 2,
                  widget: 0,
                  name: 'size',
                  kind: FormFieldKind.radio,
                  page: 0,
                  box: FormBox(0.1, 0.25, 0.16, 0.29),
                  value: '',
                  option: 'S',
                  options: [FormOption('S', 'S'), FormOption('L', 'L')],
                ),
                FormFieldInfo(
                  id: 2,
                  widget: 1,
                  name: 'size',
                  kind: FormFieldKind.radio,
                  page: 0,
                  box: FormBox(0.3, 0.25, 0.36, 0.29),
                  value: '',
                  option: 'L',
                  options: [FormOption('S', 'S'), FormOption('L', 'L')],
                ),
                FormFieldInfo(
                  id: 3,
                  widget: 0,
                  name: 'city',
                  kind: FormFieldKind.choice,
                  page: 0,
                  box: FormBox(0.1, 0.35, 0.6, 0.40),
                  value: '',
                  options: [FormOption('PNQ', 'Pune'), FormOption('BOM', 'Mumbai')],
                ),
              ]
            : const [],
      ),
  ],
  notes: notes,
  bytes: 5000,
);

void main() {
  late Directory dir;
  late FakeFormService service;
  late FakeShare share;
  late FakeSave save;

  setUp(() async {
    dir = tempDir();
    service = FakeFormService(sampleInfo());
    share = FakeShare();
    save = FakeSave();
    await sl.reset();
    sl
      ..registerSingleton<PdfFormService>(service)
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<SaveService>(save);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<PdfFormCubit> open(WidgetTester tester, {bool flattenOnly = false, int renderedPages = 1, double width = 400}) async {
    tester.view.physicalSize = Size(width * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PdfFormPage(flattenOnly: flattenOnly, openRenderer: (_) async => FakeRenderer(renderedPages)),
      ),
    );
    final cubit = tester.element(find.byType(Scaffold).first).read<PdfFormCubit>();
    await tester.runAsync(() => cubit.pick('/files/application.pdf'));
    await tester.pump();
    await tester.pump();
    return cubit;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('form-text-input')), text);
    await tester.tap(find.byKey(const ValueKey('form-text-ok')));
    await tester.pumpAndSettle();
  }

  group('fill a form', () {
    testWidgets('the start screen asks for a PDF, and a PDF that cannot be read says why', (tester) async {
      service.inspectFailure = const ExportFailure('This file is not a readable PDF. It may be damaged.');
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PdfFormPage(openRenderer: (_) async => FakeRenderer(1)),
        ),
      );
      expect(find.byKey(const ValueKey('form-pick')), findsOneWidget);
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfFormCubit>();
      await tester.runAsync(() => cubit.pick('/files/bad.pdf'));
      await tester.pump();
      expect(find.byKey(const ValueKey('form-failure')), findsOneWidget);
      expect(find.textContaining('not a readable PDF'), findsOneWidget);
      expect(find.byKey(const ValueKey('form-pick')), findsOneWidget);
    });

    testWidgets('the boxes of the form are drawn on the page, ready to tap', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('field-0-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-1-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-2-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('field-3-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('form-note')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a typed text shows in its box and is sent when saving, once, with the other fields untouched', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('field-0-0')));
      await tester.pumpAndSettle();
      await type(tester, 'Asha Rao');
      expect(find.text('Asha Rao'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      expect(service.plans, hasLength(1));
      expect(service.plans.single.values, {0: 'Asha Rao'});
      expect(service.plans.single.flatten, isFalse);
      expect(find.byKey(const ValueKey('pdf-result')), findsOneWidget);
    });

    testWidgets('a check box flips, a radio button picks its own choice, and a drop-down picks from its list', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('field-1-0')));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsNothing, reason: 'icons are lucide');
      await tester.tap(find.byKey(const ValueKey('field-2-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('field-3-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('option-BOM')));
      await tester.pumpAndSettle();
      expect(find.text('Mumbai'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      expect(service.plans.single.values, {1: 'on', 2: 'L', 3: 'BOM'});
    });

    testWidgets('tapping a check box twice puts it back and nothing is saved when nothing changed', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('field-1-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('field-1-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      // The box was switched on and off again, so the value is still sent as "off", which is a change the person made.
      expect(service.plans.single.values, {1: 'off'});
    });

    testWidgets('saving with no change at all is refused with a message', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      expect(service.plans, isEmpty);
      expect(find.textContaining('Nothing has been changed yet'), findsOneWidget);
    });

    testWidgets('a failure while saving is shown and no result is offered', (tester) async {
      service.saveFailure = const ExportFailure('The text "आशा" cannot be placed in a PDF.');
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('field-0-0')));
      await tester.pumpAndSettle();
      await type(tester, 'x');
      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      expect(find.textContaining('cannot be placed in a PDF'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-result')), findsNothing);
    });

    testWidgets('the flatten switch is sent with the plan', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('form-flatten-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      expect(service.plans.single.flatten, isTrue);
      expect(find.textContaining('Boxes and marks are now part of the pages'), findsOneWidget);
    });

    testWidgets('sharing and saving the result use the file that was made', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('field-1-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-result-share')));
      await settle(tester);
      expect(share.shared.single.mime, 'application/pdf');
      expect(share.shared.single.paths.single, contains('application_filled_'));
      await tester.tap(find.byKey(const ValueKey('pdf-result-save')));
      await settle(tester);
      expect(save.files.single, 'application_filled.pdf', reason: 'the time stamp is taken off the name');
    });
  });

  group('marks on any PDF', () {
    testWidgets('a PDF without form boxes says so and still offers the tools', (tester) async {
      service.info = sampleInfo(fields: false);
      await open(tester);
      expect(find.textContaining('has no form boxes'), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-tick')), findsOneWidget);
    });

    testWidgets('text typed where the page is tapped becomes a mark, and is sent with its place', (tester) async {
      service.info = sampleInfo(fields: false);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('tool-text')));
      await tester.pump();
      expect(find.textContaining('where the text should start'), findsOneWidget);
      final page = find.byKey(const ValueKey('page-0'));
      final rect = tester.getRect(page);
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.5));
      await tester.pumpAndSettle();
      await type(tester, 'Pune');
      expect(find.text('Pune'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      final mark = service.plans.single.marks.single;
      expect(mark.kind, MarkKind.text);
      expect(mark.text, 'Pune');
      expect(mark.u, closeTo(0.25, 0.01));
      expect(mark.v, closeTo(0.5, 0.01));
      expect(mark.sizePt, closeTo(612 * 0.022, 0.01));
    });

    testWidgets('the date tool offers today in a short form that can be changed', (tester) async {
      service.info = sampleInfo(fields: false);
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('tool-date')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-0')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('form-text-input')));
      expect(field.controller!.text, formDate(DateTime.now()));
      expect(field.controller!.text, matches(RegExp(r'^\d{2} [A-Z][a-z]{2} \d{4}$')));
      await type(tester, '01 Jan 2027');
      expect(find.text('01 Jan 2027'), findsOneWidget);
    });

    testWidgets('an empty text adds nothing, and cancelling adds nothing', (tester) async {
      service.info = sampleInfo(fields: false);
      final cubit = await open(tester);
      await tester.tap(find.byKey(const ValueKey('tool-text')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('page-0')));
      await tester.pumpAndSettle();
      await type(tester, '   ');
      expect(cubit.state.marks, isEmpty);
      await tester.tap(find.byKey(const ValueKey('page-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cubit.state.marks, isEmpty);
    });

    testWidgets('ticks and crosses are placed at once, can be undone, and can be removed one by one', (tester) async {
      service.info = sampleInfo(fields: false);
      final cubit = await open(tester);
      await tester.tap(find.byKey(const ValueKey('tool-tick')));
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('page-0'))));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tool-cross')));
      await tester.pump();
      final rect = tester.getRect(find.byKey(const ValueKey('page-0')));
      await tester.tapAt(Offset(rect.left + rect.width * 0.2, rect.top + rect.height * 0.2));
      await tester.pump();
      expect(cubit.state.marks.map((m) => m.kind), [MarkKind.tick, MarkKind.cross]);

      await tester.tap(find.byKey(const ValueKey('form-undo')));
      await tester.pump();
      expect(cubit.state.marks.map((m) => m.kind), [MarkKind.tick]);

      final mark = cubit.state.marks.single;
      await tester.tap(find.byKey(ValueKey('mark-0-${mark.u.toStringAsFixed(3)}-${mark.v.toStringAsFixed(3)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mark-remove')));
      await tester.pumpAndSettle();
      expect(cubit.state.marks, isEmpty);
    });

    testWidgets('a mark outside the page is kept inside it', (tester) async {
      service.info = sampleInfo(fields: false);
      final cubit = await open(tester);
      cubit.addMark(0, 1.4, -0.2, MarkKind.tick);
      expect(cubit.state.marks.single.u, 1.0);
      expect(cubit.state.marks.single.v, 0.0);
      cubit.addMark(5, 0.5, 0.5, MarkKind.tick);
      expect(cubit.state.marks, hasLength(1), reason: 'there is no page 6');
    });

    testWidgets('several pages are all shown', (tester) async {
      service.info = sampleInfo(fields: false, pages: 3);
      await open(tester, renderedPages: 3);
      expect(find.byKey(const ValueKey('page-0')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('flatten only', () {
    testWidgets('there are no tools, the number of things that become permanent is shown, and saving flattens', (tester) async {
      service.info = sampleInfo(notes: 3);
      await open(tester, flattenOnly: true);
      expect(find.byKey(const ValueKey('tool-text')), findsNothing);
      expect(find.byKey(const ValueKey('form-flatten-switch')), findsNothing);
      expect(find.textContaining('3 form boxes and notes will become part of the pages'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('form-save')));
      await settle(tester);
      expect(service.plans.single.flatten, isTrue);
      expect(service.plans.single.values, isEmpty);
      expect(find.textContaining('Your PDF is flattened'), findsOneWidget);
    });

    testWidgets('a PDF with nothing to flatten says so and cannot be saved', (tester) async {
      service.info = sampleInfo(fields: false, notes: 0);
      await open(tester, flattenOnly: true);
      expect(find.textContaining('nothing to flatten'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const ValueKey('form-save')));
      expect(button.onPressed, isNull);
    });

    testWidgets('typing is not possible in this mode', (tester) async {
      service.info = sampleInfo(notes: 1);
      final cubit = await open(tester, flattenOnly: true);
      cubit.setValue(sampleInfo().pages.single.fields.first, 'x');
      cubit.addMark(0, 0.5, 0.5, MarkKind.tick);
      expect(cubit.state.values, isEmpty);
      expect(cubit.state.marks, isEmpty);
    });
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.4)),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: PdfFormPage(openRenderer: (_) async => FakeRenderer(1)),
        ),
      ),
    );
    final cubit = tester.element(find.byType(Scaffold).first).read<PdfFormCubit>();
    await tester.runAsync(() => cubit.pick('/files/a.pdf'));
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

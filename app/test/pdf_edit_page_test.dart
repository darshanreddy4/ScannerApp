import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/reader/data/pdf_text_edit.dart';
import 'package:scanvault/features/text_edit/pdf/pdf_edit_cubit.dart';
import 'package:scanvault/features/text_edit/pdf/pdf_edit_page.dart';
import 'package:scanvault/features/text_edit/pdf/pdf_page_renderer.dart';

const _fixture = 'test/fixtures/office/search_text.pdf';

/// A 1x1 white picture, stretched to the page by the editor.
final _tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _FakeRenderer implements PdfPageRenderer {
  @override
  int get pageCount => 3;

  @override
  Future<Uint8List> render(int page, {required int width}) async => _tinyPng;

  @override
  Future<void> dispose() async {}
}

void main() {
  late Directory work;
  setUp(() => work = Directory.systemTemp.createTempSync('pdf_edit_page'));
  tearDown(() => work.deleteSync(recursive: true));

  Future<PdfEditCubit> open(WidgetTester tester, {String path = _fixture}) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PdfEditPage(path: path, workDir: () async => work, openRenderer: (_) async => _FakeRenderer()),
      ),
    );
    for (var i = 0; i < 60 && find.byKey(const ValueKey('pdf-pages')).evaluate().isEmpty && find.byKey(const ValueKey('pdf-message')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump();
    return tester.element(find.byType(Scaffold).first).read<PdfEditCubit>();
  }

  int lineWith(PdfEditCubit cubit, String text) => cubit.state.pages[0].lines.indexWhere((l) => l.text.contains(text));

  testWidgets('the pages open with their lines marked and nothing changed yet', (tester) async {
    final cubit = await open(tester);
    expect(find.byKey(const ValueKey('pdf-pages')), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    expect(cubit.state.pages.length, 3);
    expect(find.byKey(ValueKey('pdf-line-0-${lineWith(cubit, 'Hello')}')), findsOneWidget);
    expect(find.text('Tap a line to change or remove it. Pinch to zoom.'), findsOneWidget);
    expect(cubit.state.modified, isFalse);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('pdf-undo'))).onPressed, isNull);
  });

  testWidgets('tap a line, retype it, and the page shows the new words; undo brings the old ones back', (tester) async {
    final cubit = await open(tester);
    final line = lineWith(cubit, 'Hello');
    await tester.tap(find.byKey(ValueKey('pdf-line-0-$line')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-line-field')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('pdf-line-field')), 'Goodbye World');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-line-apply')));
    await tester.pumpAndSettle();

    expect(cubit.state.edits.textOf(0, line), 'Goodbye World');
    expect(find.text('Goodbye World'), findsOneWidget);
    expect(cubit.state.modified, isTrue);

    await tester.tap(find.byKey(const ValueKey('pdf-undo')));
    await tester.pumpAndSettle();
    expect(cubit.state.edits.textOf(0, line), isNull);
    expect(find.text('Goodbye World'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('pdf-redo')));
    await tester.pumpAndSettle();
    expect(cubit.state.edits.textOf(0, line), 'Goodbye World');
  });

  testWidgets('characters the built-in fonts cannot show are refused with a message', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(ValueKey('pdf-line-0-${lineWith(cubit, 'Hello')}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-line-field')), 'Hello \u4F60\u597D');
    await tester.pump();
    expect(find.textContaining('These characters cannot be used'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pdf-line-apply'))).onPressed, isNull);
  });

  testWidgets('a line can be removed and put back', (tester) async {
    final cubit = await open(tester);
    final line = lineWith(cubit, 'Hello');
    await tester.tap(find.byKey(ValueKey('pdf-line-0-$line')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-line-delete')));
    await tester.pumpAndSettle();
    expect(cubit.state.edits.textOf(0, line), '');

    await tester.tap(find.byKey(ValueKey('pdf-line-0-$line')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-line-restore')));
    await tester.pumpAndSettle();
    expect(cubit.state.edits.textOf(0, line), isNull);
  });

  testWidgets('Add text: tap the page, type, choose the look; the text can be changed and removed', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-mode-add')));
    await tester.pumpAndSettle();
    expect(find.text('Tap the page where the new text should go.'), findsOneWidget);
    expect(find.byKey(ValueKey('pdf-line-0-${lineWith(cubit, 'Hello')}')), findsNothing, reason: 'lines are not in the way while adding');

    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('pdf-page-0'))) + const Offset(120, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pdf-add-field')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pdf-add-apply'))).onPressed, isNull, reason: 'nothing typed yet');

    await tester.enterText(find.byKey(const ValueKey('pdf-add-field')), 'Approved');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-add-bold')));
    await tester.tap(find.byKey(const ValueKey('pdf-add-color-c62828')));
    await tester.tap(find.byKey(const ValueKey('pdf-add-apply')));
    await tester.pumpAndSettle();

    expect(cubit.state.edits.added.length, 1);
    final a = cubit.state.edits.added.single;
    expect(a.text, 'Approved');
    expect(a.bold, isTrue);
    expect(a.rgb, 0xC62828);
    expect(a.page, 0);
    expect(a.x, closeTo(120 / (tester.getSize(find.byKey(const ValueKey('pdf-page-0'))).width), 0.01));
    expect(find.text('Approved'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pdf-added-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-add-field')), 'Approved by me');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-add-apply')));
    await tester.pumpAndSettle();
    expect(cubit.state.edits.added.single.text, 'Approved by me');

    await tester.tap(find.byKey(const ValueKey('pdf-added-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pdf-add-delete')));
    await tester.pumpAndSettle();
    expect(cubit.state.edits.added, isEmpty);
  });

  testWidgets('the next text keeps the look of the last one', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-mode-add')));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('pdf-page-0'))) + const Offset(100, 200));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-add-field')), 'One');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-add-italic')));
    await tester.tap(find.byKey(const ValueKey('pdf-add-apply')));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('pdf-page-0'))) + const Offset(100, 400));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byKey(const ValueKey('pdf-add-italic'))).selected, isTrue);
  });

  testWidgets('a page with no text explains that text can still be added', (tester) async {
    final cubit = await open(tester);
    final scanned = cubit.state.pages.indexWhere((p) => p.lines.isEmpty);
    expect(scanned, greaterThanOrEqualTo(0), reason: 'the fixture has an image-only page');
    for (var i = 0; i < scanned; i++) {
      await tester.fling(find.byKey(const ValueKey('pdf-pages')), const Offset(-500, 0), 2000);
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('pdf-page-note')), findsOneWidget);
    expect(find.textContaining('Use Add text'), findsOneWidget);
  });

  testWidgets('Save writes the edited PDF, which keeps the other text and shows the changes', (tester) async {
    final cubit = await open(tester);
    final line = lineWith(cubit, 'Hello');
    await tester.tap(find.byKey(ValueKey('pdf-line-0-$line')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-line-field')), 'Goodbye World');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-line-apply')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pdf-save')));
    for (var i = 0; i < 100 && find.byKey(const ValueKey('save-share')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('save-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-files')), findsOneWidget);

    final out = File('${work.path}/text_edit/search_text_edited.pdf');
    expect(out.existsSync(), isTrue);
    final texts = analyzePdfForEditing(out.readAsBytesSync())[0].lines.map((l) => l.text).toList();
    expect(texts, contains('Goodbye World'));
    expect(texts.any((t) => t.contains('Hello')), isFalse);
    expect(texts.any((t) => t.contains('Quarterly report')), isTrue);
    expect(cubit.state.modified, isFalse);
  });

  testWidgets('a file that is not a PDF shows a clear message', (tester) async {
    final bad = File('${work.path}/bad.pdf')..writeAsStringSync('not a pdf');
    await open(tester, path: bad.path);
    expect(find.byKey(const ValueKey('pdf-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('pdf-pages')), findsNothing);
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/text_edit/docx/docx_document.dart';
import 'package:scanvault/features/text_edit/docx/docx_edit_cubit.dart';
import 'package:scanvault/features/text_edit/docx/docx_edit_page.dart';

void main() {
  late Directory work;
  setUp(() => work = Directory.systemTemp.createTempSync('docx_edit_page'));
  tearDown(() => work.deleteSync(recursive: true));

  Future<DocxEditCubit> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DocxEditPage(path: 'test/fixtures/text_edit/sample.docx', workDir: () async => work),
      ),
    );
    for (var i = 0; i < 40 && find.byKey(const ValueKey('docx-paper')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    return tester.element(find.byKey(const ValueKey('docx-paper'))).read<DocxEditCubit>();
  }

  ParaBlock paragraph(DocxEditCubit cubit, String startsWith) {
    ParaBlock? found;
    void walk(List<DocBlock> blocks) {
      for (final b in blocks) {
        if (b is ParaBlock && b.text.startsWith(startsWith)) found ??= b;
        if (b is TableBlock) {
          for (final row in b.rows) {
            for (final cell in row) {
              walk(cell);
            }
          }
        }
      }
    }

    walk(cubit.state.blocks);
    return found!;
  }

  testWidgets('the document is shown as paper, and Save is the way out of unsaved changes', (tester) async {
    final cubit = await open(tester);
    expect(find.text('Quarterly Report'), findsOneWidget);
    expect(find.textContaining('Fox Ltd'), findsOneWidget);
    expect(find.text('Step one'), findsOneWidget);
    expect(cubit.state.modified, isFalse);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('docx-undo'))).onPressed, isNull);
  });

  testWidgets('tap a paragraph, change its words, press Done: the document changes and can be undone', (tester) async {
    final cubit = await open(tester);
    final para = paragraph(cubit, 'The quick');
    await tester.tap(find.byKey(ValueKey('docx-para-${para.index}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('docx-paragraph-field')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('docx-paragraph-field')), 'The quick brown cat jumps over the lazy dog.');
    await tester.tap(find.byKey(const ValueKey('para-done')));
    await tester.pumpAndSettle();

    final after = paragraph(cubit, 'The quick');
    expect(after.text, 'The quick brown cat jumps over the lazy dog.');
    expect(after.spans.firstWhere((s) => s.text == 'brown').bold, isTrue, reason: 'the look of the other words is kept');
    expect(cubit.state.modified, isTrue);

    await tester.tap(find.byKey(const ValueKey('docx-undo')));
    await tester.pumpAndSettle();
    expect(paragraph(cubit, 'The quick').text, 'The quick brown fox jumps over the lazy dog.');
  });

  testWidgets('bold with nothing selected formats the whole paragraph; alignment changes', (tester) async {
    final cubit = await open(tester);
    final para = paragraph(cubit, 'Last paragraph');
    await tester.ensureVisible(find.byKey(ValueKey('docx-para-${para.index}')));
    await tester.tap(find.byKey(ValueKey('docx-para-${para.index}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fmt-bold')));
    await tester.pumpAndSettle();
    expect(paragraph(cubit, 'Last paragraph').spans.every((s) => s.bold), isTrue);
    await tester.tap(find.byKey(const ValueKey('align-center')));
    await tester.pumpAndSettle();
    expect(paragraph(cubit, 'Last paragraph').align, 'center');
    await tester.tap(find.byKey(const ValueKey('fmt-bold')));
    await tester.pumpAndSettle();
    expect(paragraph(cubit, 'Last paragraph').spans.any((s) => s.bold), isFalse, reason: 'tapping again turns it off');
  });

  testWidgets('typing and formatting in one go: the typed words are what gets formatted', (tester) async {
    final cubit = await open(tester);
    final para = paragraph(cubit, 'Last paragraph');
    await tester.ensureVisible(find.byKey(ValueKey('docx-para-${para.index}')));
    await tester.tap(find.byKey(ValueKey('docx-para-${para.index}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('docx-paragraph-field')), 'Typed first');
    await tester.tap(find.byKey(const ValueKey('fmt-italic')));
    await tester.pumpAndSettle();
    final after = paragraph(cubit, 'Typed first');
    expect(after.spans.every((s) => s.italic), isTrue);
  });

  testWidgets('add a paragraph below opens it for typing, and delete removes one', (tester) async {
    final cubit = await open(tester);
    final para = paragraph(cubit, 'First bullet');
    final count = cubit.document.paragraphCount;
    await tester.tap(find.byKey(ValueKey('docx-para-${para.index}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('para-add')));
    await tester.pumpAndSettle();
    expect(cubit.document.paragraphCount, count + 1);
    expect(find.byKey(const ValueKey('docx-paragraph-field')), findsOneWidget, reason: 'the new paragraph is open for typing');
    await tester.enterText(find.byKey(const ValueKey('docx-paragraph-field')), 'Third bullet');
    await tester.tap(find.byKey(const ValueKey('para-done')));
    await tester.pumpAndSettle();
    final added = paragraph(cubit, 'Third bullet');
    expect(added.listLabel, '\u2022');

    await tester.tap(find.byKey(ValueKey('docx-para-${added.index}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('para-delete')));
    await tester.pumpAndSettle();
    expect(cubit.document.paragraphCount, count);
    expect(find.text('Third bullet'), findsNothing);
    expect(paragraph(cubit, 'Second bullet').text, startsWith('Second bullet'), reason: 'nothing else was changed by the delete');
  });

  testWidgets('find shows the count and steps through, replace all changes every match', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(const ValueKey('docx-find-button')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('docx-find-field')), 'fox');
    await tester.pumpAndSettle();
    expect(find.text('1 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('docx-find-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 4'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('docx-find-prev')));
    await tester.tap(find.byKey(const ValueKey('docx-find-prev')));
    await tester.pumpAndSettle();
    expect(find.text('4 of 4'), findsOneWidget, reason: 'it wraps around');

    await tester.tap(find.byKey(const ValueKey('docx-find-options')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('docx-replace-field')), 'wolf');
    await tester.tap(find.byKey(const ValueKey('docx-match-case')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget, reason: 'only the two lower case matches');
    await tester.tap(find.byKey(const ValueKey('docx-replace-all')));
    await tester.pumpAndSettle();
    expect(paragraph(cubit, 'The quick').text, 'The quick brown wolf jumps over the lazy dog.');
    expect(paragraph(cubit, 'Centered').text, 'Centered line about the Fox', reason: 'the capital Fox was left alone with match case on');
    expect(cubit.state.modified, isTrue);

    await tester.tap(find.byKey(const ValueKey('docx-find-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('docx-find-field')), findsNothing);
  });

  testWidgets('Save writes the changed file and offers to share or save it', (tester) async {
    final cubit = await open(tester);
    cubit.commitText(paragraph(cubit, 'Last paragraph').index, 'Final words');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('docx-save')));
    for (var i = 0; i < 20 && find.byKey(const ValueKey('save-share')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('save-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('save-files')), findsOneWidget);
    final saved = File('${work.path}/text_edit/sample_edited.docx');
    expect(saved.existsSync(), isTrue);
    expect(DocxDocument.open(saved.readAsBytesSync()).paragraphText(cubit.document.paragraphCount - 1), 'Final words');
    expect(cubit.state.modified, isFalse);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    final cubit = await open(tester);
    cubit.commitText(paragraph(cubit, 'Last paragraph').index, 'Changed');
    await tester.pump();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsNothing);
  });

  testWidgets('a file that is not a Word document shows why', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DocxEditPage(path: 'test/fixtures/office/basic.xlsx', workDir: () async => work),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('not a valid .docx'), findsWidgets);
  });
}

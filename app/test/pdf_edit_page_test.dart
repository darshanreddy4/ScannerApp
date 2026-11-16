import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/reader/data/pdf_text_edit.dart';
import 'package:doculoom/features/text_edit/pdf/pdf_edit_cubit.dart';
import 'package:doculoom/features/text_edit/pdf/pdf_edit_page.dart';
import 'package:doculoom/features/text_edit/pdf/pdf_page_renderer.dart';
import 'package:doculoom/features/text_edit/pdf/scan_text.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:image/image.dart' as img;

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

  Future<PdfEditCubit> open(WidgetTester tester, {String path = _fixture, ScanReader? scanReader}) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PdfEditPage(path: path, workDir: () async => work, openRenderer: (_) async => _FakeRenderer(), scanReader: scanReader),
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

  testWidgets('letters the built-in fonts cannot show are allowed, with a note that they are placed as a picture', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(ValueKey('pdf-line-0-${lineWith(cubit, 'Hello')}')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-line-field')), 'Hello \u0928\u092E\u0938\u094D\u0924\u0947');
    await tester.pump();
    expect(find.textContaining('placed as a picture'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('pdf-line-apply'))).onPressed, isNotNull);
  });

  testWidgets('a line retyped in Hindi becomes a picture where the old line was, and undo brings the old line back', (tester) async {
    final cubit = await open(tester);
    final line = lineWith(cubit, 'Hello');
    await tester.tap(find.byKey(ValueKey('pdf-line-0-$line')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-line-field')), '\u0928\u092E\u0938\u094D\u0924\u0947');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-line-apply')));
    for (var i = 0; i < 60 && cubit.state.edits.pictures.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(cubit.state.edits.pictures, hasLength(1));
    expect(cubit.state.edits.textOf(0, line), '', reason: 'the old line is taken out');
    final pic = cubit.state.edits.pictures.single;
    final box = cubit.state.pages[0].lines[line].box;
    expect(pic.x, closeTo(box.left, 0.01));
    expect(pic.page, 0);

    cubit.undo();
    expect(cubit.state.edits.pictures, isEmpty);
    expect(cubit.state.edits.textOf(0, line), isNull);
  });

  testWidgets('added text in Hindi is placed as a picture', (tester) async {
    final cubit = await open(tester);
    await tester.tap(find.byKey(const ValueKey('pdf-mode-add')));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('pdf-page-0'))) + const Offset(120, 300));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pdf-add-field')), '\u0928\u092E\u0938\u094D\u0924\u0947');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pdf-add-apply')));
    for (var i = 0; i < 60 && cubit.state.edits.pictures.isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(cubit.state.edits.pictures, hasLength(1));
    expect(cubit.state.edits.added, isEmpty);
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

  group('drawings, pictures and moving', () {
    Offset pageTopLeft(WidgetTester tester) => tester.getTopLeft(find.byKey(const ValueKey('pdf-page-0')));

    testWidgets('Mark: drag to draw a highlight, a box or a line; a tap draws nothing; a drawing can be recoloured and removed', (tester) async {
      final cubit = await open(tester);
      await tester.tap(find.byKey(const ValueKey('pdf-mode-mark')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Drag on the page to draw'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-mark-highlight')), findsOneWidget);

      final size = tester.getSize(find.byKey(const ValueKey('pdf-page-0')));
      final origin = pageTopLeft(tester);
      await tester.dragFrom(origin + Offset(size.width * 0.2, size.height * 0.2), Offset(size.width * 0.5, size.height * 0.05));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks, hasLength(1));
      var m = cubit.state.edits.marks.single;
      expect(m.kind, 'highlight');
      expect(m.rgb, 0xFFEB3B);
      expect(m.x0, closeTo(0.2, 0.02));
      expect(m.x1, closeTo(0.7, 0.03));

      await tester.tapAt(origin + Offset(size.width * 0.3, size.height * 0.6));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks, hasLength(1), reason: 'a tap on empty page draws nothing');

      await tester.tap(find.byKey(const ValueKey('pdf-mark-box')));
      await tester.tap(find.byKey(const ValueKey('pdf-mark-color-1565c0')));
      await tester.pump();
      await tester.dragFrom(origin + Offset(size.width * 0.2, size.height * 0.4), Offset(size.width * 0.3, size.height * 0.2));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks, hasLength(2));
      m = cubit.state.edits.marks.last;
      expect(m.kind, 'box');
      expect(m.rgb, 0x1565C0);

      await tester.tap(find.byKey(const ValueKey('pdf-mark-line')));
      await tester.pump();
      await tester.dragFrom(origin + Offset(size.width * 0.1, size.height * 0.8), Offset(size.width * 0.6, 0));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks.last.kind, 'line');
      expect(cubit.state.edits.marks.last.rgb, 0xC62828);

      // Tap inside the highlight: change its colour.
      await tester.tapAt(origin + Offset(size.width * 0.4, size.height * 0.22));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-marksheet-color-2e7d32')));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks.first.rgb, 0x2E7D32);
      expect(cubit.state.edits.marks, hasLength(3));

      await tester.tapAt(origin + Offset(size.width * 0.4, size.height * 0.22));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-mark-delete')));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks, hasLength(2));
      expect(cubit.state.edits.marks.any((x) => x.kind == 'highlight'), isFalse);

      await tester.tap(find.byKey(const ValueKey('pdf-undo')));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks, hasLength(3), reason: 'undo brings the drawing back');
    });

    testWidgets('a picture can be resized, moved by dragging and removed', (tester) async {
      final cubit = await open(tester);
      final info = cubit.state.pages[0];
      cubit.addPicture(AddedPicture(page: 0, x: 0.1, y: 0.1, w: 0.3, bytes: _tinyPng, aspect: 1));
      await tester.tap(find.byKey(const ValueKey('pdf-mode-picture')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tap the page where the picture should go'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-picture-0')), findsOneWidget);
      expect(info.aspect, greaterThan(0));

      await tester.drag(find.byKey(const ValueKey('pdf-picture-0')), const Offset(60, 80));
      await tester.pumpAndSettle();
      final p = cubit.state.edits.pictures.single;
      final size = tester.getSize(find.byKey(const ValueKey('pdf-page-0')));
      expect(p.x, closeTo(0.1 + 60 / size.width, 0.02));
      expect(p.y, closeTo(0.1 + 80 / size.height, 0.02));
      expect(p.w, 0.3);

      await tester.tap(find.byKey(const ValueKey('pdf-picture-0')));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const ValueKey('pdf-picture-size')), const Offset(100, 0));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-picture-apply')));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.pictures.single.w, greaterThan(0.3));

      await tester.tap(find.byKey(const ValueKey('pdf-picture-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-picture-delete')));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.pictures, isEmpty);
    });

    testWidgets('added text can be dragged to a new place without opening its sheet', (tester) async {
      final cubit = await open(tester);
      cubit.addText(const AddedText(page: 0, x: 0.2, y: 0.5, text: 'Moveme', sizePt: 14));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byKey(const ValueKey('pdf-page-0')));
      await tester.drag(find.byKey(const ValueKey('pdf-added-0')), Offset(size.width * 0.3, 40));
      await tester.pumpAndSettle();
      final a = cubit.state.edits.added.single;
      expect(a.x, closeTo(0.5, 0.03));
      expect(a.y, closeTo(0.5 + 40 / size.height, 0.02));
      expect(find.byKey(const ValueKey('pdf-add-field')), findsNothing, reason: 'a drag is not a tap');
    });

    testWidgets('Save writes the drawings and the picture into the PDF', (tester) async {
      final cubit = await open(tester);
      cubit.addMark(const AddedMark(page: 0, kind: 'cover', x0: 0.1, y0: 0.1, x1: 0.4, y1: 0.2, rgb: 0xFFFFFF));
      cubit.addPicture(AddedPicture(page: 0, x: 0.5, y: 0.5, w: 0.2, bytes: _tinyPng, aspect: 1));
      final path = await tester.runAsync(cubit.export);
      expect(path, isNotNull);
      final bytes = File(path!).readAsBytesSync();
      expect(String.fromCharCodes(bytes), contains('SVI1'));
      expect(analyzePdfForEditing(bytes)[0].lines.map((l) => l.text), contains('Hello World'));
    });
  });

  group('text in scans', () {
    Future<void> goToScan(WidgetTester tester, PdfEditCubit cubit) async {
      final scanned = cubit.state.pages.indexWhere((p) => p.lines.isEmpty);
      for (var i = 0; i < scanned; i++) {
        await tester.fling(find.byKey(const ValueKey('pdf-pages')), const Offset(-500, 0), 2000);
        await tester.pumpAndSettle();
      }
    }

    final found = [
      const ScanLine(text: 'Total due 450', left: 0.1, top: 0.2, right: 0.6, bottom: 0.24, background: 0xF5F0E0, ink: 0x202020),
      const ScanLine(text: 'Thank you', left: 0.1, top: 0.4, right: 0.4, bottom: 0.43),
    ];

    testWidgets('find the text of a scanned page, retype a line: the old writing is covered and the new words go over it; undo is one step', (tester) async {
      PdfEditCubit? c;
      OcrScript? asked;
      final cubit = await open(
        tester,
        scanReader: (png, script) async {
          asked = script;
          return found;
        },
      );
      c = cubit;
      await goToScan(tester, c);
      expect(find.byKey(const ValueKey('pdf-scan-find')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-scan-find')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-scan-latin')));
      for (var i = 0; i < 40 && find.byKey(ValueKey('pdf-scan-${c.state.pages.indexWhere((p) => p.lines.isEmpty)}-0')).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      expect(asked, OcrScript.latin);
      final page = c.state.pages.indexWhere((p) => p.lines.isEmpty);
      expect(find.byKey(ValueKey('pdf-scan-$page-0')), findsOneWidget);
      expect(find.byKey(ValueKey('pdf-scan-$page-1')), findsOneWidget);
      expect(find.textContaining('Tap a framed line'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-scan-find')), findsNothing);

      await tester.tap(find.byKey(ValueKey('pdf-scan-$page-0')));
      await tester.pumpAndSettle();
      expect(find.text('Total due 450'), findsWidgets, reason: 'the sheet shows what was read');
      await tester.enterText(find.byKey(const ValueKey('pdf-line-field')), 'Total due 540');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('pdf-line-apply')));
      await tester.pumpAndSettle();

      final e = c.state.edits;
      expect(e.marks, hasLength(1));
      expect(e.marks.single.kind, 'cover');
      expect(e.marks.single.rgb, 0xF5F0E0, reason: 'the colour of the paper');
      expect(e.marks.single.page, page);
      expect(e.added, hasLength(1));
      expect(e.added.single.text, 'Total due 540');
      expect(e.added.single.rgb, 0x202020, reason: 'the colour of the writing');
      expect(e.added.single.x, closeTo(0.1, 1e-9));
      expect(find.byKey(ValueKey('pdf-scan-$page-0')), findsNothing, reason: 'a retyped line is not offered again');
      expect(find.byKey(ValueKey('pdf-scan-$page-1')), findsOneWidget);

      c.undo();
      await tester.pumpAndSettle();
      expect(c.state.edits.marks, isEmpty);
      expect(c.state.edits.added, isEmpty);
      expect(find.byKey(ValueKey('pdf-scan-$page-0')), findsOneWidget);
    });

    testWidgets('a scanned line can be removed', (tester) async {
      final cubit = await open(tester, scanReader: (png, script) async => found);
      await goToScan(tester, cubit);
      await tester.tap(find.byKey(const ValueKey('pdf-scan-find')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-scan-devanagari')));
      await tester.pumpAndSettle();
      final page = cubit.state.pages.indexWhere((p) => p.lines.isEmpty);
      await tester.tap(find.byKey(ValueKey('pdf-scan-$page-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-line-delete')));
      await tester.pumpAndSettle();
      expect(cubit.state.edits.marks, hasLength(1));
      expect(cubit.state.edits.added, isEmpty);
      expect(cubit.state.edits.marks.single.rgb, 0xFFFFFF);
    });

    testWidgets('a page where nothing is found says so and offers the search again', (tester) async {
      final cubit = await open(tester, scanReader: (png, script) async => const []);
      await goToScan(tester, cubit);
      await tester.tap(find.byKey(const ValueKey('pdf-scan-find')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-scan-latin')));
      await tester.pumpAndSettle();
      expect(find.text('No text was found on this page.'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-scan-find')), findsOneWidget);
    });

    testWidgets('a failure while reading the page is shown and the page can be tried again', (tester) async {
      final cubit = await open(tester, scanReader: (png, script) async => throw StateError('no engine'));
      await goToScan(tester, cubit);
      await tester.tap(find.byKey(const ValueKey('pdf-scan-find')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pdf-scan-latin')));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be read'), findsWidgets);
      expect(find.byKey(const ValueKey('pdf-scan-find')), findsOneWidget);
    });
  });

  group('colours of a scanned line', () {
    test('the paper is the colour around the line and the writing is the colour that differs most inside it', () {
      final image = img.Image(width: 400, height: 100)..clear(img.ColorRgb8(245, 240, 224));
      for (var y = 40; y < 60; y++) {
        for (var x = 100; x < 300; x += 4) {
          for (var dx = 0; dx < 2; dx++) {
            image.setPixelRgb(x + dx, y, 180, 20, 20);
          }
        }
      }
      final c = sampleLineColors(image, 95, 36, 305, 64);
      expect(c.background, 0xF5F0E0);
      expect((c.ink >> 16) & 255, greaterThan(150));
      expect(c.ink & 255, lessThan(60));
    });

    test('faint writing gets black on light paper and white on dark paper', () {
      final light = img.Image(width: 200, height: 60)..clear(img.ColorRgb8(250, 250, 250));
      expect(sampleLineColors(light, 20, 20, 180, 40).ink, 0x000000);
      final dark = img.Image(width: 200, height: 60)..clear(img.ColorRgb8(20, 20, 30));
      expect(sampleLineColors(dark, 20, 20, 180, 40).ink, 0xFFFFFF);
    });

    test('boxes at the edge of the picture do not fail', () {
      final image = img.Image(width: 100, height: 50)..clear(img.ColorRgb8(255, 255, 255));
      final c = sampleLineColors(image, -5, -5, 120, 60);
      expect(c.background, 0xFFFFFF);
    });
  });
}

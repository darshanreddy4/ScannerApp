import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/pdf_compare/domain/text_compare.dart';
import 'package:doculoom/features/pdf_compare/presentation/pdf_compare_cubit.dart';
import 'package:doculoom/features/pdf_compare/presentation/pdf_compare_page.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_picture_pages.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_security.dart' show WrongPasswordException;
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/tools/presentation/tools_view.dart';

import 'support/ocr_tool_fakes.dart';
import 'support/pdf_ui_fakes.dart';

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

/// Pages drawn as lines of ink: each page is a list of (x, y, width, height) boxes on a white 600 x 800 sheet.
Uint8List sheet(List<(int, int, int, int)> ink) {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (final (x, y, w, h) in ink) {
    img.fillRect(image, x1: x, y1: y, x2: x + w, y2: y + h, color: img.ColorRgb8(0, 0, 0));
  }
  return Uint8List.fromList(img.encodePng(image));
}

const _lines = [(60, 100, 400, 12), (60, 130, 380, 12), (60, 160, 420, 12)];

/// A PDF that is a list of page pictures.
class _Pages implements PdfPicturePages {
  _Pages(this.pages);
  final List<Uint8List> pages;
  var closed = false;
  final rendered = <int>[];
  Completer<void>? hold;

  @override
  Future<int> open(String path) async => pages.length;

  @override
  Future<Uint8List> render(int page, {required int width, required bool png}) async {
    rendered.add(page);
    if (hold != null) await hold!.future;
    return pages[page];
  }

  @override
  Future<void> close() async => closed = true;
}

PageWords words(String text, {double top = 0.1}) {
  final out = <PageWord>[];
  var x = 0.05;
  for (final w in text.split(' ')) {
    out.add(PageWord(w, TextRect(x, top, x + w.length * 0.01, top + 0.02)));
    x += w.length * 0.01 + 0.01;
  }
  return PageWords(words: out);
}

void main() {
  late Directory dir;
  late String fileA, fileB;
  late FakeTextReader reader;

  setUp(() async {
    dir = tempDir();
    fileA = (File('${dir.path}/contract_v1.pdf')..writeAsStringSync('A')).path;
    fileB = (File('${dir.path}/contract_v2.pdf')..writeAsStringSync('B')).path;
    reader = FakeTextReader({});
    await sl.reset();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('page pairs follow the words', () {
    test('an inserted page is a page of its own and the pages after it still pair up', () {
      final a = [words('alpha beta gamma delta'), words('epsilon zeta eta theta'), words('iota kappa lambda mu')];
      final b = [a[0], words('A completely new page of text'), a[1], a[2]];
      expect(compareText(a, b).pagePairs, [(0, 0), (null, 1), (1, 2), (2, 3)]);
    });

    test('a removed page', () {
      final a = [words('alpha beta gamma delta'), words('epsilon zeta eta theta'), words('iota kappa lambda mu')];
      expect(compareText(a, [a[0], a[2]]).pagePairs, [(0, 0), (1, null), (2, 1)]);
    });

    test('pages with no words are paired by number', () {
      const empty = PageWords(words: []);
      expect(compareText(const [empty, empty, empty], const [empty, empty]).pagePairs, [(0, 0), (1, 1), (2, null)]);
    });

    test('no pages at all', () {
      expect(compareText(const [], const []).pagePairs, isEmpty);
    });
  });

  group('comparing two files', () {
    late List<PdfPicturePages> renderers;

    PdfCompareCubit make({List<PageWords>? a, List<PageWords>? b, int maxPages = 60, Object? readError}) {
      return PdfCompareCubit(
        engine: reader,
        outputDir: () async => dir,
        pdfPages: () => renderers.removeAt(0),
        readWords: (bytes, max) async {
          if (readError != null) throw readError;
          return String.fromCharCodes(bytes) == 'A' ? (a ?? const []) : (b ?? const []);
        },
        maxPages: maxPages,
        now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    }

    Future<PdfCompareCubit> run(PdfCompareCubit c) async {
      c.setOriginal(fileA);
      c.setRevised(fileB);
      await c.compare();
      return c;
    }

    test('the same words and the same look: the files are the same, and no page is kept', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(a: [words('Pay within thirty days')], b: [words('Pay within thirty days')]));
      final r = c.state.result!;
      expect(c.state.status, CompareStatus.done);
      expect(r.identical, isTrue);
      expect(r.pages, isEmpty);
      expect((r.pagesA, r.pagesB, r.pairs), (1, 1, 1));
      expect(renderers, isEmpty);
      await c.close();
    });

    test('a changed word is listed and its place is marked on both pages', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(a: [words('Pay within thirty days')], b: [words('Pay within fourteen days')]));
      final r = c.state.result!;
      expect(r.text.changes.single.plain, 'Pay within [-thirty-] {+fourteen+} days');
      final page = r.pages.single;
      expect((page.pageA, page.pageB), (0, 0));
      expect(page.removed.length, 1);
      expect(page.added.length, 1);
      expect(page.imageA, isNotNull);
      expect(page.imageB, isNotNull);
      expect(page.changed, isTrue);
      expect(r.identical, isFalse);
      await c.close();
    });

    test('a change that is only in how the page looks is found, where it is', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([
          sheet([..._lines, (60, 500, 300, 12)]),
        ]),
      ];
      final c = await run(make(a: [words('Same words')], b: [words('Same words')]));
      final r = c.state.result!;
      expect(r.text.identical, isTrue);
      expect(r.pages.single.visual.length, 1);
      expect(r.pages.single.visual.single.top, closeTo(500 / 800, 0.03));
      expect(r.pages.single.similarity, lessThan(1));
      await c.close();
    });

    test('a look change right under the changed words is not marked twice', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([
          sheet([..._lines, (66, 76, 36, 16)]),
        ]),
      ];
      // The words box covers the area around y = 0.1 (80 of 800) so the picture difference is the same change.
      final c = await run(make(a: [words('Total ten', top: 0.095)], b: [words('Total twenty', top: 0.095)]));
      final page = c.state.result!.pages.single;
      expect(page.added, isNotEmpty);
      expect(page.visual, isEmpty);
      await c.close();
    });

    test('a page put in the middle is a new page, and the others are not reported', () async {
      final a = [words('alpha beta gamma delta'), words('epsilon zeta eta theta')];
      final b = [a[0], words('A completely new page of text'), a[1]];
      renderers = [
        _Pages([
          sheet(_lines),
          sheet([(60, 100, 200, 12)]),
        ]),
        _Pages([
          sheet(_lines),
          sheet([(60, 300, 100, 12)]),
          sheet([(60, 100, 200, 12)]),
        ]),
      ];
      final c = await run(make(a: a, b: b));
      final r = c.state.result!;
      expect(r.pairs, 3);
      final page = r.pages.single;
      expect(page.onlyInRevised, isTrue);
      expect(page.pageB, 1);
      expect(page.imageB, isNotNull);
      expect(page.imageA, isNull);
      await c.close();
    });

    test('a page taken out is a page of the original only', () async {
      final a = [words('alpha beta gamma delta'), words('epsilon zeta eta theta')];
      renderers = [
        _Pages([sheet(_lines), sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(a: a, b: [a[0]]));
      final page = c.state.result!.pages.single;
      expect(page.onlyInOriginal, isTrue);
      expect(page.pageA, 1);
      expect(page.imageA, isNotNull);
      await c.close();
    });

    test('pages that are pictures are read with the text reader, then compared by words', () async {
      reader.texts.addAll({'a0.jpg': 'Pay within thirty days', 'b0.jpg': 'Pay within fourteen days'});
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make());
      final r = c.state.result!;
      expect(reader.reads.map((x) => x.path.split('/').last), ['a0.jpg', 'b0.jpg']);
      expect(r.ocrPages, 2);
      expect(r.text.changes.single.plain, 'Pay within [-thirty-] {+fourteen+} days');
      expect(r.noText, isFalse);
      expect(
        Directory('${dir.path}/pdf_compare').existsSync() ? Directory('${dir.path}/pdf_compare').listSync(recursive: true).whereType<File>() : <File>[],
        isEmpty,
      );
      await c.close();
    });

    test('with reading pictures turned off only the look is compared, and the person is told', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([
          sheet([..._lines, (60, 500, 300, 12)]),
        ]),
      ];
      final c = make()..setUseOcr(false);
      await run(c);
      expect(reader.reads, isEmpty);
      expect(c.state.result!.noText, isTrue);
      expect(c.state.notes.single, contains('pictures'));
      expect(c.state.result!.pages.single.visual, isNotEmpty);
      await c.close();
    });

    test('a file with a password stops with a message that says what to do', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(readError: const WrongPasswordException()));
      expect(c.state.failure, isA<PasswordFailure>());
      expect(c.state.status, CompareStatus.idle);
      expect(c.state.result, isNull);
      await c.close();
    });

    test('a file that is not a PDF fails with a plain message', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = make(a: [words('x')], b: [words('x')]);
      c.setOriginal('${dir.path}/missing.pdf');
      c.setRevised(fileB);
      await c.compare();
      expect(c.state.failure!.message, contains('could not be compared'));
      expect(c.state.status, CompareStatus.idle);
      await c.close();
    });

    test('only the first pages of a long file are compared, and the person is told', () async {
      final many = List.generate(5, (_) => sheet(_lines));
      renderers = [_Pages(many), _Pages(many)];
      final c = await run(
        make(
          a: [for (var i = 0; i < 5; i++) words('page number $i text here')],
          b: [for (var i = 0; i < 5; i++) words('page number $i text here')],
          maxPages: 2,
        ),
      );
      expect(c.state.result!.pagesA, 2);
      expect(c.state.notes, ['"contract_v1.pdf" has 5 pages; the first 2 were compared.', '"contract_v2.pdf" has 5 pages; the first 2 were compared.']);
      await c.close();
    });

    test('Stop ends the comparison without a result', () async {
      final a = _Pages([sheet(_lines), sheet(_lines)])..hold = Completer<void>();
      renderers = [
        a,
        _Pages([sheet(_lines), sheet(_lines)]),
      ];
      final c = make(a: [words('one two three four'), words('five six seven eight')], b: [words('one two three four'), words('five six seven eight')]);
      c.setOriginal(fileA);
      c.setRevised(fileB);
      final run = c.compare();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.state.comparing, isTrue);
      c.cancel();
      a.hold!.complete();
      await run;
      expect(c.state.status, CompareStatus.idle);
      expect(c.state.result, isNull);
      expect(c.state.notes.single, startsWith('Stopped'));
      expect(a.closed, isTrue);
      await c.close();
    });

    test('files can be swapped, and choosing another file clears the result', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(a: [words('a b c d')], b: [words('a b c e')]));
      expect(c.state.result, isNotNull);
      c.swap();
      expect((c.state.pathA, c.state.pathB), (fileB, fileA));
      expect(c.state.result, isNull);
      c.setRevised(fileA);
      expect(c.state.nameB, 'contract_v1.pdf');
      await c.close();
    });

    test('the list of changes and the marked pages can be saved', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(a: [words('Pay within thirty days')], b: [words('Pay within fourteen days')]));
      final txt = await c.writeChangesText();
      final text = File(txt!).readAsStringSync();
      expect(text, contains('"contract_v1.pdf" (original, 1 pages) and "contract_v2.pdf" (revised, 1 pages)'));
      expect(text, contains('1 change, 1 words removed, 1 words added'));
      expect(text, contains('Pay within [-thirty-] {+fourteen+} days'));
      final pdf = await c.writeReportPdf();
      expect(File(pdf!).readAsBytesSync().take(5), '%PDF-'.codeUnits);
      await c.close();
    });

    test('no marked pages when the pages are all the same', () async {
      renderers = [
        _Pages([sheet(_lines)]),
        _Pages([sheet(_lines)]),
      ];
      final c = await run(make(a: [words('same')], b: [words('same')]));
      expect(await c.writeReportPdf(), isNull);
      await c.close();
    });
  });

  group('the screen', () {
    late FakeShare share;
    late List<PdfPicturePages> renderers;
    late List<String?> picks;

    Future<void> open(
      WidgetTester tester, {
      List<PageWords>? a,
      List<PageWords>? b,
      List<Uint8List>? pagesA,
      List<Uint8List>? pagesB,
      Object? readError,
      double width = 400,
      double height = 2200,
      double scale = 1,
    }) async {
      share = FakeShare();
      sl.registerSingleton<ShareService>(share);
      renderers = [
        _Pages(pagesA ?? [sheet(_lines)]),
        _Pages(pagesB ?? [sheet(_lines)]),
      ];
      picks = [fileA, fileB];
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      final settings = SettingsCubit(_Prefs());
      await tester.runAsync(settings.load);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PdfComparePage(
              engine: reader,
              pdfPages: () => renderers.removeAt(0),
              readWords: (bytes, max) async {
                if (readError != null) throw readError;
                return String.fromCharCodes(bytes) == 'A' ? (a ?? [words('Pay within thirty days')]) : (b ?? [words('Pay within fourteen days')]);
              },
              pickPdf: () async => picks.isEmpty ? null : picks.removeAt(0),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: settings,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
            child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
    }

    Future<void> chooseBoth(WidgetTester tester) async {
      await tapKey(tester, 'compare-original');
      await tester.pumpAndSettle();
      await tapKey(tester, 'compare-revised');
      await tester.pumpAndSettle();
    }

    Future<void> compare(WidgetTester tester) async {
      await chooseBoth(tester);
      await tapKey(tester, 'compare-start');
      await settle(tester);
    }

    testWidgets('it starts by asking for the two files, and Compare waits for both', (tester) async {
      await open(tester);
      expect(find.text('Not chosen'), findsNWidgets(2));
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('compare-start'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('compare-original')));
      await tester.pumpAndSettle();
      expect(find.text('contract_v1.pdf'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('compare-start'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('compare-revised')));
      await tester.pumpAndSettle();
      expect(find.text('contract_v2.pdf'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('compare-start'))).onPressed, isNotNull);
      expect(find.textContaining('never uploaded'), findsOneWidget);
    });

    testWidgets('a cancelled picker changes nothing, and the files can be swapped', (tester) async {
      await open(tester);
      picks = [null];
      await tester.tap(find.byKey(const ValueKey('compare-original')));
      await tester.pumpAndSettle();
      expect(find.text('Not chosen'), findsNWidgets(2));
      picks = [fileA, fileB];
      await chooseBoth(tester);
      await tester.tap(find.byKey(const ValueKey('compare-swap')));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('compare-original-name'))).data, 'contract_v2.pdf');
      expect(tester.widget<Text>(find.byKey(const ValueKey('compare-revised-name'))).data, 'contract_v1.pdf');
    });

    testWidgets('the result says how many changes there are, lists them with the words marked, and shows the pages', (tester) async {
      await open(tester);
      await compare(tester);
      expect(find.text('The two files differ'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('compare-words-line'))).data, 'Words: 1 change, 1 removed, 1 added');
      expect(tester.widget<Text>(find.byKey(const ValueKey('compare-pages-line'))).data, 'Pages that look different: 1 of 1');
      expect(find.byKey(const ValueKey('compare-change-0')), findsOneWidget);
      expect(find.textContaining('thirty', findRichText: true), findsOneWidget);
      expect(find.textContaining('fourteen', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('compare-tab-pages')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compare-page-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('compare-image-1')), findsOneWidget);
      expect(find.text('Words put in'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('compare-side-1')), matching: find.text('Original')));
      await tester.pumpAndSettle();
      expect(find.text('Words taken out'), findsOneWidget);
    });

    testWidgets('a page can be opened full size', (tester) async {
      await open(tester);
      await compare(tester);
      await tester.tap(find.byKey(const ValueKey('compare-tab-pages')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compare-image-1')));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('two files that are the same say so and offer nothing to share', (tester) async {
      await open(tester, a: [words('Same words here')], b: [words('Same words here')]);
      await compare(tester);
      expect(find.text('The two files are the same'), findsOneWidget);
      expect(find.byKey(const ValueKey('compare-tabs')), findsNothing);
      expect(find.byKey(const ValueKey('compare-share-text')), findsNothing);
    });

    testWidgets('while comparing there is progress and a Stop button', (tester) async {
      final held = _Pages([sheet(_lines)])..hold = Completer<void>();
      await open(tester);
      renderers = [
        held,
        _Pages([sheet(_lines)]),
      ];
      await chooseBoth(tester);
      await tester.tap(find.byKey(const ValueKey('compare-start')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      expect(find.byKey(const ValueKey('compare-progress')), findsOneWidget);
      expect(find.byKey(const ValueKey('compare-cancel')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('compare-start'))).onPressed, isNull);
      held.hold!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('compare-progress')), findsNothing);
      expect(find.byKey(const ValueKey('compare-summary')), findsOneWidget);
    });

    testWidgets('the list and the marked pages are shared', (tester) async {
      await open(tester);
      await compare(tester);
      await tester.tap(find.byKey(const ValueKey('compare-share-text')));
      await settle(tester);
      expect(share.single.single.mime, 'text/plain');
      expect(File(share.single.single.path).readAsStringSync(), contains('[-thirty-]'));
      await tester.tap(find.byKey(const ValueKey('compare-share-pdf')));
      await settle(tester);
      expect(share.single.last.mime, 'application/pdf');
      expect(File(share.single.last.path).readAsBytesSync().take(4), '%PDF'.codeUnits);
    });

    testWidgets('a protected file shows what to do', (tester) async {
      await open(tester, readError: const WrongPasswordException());
      await compare(tester);
      expect(find.textContaining('protected by a password'), findsOneWidget);
      expect(find.byKey(const ValueKey('compare-summary')), findsNothing);
    });

    testWidgets('a page that exists in one file only is called new or removed', (tester) async {
      final a = [words('alpha beta gamma delta')];
      final b = [a[0], words('A completely new page of text')];
      await open(tester, a: a, b: b, pagesA: [sheet(_lines)], pagesB: [sheet(_lines), sheet(_lines)]);
      await compare(tester);
      await tester.tap(find.byKey(const ValueKey('compare-tab-pages')));
      await tester.pumpAndSettle();
      expect(find.text('Revised page 2 (new)'), findsOneWidget);
    });

    testWidgets('a small phone with large text does not overflow', (tester) async {
      await open(tester, width: 320, height: 568, scale: 1.4);
      await compare(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('compare-tab-pages')), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compare-tab-pages')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the Tools tab', () {
    testWidgets('Compare two PDFs is offered and opens the tool', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: ToolsView()),
          ),
          GoRoute(
            path: '/compare-pdf',
            builder: (_, _) => const Scaffold(body: Text('COMPARE')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Compare two PDFs'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.text('Compare two PDFs'));
      await tester.pumpAndSettle();
      expect(find.text('COMPARE'), findsOneWidget);
    });
  });
}

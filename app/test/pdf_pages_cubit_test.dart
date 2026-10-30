import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_pages.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_pages_cubit.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_pages_page.dart';

class _Service implements PdfPageService {
  _Service(this.pages, {this.openFailure});
  final List<String> pages;
  final Failure? openFailure;
  List<PartRequest> lastParts = const [];
  Map<int, int> lastRotations = const {};
  PageMarks lastMarks = const PageMarks();
  Failure? buildFailure;

  @override
  Future<Result<OpenedPdf>> open(String path) async => openFailure != null ? Err(openFailure!) : Ok(OpenedPdf(name: 'Bank statement 2025', pages: pages));

  @override
  Future<Result<List<PdfPart>>> build({
    required OpenedPdf source,
    required List<PartRequest> parts,
    required Map<int, int> rotations,
    required PageMarks marks,
    required String outputDir,
    void Function(int done, int total)? onProgress,
  }) async {
    lastParts = parts;
    lastRotations = rotations;
    lastMarks = marks;
    if (buildFailure != null) return Err(buildFailure!);
    onProgress?.call(1, 1);
    return Ok([for (final r in parts) PdfPart(path: p.join(outputDir, r.fileName), name: r.fileName, pages: r.pages.length, bytes: 20 * 1024)]);
  }
}

void main() {
  late Directory dir;
  late _Service service;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_pgc');
    final pages = <String>[];
    for (var i = 0; i < 6; i++) {
      final path = p.join(dir.path, 'pg$i.jpg');
      File(path).writeAsBytesSync(img.encodeJpg(img.Image(width: 60, height: 80, numChannels: 3), quality: 50));
      pages.add(path);
    }
    service = _Service(pages);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  PdfPagesCubit make() => PdfPagesCubit(service: service, outputDir: () async => dir, now: () => DateTime.fromMillisecondsSinceEpoch(1000));

  Future<PdfPagesCubit> opened() async {
    final c = make();
    await c.open('/x.pdf');
    return c;
  }

  group('cubit', () {
    test('opening shows the pages and starts with nothing selected', () async {
      final c = await opened();
      expect(c.state.pageCount, 6);
      expect(c.state.selected, isEmpty);
      await c.close();
    });

    test('a PDF that cannot be opened reports why', () async {
      final c = PdfPagesCubit(
        service: _Service(const [], openFailure: const ImportFailure('This file is password protected.')),
        outputDir: () async => dir,
      );
      await c.open('/x.pdf');
      expect(c.state.pdf, isNull);
      expect(c.state.failure!.message, 'This file is password protected.');
      await c.close();
    });

    test('selecting by tap, parity, all, none and range text', () async {
      final c = await opened();
      c.toggle(2);
      c.toggle(4);
      expect(c.state.selected, {2, 4});
      c.toggle(2);
      expect(c.state.selected, {4});
      c.selectParity(odd: true);
      expect(c.state.selected, {0, 2, 4});
      c.selectParity(odd: false);
      expect(c.state.selected, {1, 3, 5});
      c.selectAll();
      expect(c.state.selected.length, 6);
      c.selectNone();
      expect(c.state.selected, isEmpty);
      c.selectRanges('2-3, 6');
      expect(c.state.selected, {1, 2, 5});
      c.selectRanges('9');
      expect(c.state.rangeError, contains('Page 9 does not exist'));
      expect(c.state.selected, {1, 2, 5}, reason: 'a bad entry keeps the old selection');
      c.toggle(0);
      expect(c.state.rangeError, isNull);
      await c.close();
    });

    test('keep selected makes one file with those pages in order', () async {
      final c = await opened();
      c.selectRanges('5, 1-2');
      await c.run();
      expect(service.lastParts.single.pages, [0, 1, 4]);
      expect(service.lastParts.single.fileName, 'Bank_statement_2025_pages_1-2_5.pdf');
      expect(c.state.status, PagesStatus.done);
      expect(c.state.parts.single.pages, 3);
      await c.close();
    });

    test('keep selected needs a selection', () async {
      final c = await opened();
      await c.run();
      expect(service.lastParts, isEmpty);
      expect(c.state.failure!.message, contains('Tap the pages you want to keep'));
      expect(c.state.status, PagesStatus.idle);
      await c.close();
    });

    test('remove selected keeps the rest, and refuses to remove everything', () async {
      final c = await opened();
      c.setAction(PageAction.remove);
      await c.run();
      expect(c.state.failure!.message, contains('Tap the pages you want to remove'));
      c.selectRanges('2-3');
      await c.run();
      expect(service.lastParts.single.pages, [0, 3, 4, 5]);
      expect(service.lastParts.single.fileName, contains('without_2-3'));
      c.selectAll();
      await c.run();
      expect(c.state.failure!.message, contains('every page'));
      await c.close();
    });

    test('split into every N pages', () async {
      final c = await opened();
      c.setAction(PageAction.split);
      c.setSplitMode(SplitMode.every);
      c.setSplitEvery(4);
      await c.run();
      expect(service.lastParts.map((e) => e.pages), [
        [0, 1, 2, 3],
        [4, 5],
      ]);
      expect(service.lastParts.map((e) => e.fileName), ['Bank_statement_2025_part_1_p1-4.pdf', 'Bank_statement_2025_part_2_p5-6.pdf']);
      await c.close();
    });

    test('split every page and by ranges', () async {
      final c = await opened();
      c.setAction(PageAction.split);
      c.setSplitMode(SplitMode.each);
      await c.run();
      expect(service.lastParts.length, 6);
      expect(service.lastParts[2].fileName, 'Bank_statement_2025_page_3.pdf');
      c.setSplitMode(SplitMode.ranges);
      c.setSplitRanges('1-2, 5-');
      await c.run();
      expect(service.lastParts.map((e) => e.pages), [
        [0, 1],
        [4, 5],
      ]);
      c.setSplitRanges('1-20');
      await c.run();
      expect(c.state.failure!.message, contains('does not exist'));
      await c.close();
    });

    test('splitting into one file is refused with advice', () async {
      final c = await opened();
      c.setAction(PageAction.split);
      c.setSplitEvery(50);
      await c.run();
      expect(c.state.failure!.message, contains('single file'));
      await c.close();
    });

    test('turning selected pages accumulates and cancels out', () async {
      final c = await opened();
      c.rotateSelected(1);
      expect(c.state.rotations, isEmpty, reason: 'nothing selected');
      c.selectRanges('1-2');
      c.rotateSelected(1);
      c.rotateSelected(1);
      expect(c.state.rotations, {0: 2, 1: 2});
      c.rotateSelected(-1);
      expect(c.state.rotations, {0: 1, 1: 1});
      c.rotateSelected(-1);
      expect(c.state.rotations, isEmpty);
      c.rotateSelected(-1);
      expect(c.state.rotations, {0: 3, 1: 3});
      await c.close();
    });

    test('turns and marks are handed to the service', () async {
      final c = await opened();
      c.selectRanges('1');
      c.rotateSelected(1);
      c.setMarks(const PageMarks(numbers: PageNumberStyle.pageOf, footer: 'Draft'));
      await c.run();
      expect(service.lastRotations, {0: 1});
      expect(service.lastMarks.footer, 'Draft');
      expect(service.lastMarks.numbers, PageNumberStyle.pageOf);
      await c.close();
    });

    test('changing a setting clears the earlier result', () async {
      final c = await opened();
      c.selectAll();
      await c.run();
      expect(c.state.parts, isNotEmpty);
      c.setAction(PageAction.remove);
      expect(c.state.parts, isEmpty);
      expect(c.state.status, PagesStatus.idle);
      await c.close();
    });

    test('a failure from the service is shown', () async {
      final c = await opened();
      service.buildFailure = const ExportFailure('The PDF could not be created. The file may be damaged.');
      c.selectAll();
      await c.run();
      expect(c.state.failure!.message, contains('could not be created'));
      expect(c.state.parts, isEmpty);
      await c.close();
    });

    test('file names are safe', () async {
      final c = PdfPagesCubit(service: _Service([service.pages.first, service.pages[1]]), outputDir: () async => dir);
      await c.open('/x.pdf');
      c.selectAll();
      await c.run();
      expect(c.state.parts.single.name, 'Bank_statement_2025_pages_1-2.pdf');
      await c.close();
    });
  });

  group('page', () {
    Future<PdfPagesCubit> show(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      await sl.reset();
      sl.registerSingleton<PdfPageService>(service);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PdfPagesPage()));
      await tester.pump();
      return tester.element(find.byType(Scaffold).first).read<PdfPagesCubit>();
    }

    testWidgets('asks for a PDF first and explains the limits', (tester) async {
      await show(tester);
      expect(find.text('Choose a PDF'), findsOneWidget);
      expect(find.textContaining('can no longer be selected'), findsOneWidget);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('shows pages, selection and the created files at ${width.toInt()} px', (tester) async {
        final cubit = await show(tester, width: width);
        await tester.runAsync(() => cubit.open('/x.pdf'));
        await tester.pump();
        expect(find.text('Bank statement 2025.pdf'), findsOneWidget);
        expect(find.textContaining('6 pages'), findsOneWidget);
        expect(find.text('No pages selected'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('page-1')));
        await tester.pump();
        expect(find.text('1 of 6 selected'), findsOneWidget);
        expect(find.byIcon(AppIcons.check), findsOneWidget);

        final create = find.text('Create PDF');
        await tester.scrollUntilVisible(create, 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(create);
        await tester.pump();
        await tester.tap(create);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        final ready = find.text('Your PDF is ready');
        await tester.scrollUntilVisible(ready, 200, scrollable: find.byType(Scrollable).first);
        expect(ready, findsOneWidget);
        expect(find.textContaining('Bank_statement_2025_pages_2.pdf'), findsOneWidget);
        expect(find.text('Share'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('typing a bad page shows the reason under the field', (tester) async {
      final cubit = await show(tester);
      await tester.runAsync(() => cubit.open('/x.pdf'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '12');
      await tester.tap(find.text('Select'));
      await tester.pump();
      expect(find.textContaining('Page 12 does not exist'), findsOneWidget);
    });

    testWidgets('a failed open shows the reason', (tester) async {
      service = _Service(const [], openFailure: const ImportFailure('This file is password protected.'));
      final cubit = await show(tester);
      await tester.runAsync(() => cubit.open('/x.pdf'));
      await tester.pump();
      expect(find.text('This file is password protected.'), findsOneWidget);
    });
  });
}

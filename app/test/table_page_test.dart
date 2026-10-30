import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/tables/domain/table_reader.dart';
import 'package:doculoom/features/tables/presentation/table_cubit.dart';
import 'package:doculoom/features/tables/presentation/table_page.dart';

import 'support/pdf_ui_fakes.dart';
import 'support/table_pages.dart';

class _Ocr implements OcrEngine {
  _Ocr(this.pages);
  final Map<String, OcrPageResult> pages;
  final reads = <({String path, OcrScript script})>[];
  Failure? failure;
  Completer<void>? hold;

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async {
    reads.add((path: imagePath, script: script));
    if (hold != null) await hold!.future;
    if (failure != null) return Err(failure!);
    final page = pages[imagePath];
    return page == null ? const Err(OcrFailure('The text could not be read from this page.')) : Ok(page);
  }
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings(ocrScript: OcrScript.devanagari);
  @override
  Future<void> save(AppSettings settings) async {}
}

const _data = [
  ['Item', 'Qty', 'Price'],
  ['Apples', '12', '3.50'],
  ['Green tea', '4', '12.00'],
];

OcrPageResult _page(List<List<String>> rows) => page(grid(rows, [100, 400, 700]));

void main() {
  late Directory dir;
  late FakeShare share;
  late FakeSave save;

  setUp(() async {
    dir = tempDir();
    share = FakeShare();
    save = FakeSave();
    await sl.reset();
    sl
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<SaveService>(save);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('the table of a photo', () {
    TableCubit make(_Ocr ocr, {List<String> images = const ['/a.jpg'], String title = 'Sales report'}) => TableCubit(
      engine: ocr,
      images: images,
      script: OcrScript.latin,
      outputDir: () async => dir,
      title: title,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    test('column letters go A to Z, then AA, AB and on', () {
      expect([0, 1, 25, 26, 27, 51, 52, 701, 702].map(columnLabel), ['A', 'B', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
    });

    test('every picture is read once, with the chosen script, and the table is built from what was read', () async {
      final ocr = _Ocr({'/a.jpg': _page(_data)});
      final c = make(ocr);
      await c.start();
      expect(ocr.reads.map((r) => r.path), ['/a.jpg']);
      expect(ocr.reads.single.script, OcrScript.latin);
      expect(c.state.status, TableStatus.ready);
      expect(c.state.rows, _data);
      expect(c.state.hasTable, isTrue);
      expect(c.state.done, 1);
      await c.close();
    });

    test('pages are read in order and join into one table, without the heading row twice', () async {
      final ocr = _Ocr({
        '/a.jpg': _page(_data),
        '/b.jpg': _page([
          _data.first,
          ['Soap', '9', '1.00'],
        ]),
      });
      final c = make(ocr, images: ['/a.jpg', '/b.jpg']);
      final progress = <int>[];
      final sub = c.stream.listen((s) => progress.add(s.done));
      await c.start();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(ocr.reads.map((r) => r.path), ['/a.jpg', '/b.jpg']);
      expect(c.state.rows, [
        ..._data,
        ['Soap', '9', '1.00'],
      ]);
      expect(progress, containsAllInOrder([1, 2]));
      await c.close();
    });

    test('a page that cannot be read stops the job with the reason, and Try again works once it can', () async {
      final ocr = _Ocr({'/a.jpg': _page(_data)})..failure = const OcrFailure('The text could not be read from this page.');
      final c = make(ocr);
      await c.start();
      expect(c.state.status, TableStatus.failed);
      expect(c.state.failure?.message, contains('could not be read'));
      ocr.failure = null;
      await c.start();
      expect(c.state.status, TableStatus.ready);
      expect(c.state.failure, isNull);
      await c.close();
    });

    test('nothing to read is a failure and a photo with no text is an empty table', () async {
      final none = make(_Ocr({}), images: const []);
      await none.start();
      expect(none.state.status, TableStatus.failed);
      await none.close();

      final blank = make(_Ocr({'/a.jpg': const OcrPageResult(width: 100, height: 100, blocks: [])}));
      await blank.start();
      expect(blank.state.status, TableStatus.ready);
      expect(blank.state.hasTable, isFalse);
      expect(await blank.writeXlsx(), isNull);
      await blank.close();
    });

    test('column spacing rebuilds the table from the same reading, loses hand corrections, and the same spacing does nothing', () async {
      final close = [
        ['Name', 'Dept'],
        ['Asha', 'Sales'],
      ];
      final cells = [
        for (var r = 0; r < close.length; r++) ...[(close[r][0], 100.0, r), (close[r][1], 100.0 + close[r][0].length * 14.0 + 26, r)],
      ];
      final ocr = _Ocr({'/a.jpg': page(cells)});
      final c = make(ocr);
      await c.start();
      expect(c.state.columnCount, 1);
      c.editCell(0, 0, 'Staff');
      expect(c.state.edited, isTrue);
      c.setSpacing(TableSpacing.tight);
      expect(c.state.columnCount, 2);
      expect(c.state.edited, isFalse);
      expect(c.state.rows.first, ['Name', 'Dept']);
      expect(ocr.reads, hasLength(1), reason: 'the picture is not read again');
      final before = c.state;
      c.setSpacing(TableSpacing.tight);
      expect(c.state, before);
      await c.close();
    });

    test('a cell is corrected with spaces tidied; the same text, or a cell that is not there, changes nothing', () async {
      final c = make(_Ocr({'/a.jpg': _page(_data)}));
      await c.start();
      c.editCell(1, 0, '  Red   apples ');
      expect(c.state.rows[1][0], 'Red apples');
      expect(c.state.edited, isTrue);
      final before = c.state;
      c.editCell(1, 0, 'Red apples');
      c.editCell(9, 0, 'x');
      c.editCell(0, 9, 'x');
      c.editCell(-1, 0, 'x');
      expect(c.state, before);
      c.editCell(2, 1, '');
      expect(c.state.rows[2][1], '', reason: 'a cell can be emptied');
      await c.close();
    });

    test('rows and columns can be deleted, and deleting everything leaves no table', () async {
      final c = make(_Ocr({'/a.jpg': _page(_data)}));
      await c.start();
      c.deleteRow(0);
      expect(c.state.rows.first, ['Apples', '12', '3.50']);
      c.deleteColumn(1);
      expect(c.state.rows, [
        ['Apples', '3.50'],
        ['Green tea', '12.00'],
      ]);
      c.deleteRow(7);
      c.deleteColumn(7);
      expect(c.state.rows, hasLength(2));
      c.deleteColumn(0);
      c.deleteColumn(0);
      expect(c.state.hasTable, isFalse);
      await c.close();
    });

    test('Excel and CSV files are written under the name of the scan, with what is on screen', () async {
      final c = make(_Ocr({'/a.jpg': _page(_data)}), title: 'Sales / report: Q1!');
      await c.start();
      c.editCell(1, 0, 'Pears');
      final xlsx = (await c.writeXlsx())!;
      final csv = (await c.writeCsv())!;
      expect(xlsx, endsWith('Sales_report_Q1_1700000000000.xlsx'));
      expect(csv, endsWith('Sales_report_Q1_1700000000000.csv'));
      final wb = readXlsx(File(xlsx).readAsBytesSync());
      expect((wb.sheets.first.cells[CellRef.key(1, 0)]!.value as TextValue).text, 'Pears');
      expect((wb.sheets.first.cells[CellRef.key(1, 1)]!.value as NumberValue).number, 12);
      expect(File(csv).readAsStringSync(), contains('Pears,12,3.50'));
      await c.close();
    });

    test('a title with nothing usable in it still gives a file name', () async {
      final c = make(_Ocr({'/a.jpg': _page(_data)}), title: '???');
      await c.start();
      expect(await c.writeCsv(), contains('/table_'));
      await c.close();
    });
  });

  group('the screen', () {
    late _Ocr ocr;

    Future<GoRouter> open(WidgetTester tester, {Map<String, OcrPageResult>? pages, double width = 400, double height = 900, double scale = 1}) async {
      ocr = _Ocr(pages ?? {'/a.jpg': _page(_data)});
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
            builder: (_, _) => TablePage(
              args: const TableArgs(title: 'Sales report', imagePaths: ['/a.jpg']),
              engine: ocr,
            ),
          ),
          GoRoute(
            path: '/sheet',
            builder: (_, s) => Scaffold(body: Text('SHEET ${(s.extra! as SheetArgs).path}')),
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
      return router;
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    testWidgets('while it reads there is a message, and the text language of the settings is used', (tester) async {
      await open(tester);
      // The reading may already have finished; hold a new one to see the message.
      expect(ocr.reads.length, lessThanOrEqualTo(1));
      await settle(tester);
      expect(ocr.reads.single.script, OcrScript.devanagari);
    });

    testWidgets('it says it is reading while the text reader works', (tester) async {
      ocr = _Ocr({'/a.jpg': _page(_data)})..hold = Completer<void>();
      tester.view.physicalSize = const Size(1200, 2700);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        BlocProvider(
          create: (_) => SettingsCubit(_Prefs()),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: TablePage(
              args: const TableArgs(title: 't', imagePaths: ['/a.jpg']),
              engine: ocr,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Reading the table'), findsOneWidget);
      ocr.hold!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('table-grid')), findsOneWidget);
    });

    testWidgets('the cells are shown with the counts, and the share buttons are there', (tester) async {
      await open(tester);
      await settle(tester);
      expect(find.text('Apples'), findsOneWidget);
      expect(find.text('3.50'), findsOneWidget);
      expect(find.textContaining('3 rows, 3 columns'), findsOneWidget);
      for (final k in ['table-share-xlsx', 'table-open', 'table-share-csv', 'table-save']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a cell opens it for correction and the new text is shown and shared', (tester) async {
      await open(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('table-cell-1-0')));
      await tester.pumpAndSettle();
      expect(find.text('Row 2, column A'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('form-text-input')), 'Pears');
      await tester.tap(find.byKey(const ValueKey('form-text-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Pears'), findsOneWidget);
      expect(find.text('Apples'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('table-share-csv')));
      await settle(tester);
      final sent = share.single.single;
      expect(sent.mime, 'text/csv');
      expect(sent.subject, 'Sales report');
      expect(File(sent.path).readAsStringSync(), contains('Pears,12,3.50'));
    });

    testWidgets('Share Excel sends an .xlsx file, Save to Files keeps the name without the time stamp, Open to edit goes to the sheet screen', (tester) async {
      final router = await open(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('table-share-xlsx')));
      await settle(tester);
      expect(share.single.single.mime, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      expect(share.single.single.path, endsWith('.xlsx'));

      await tester.tap(find.byKey(const ValueKey('table-save')));
      await settle(tester);
      expect(save.files.single, 'Sales_report.xlsx');

      await tester.tap(find.byKey(const ValueKey('table-open')));
      await settle(tester);
      expect(find.textContaining('SHEET '), findsOneWidget);
      expect(router.state.matchedLocation, '/sheet');
      final path = (tester.widget<Text>(find.textContaining('SHEET ')).data!).substring(6);
      expect(File(path).existsSync(), isTrue);
    });

    testWidgets('press and hold offers to delete the row or the column', (tester) async {
      await open(tester);
      await settle(tester);
      await tester.longPress(find.byKey(const ValueKey('table-cell-2-1')));
      await tester.pumpAndSettle();
      expect(find.text('Delete row 3'), findsOneWidget);
      expect(find.text('Delete column B'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('table-delete-row')));
      await tester.pumpAndSettle();
      expect(find.text('Green tea'), findsNothing);
      expect(find.textContaining('2 rows, 3 columns'), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('table-cell-1-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('table-delete-column')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2 rows, 2 columns'), findsOneWidget);
    });

    testWidgets('changing the column spacing after a correction asks first; keeping leaves the table as it was', (tester) async {
      await open(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('table-cell-1-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('form-text-input')), 'Pears');
      await tester.tap(find.byKey(const ValueKey('form-text-ok')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('table-spacing-loose')));
      await tester.pumpAndSettle();
      expect(find.text('Change the columns?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text('Pears'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('table-spacing-loose')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('table-spacing-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Pears'), findsNothing);
      expect(find.text('Apples'), findsOneWidget);
      expect(ocr.reads, hasLength(1));
    });

    testWidgets('a photo with no table says so and offers no files', (tester) async {
      await open(tester, pages: {'/a.jpg': const OcrPageResult(width: 100, height: 100, blocks: [])});
      await settle(tester);
      expect(find.byKey(const ValueKey('table-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('table-share-xlsx')), findsNothing);
    });

    testWidgets('a photo that cannot be read says why and can be tried again', (tester) async {
      await open(tester, pages: {});
      await settle(tester);
      expect(find.byKey(const ValueKey('table-failure')), findsOneWidget);
      ocr.pages['/a.jpg'] = _page(_data);
      await tester.tap(find.byKey(const ValueKey('table-retry')));
      await settle(tester);
      expect(find.text('Apples'), findsOneWidget);
    });

    testWidgets('a wide table scrolls sideways, and a small phone with large text does not overflow', (tester) async {
      final wide = [
        for (var r = 0; r < 4; r++) ['Row $r', 'Long text $r', 'Another $r', 'More words $r', 'Last $r'],
      ];
      await open(
        tester,
        pages: {
          '/a.jpg': page(grid(wide, [30, 200, 420, 640, 860])),
        },
        width: 320,
        height: 568,
        scale: 1.4,
      );
      await settle(tester);
      expect(find.textContaining('5 columns'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:doculoom/features/expenses/presentation/expenses_cubit.dart';
import 'package:doculoom/features/expenses/presentation/expenses_page.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_picture_pages.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/tools/presentation/tools_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/ocr_tool_fakes.dart';
import 'support/pdf_ui_fakes.dart';

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

const _lunch =
    'SUNRISE SUPERMARKET\nDate 12/03/2026\nMilk 60.00\nBread 45.00\nRice 295.00\nSub Total 400.00\nCGST 9% 36.00\nSGST 9% 36.00\nGrand Total ₹472.00';
const _taxi = 'Uber Rides\n05/03/2026\nTotal ₹250.00';
const _tea = 'Chai Point Cafe\n20/02/2026\nTotal 80.00';
const _pizza = "Joe's Pizza Kitchen\n04/18/2026\nSubtotal 17.50\nSales Tax 1.44\nTip 3.50\nTotal \$22.44";

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;
  late FakeTextReader reader;

  setUp(() async {
    dir = tempDir();
    reader = FakeTextReader({'lunch.jpg': _lunch, 'taxi.jpg': _taxi, 'tea.jpg': _tea, 'pizza.jpg': _pizza, 'blank.jpg': '', 'p0.jpg': _lunch, 'p1.jpg': _taxi});
    await sl.reset();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('reading bills', () {
    ExpensesCubit make({String currency = '', PdfPicturePages Function()? pdf, int maxPdfPages = 60}) => ExpensesCubit(
      engine: reader,
      outputDir: () async => dir,
      defaultCurrency: currency,
      pdfPages: pdf,
      maxPdfPages: maxPdfPages,
      now: () => DateTime(2026, 6, 1, 10),
    );

    test('every picture is one bill, in the order they were chosen', () async {
      final c = make();
      await c.addFiles(['/x/lunch.jpg', '/x/taxi.jpg']);
      expect(c.state.status, ExpensesStatus.ready);
      expect(c.state.records.map((r) => r.source), ['lunch.jpg', 'taxi.jpg']);
      expect(c.state.records.map((r) => r.total), [472.0, 250.0]);
      expect(c.state.records.first.vendor, 'SUNRISE SUPERMARKET');
      expect(c.state.records.first.date, DateTime(2026, 3, 12));
      expect(c.state.records.map((r) => r.id).toSet().length, 2);
      expect(c.state.failure, isNull);
      await c.close();
    });

    test('bills added later join the earlier ones', () async {
      final c = make();
      await c.addFiles(['/x/lunch.jpg']);
      await c.addFiles(['/x/taxi.jpg']);
      expect(c.state.records.length, 2);
      await c.close();
    });

    test('each page of a PDF is one bill, and the pictures made for reading are removed', () async {
      final pages = FakePicturePages(2);
      reader.texts.addAll({'p0.jpg': _lunch, 'p1.jpg': _taxi});
      final c = make(pdf: () => pages);
      await c.addFiles(['/x/month.pdf']);
      expect(c.state.records.map((r) => r.source), ['month.pdf, page 1', 'month.pdf, page 2']);
      expect(c.state.records.map((r) => r.total), [472.0, 250.0]);
      expect(pages.closed, isTrue);
      expect(Directory(p.join(dir.path, 'expenses')).listSync(recursive: true).whereType<File>(), isEmpty);
      await c.close();
    });

    test('a PDF with one page is named after the file; a long PDF is read up to the limit', () async {
      final c = make(pdf: () => FakePicturePages(1));
      await c.addFiles(['/x/one.pdf']);
      expect(c.state.records.single.source, 'one.pdf');
      await c.close();
      final long = make(pdf: () => FakePicturePages(5), maxPdfPages: 2);
      await long.addFiles(['/x/long.pdf']);
      expect(long.state.notes.single, contains('the first 2 were read'));
      expect(reader.reads.length, 1 + 2);
      await long.close();
    });

    test('what is not a picture or PDF, and pictures with no bill, are left out with a note', () async {
      final c = make();
      await c.addFiles(['/x/notes.docx', '/x/blank.jpg', '/x/lunch.jpg']);
      expect(c.state.records.map((r) => r.source), ['lunch.jpg']);
      expect(c.state.notes, ['"notes.docx" is not a picture or a PDF, so it was skipped.', 'No bill was found on "blank.jpg".']);
      await c.close();
    });

    test('a picture that cannot be read is named, and the others carry on', () async {
      reader.failing.add('taxi.jpg');
      final c = make();
      await c.addFiles(['/x/taxi.jpg', '/x/lunch.jpg']);
      expect(c.state.records.map((r) => r.source), ['lunch.jpg']);
      expect(c.state.notes.single, startsWith('Could not read "taxi.jpg"'));
      await c.close();
    });

    test('when nothing can be read the person is told what to try', () async {
      final c = make();
      await c.addFiles(['/x/blank.jpg']);
      expect(c.state.records, isEmpty);
      expect(c.state.failure!.message, contains('No bill could be read'));
      await c.close();
    });

    test('a saved scan is one bill, whatever its number of pages', () async {
      reader.texts['front.jpg'] = "Joe's Pizza Kitchen\n04/18/2026\nSubtotal 17.50";
      reader.texts['back.jpg'] = 'Sales Tax 1.44\nTotal \$22.44';
      final c = make();
      await c.addScans([
        (label: 'Dinner', pages: ['/s/front.jpg', '/s/back.jpg']),
      ]);
      final r = c.state.records.single;
      expect((r.source, r.vendor, r.subtotal, r.tax, r.total), ('Dinner', "Joe's Pizza Kitchen", 17.5, 1.44, 22.44));
      await c.close();
    });

    test('the currency for bills that print none can be chosen, and applies to those already read', () async {
      final c = make(currency: 'INR');
      await c.addFiles(['/x/tea.jpg', '/x/pizza.jpg']);
      expect(c.state.records.map((r) => r.currency), ['INR', 'USD']);
      c.setDefaultCurrency('EUR');
      expect(c.state.records.map((r) => r.currency), ['EUR', 'USD']);
      await c.addFiles(['/x/tea.jpg']);
      expect(c.state.records.last.currency, 'EUR');
      await c.close();
    });

    test('Stop keeps what was read so far', () async {
      reader.hold = Completer<void>();
      final c = make();
      final run = c.addFiles(['/x/lunch.jpg', '/x/taxi.jpg']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.state.reading, isTrue);
      expect(c.state.label, 'lunch.jpg');
      c.cancel();
      reader.hold!.complete();
      await run;
      expect(c.state.records.map((r) => r.source), ['lunch.jpg']);
      expect(c.state.notes.last, startsWith('Stopped.'));
      await c.close();
    });

    test('a bill can be corrected, removed, and all can be cleared; a second photo of one bill is flagged', () async {
      final c = make();
      await c.addFiles(['/x/lunch.jpg', '/x/lunch.jpg']);
      final first = c.state.records.first;
      expect(c.state.duplicates, {c.state.records.last.id});
      c.replace(first.copyWith(vendor: 'Sunrise', total: 500.0));
      expect(c.state.records.first.vendor, 'Sunrise');
      expect(c.state.duplicates, isEmpty);
      c.remove(first.id);
      expect(c.state.records.length, 1);
      c.clear();
      expect(c.state.records, isEmpty);
      expect(c.state.status, ExpensesStatus.idle);
      await c.close();
    });

    test('Excel and CSV files are written with the bills in them', () async {
      final c = make();
      expect(await c.writeXlsx(), isNull);
      await c.addFiles(['/x/lunch.jpg', '/x/taxi.jpg']);
      final xlsx = await c.writeXlsx();
      expect(p.basename(xlsx!), 'Expenses_2026-06-01_${DateTime(2026, 6, 1, 10).millisecondsSinceEpoch}.xlsx');
      final wb = readXlsx(File(xlsx).readAsBytesSync());
      expect(wb.sheets.map((s) => s.name), ['Receipts', 'Monthly', 'Categories', 'Items']);
      final csv = await c.writeCsv();
      expect(File(csv!).readAsStringSync(), contains('SUNRISE SUPERMARKET'));
      await c.close();
    });
  });

  group('the screen', () {
    late FakeShare share;
    late FakeSave save;

    Future<void> open(
      WidgetTester tester, {
      List<String> images = const ['/x/lunch.jpg', '/x/taxi.jpg', '/x/tea.jpg'],
      List<String> files = const [],
      Future<List<BillSource>> Function(BuildContext)? scans,
      double width = 400,
      double height = 2200,
      double scale = 1,
    }) async {
      share = FakeShare();
      save = FakeSave();
      sl
        ..registerSingleton<ShareService>(share)
        ..registerSingleton<SaveService>(save);
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
            builder: (_, _) => ExpensesPage(
              engine: reader,
              country: 'IN',
              pdfPages: () => FakePicturePages(2),
              pickImages: () async => images,
              takePhoto: () async => const ['/x/pizza.jpg'],
              pickFiles: () async => files,
              pickScans: scans ?? (_) async => const [],
            ),
          ),
          GoRoute(
            path: '/sheet',
            builder: (_, s) => const Scaffold(body: Text('SHEET')),
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
        await tester.pump();
      }
    }

    Future<void> readPictures(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('expenses-images')));
      await settle(tester);
    }

    String textOf(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    testWidgets('it starts with ways to add bills, a currency choice and a promise about privacy', (tester) async {
      await open(tester);
      for (final k in ['expenses-images', 'expenses-camera', 'expenses-files', 'expenses-scans', 'expenses-currency']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.textContaining('never uploaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-share-xlsx')), findsNothing);
      expect(find.byKey(const ValueKey('expenses-summary-INR')), findsNothing);
    });

    testWidgets('after reading there is the total spent, the months, the kinds of spending and a card for each bill', (tester) async {
      await open(tester);
      await readPictures(tester);
      expect(textOf(tester, 'expenses-total-INR'), '₹802.00');
      expect(textOf(tester, 'expenses-figures-INR'), contains('3 bills'));
      expect(find.byKey(const ValueKey('expenses-month-INR-2026-03')), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-month-INR-2026-02')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('expenses-month-INR-2026-03')), matching: find.text('₹722.00')), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-kind-INR-groceries')), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-kind-INR-transport')), findsOneWidget);
      for (final id in ['b0', 'b1', 'b2']) {
        expect(find.byKey(ValueKey('expenses-bill-$id')), findsOneWidget);
      }
      expect(textOf(tester, 'expenses-amount-b0'), '₹472.00');
      expect(find.byKey(const ValueKey('expenses-share-xlsx')), findsOneWidget);
    });

    testWidgets('bills in two currencies are never added together', (tester) async {
      await open(tester, images: const ['/x/lunch.jpg', '/x/pizza.jpg']);
      await readPictures(tester);
      expect(textOf(tester, 'expenses-total-INR'), '₹472.00');
      expect(textOf(tester, 'expenses-total-USD'), '\$22.44');
      expect(find.text('Total spent (USD)'), findsOneWidget);
    });

    testWidgets('while reading there is progress with the name and a Stop button', (tester) async {
      await open(tester);
      reader.hold = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('expenses-images')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(find.textContaining('Reading lunch.jpg (1 of 3)'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-cancel')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('expenses-images'))).onPressed, isNull);
      reader.hold!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('expenses-progress')), findsNothing);
    });

    testWidgets('a bill with a note shows it, and a bill with no total is left out of the sums and says so', (tester) async {
      reader.texts['odd.jpg'] = 'Mystery Shop\n01/02/2026\n~~';
      await open(tester, images: const ['/x/lunch.jpg', '/x/odd.jpg']);
      await readPictures(tester);
      expect(find.text('No total'), findsOneWidget);
      expect(find.text('No total was found. Type it in.'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-untotalled')), findsOneWidget);
      expect(textOf(tester, 'expenses-total-INR'), '₹472.00');
    });

    testWidgets('tapping a bill opens it for correction, shows at once whether it adds up, and saving updates the sums', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-bill-b0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expense-ok')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('expense-total')), '500');
      await tester.pump();
      expect(find.byKey(const ValueKey('expense-ok')), findsNothing);
      expect(find.text('The parts do not add up to the total. Check the amounts.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('expense-total')), 'abc');
      await tester.pump();
      expect(find.text('Not an amount'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('expense-save'))).onPressed, isNull);
      await tester.enterText(find.byKey(const ValueKey('expense-total')), '500.00');
      await tester.enterText(find.byKey(const ValueKey('expense-tax')), '100');
      await tester.enterText(find.byKey(const ValueKey('expense-vendor')), 'Sunrise Mart');
      await tester.pump();
      expect(find.byKey(const ValueKey('expense-ok')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('expense-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('expense-save')));
      await tester.pumpAndSettle();
      expect(find.text('Sunrise Mart'), findsOneWidget);
      expect(textOf(tester, 'expenses-amount-b0'), '₹500.00');
      expect(textOf(tester, 'expenses-total-INR'), '₹830.00');
    });

    testWidgets('a bill can be changed to another currency and kind of spending', (tester) async {
      await open(tester, images: const ['/x/tea.jpg']);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-bill-b0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expense-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('expense-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('expense-save')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'expenses-amount-b0'), '\$80.00');
      expect(find.byKey(const ValueKey('expenses-kind-USD-health')), findsOneWidget);
    });

    testWidgets('a bill can be removed from its form or with the bin', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-remove-b2')));
      await tester.pump();
      expect(find.byKey(const ValueKey('expenses-bill-b2')), findsNothing);
      expect(textOf(tester, 'expenses-total-INR'), '₹722.00');
      await tester.tap(find.byKey(const ValueKey('expenses-bill-b1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('expense-delete')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('expense-delete')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'expenses-total-INR'), '₹472.00');
    });

    testWidgets('the Excel file, the CSV and Save to Files each get the bills', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-share-xlsx')));
      await settle(tester);
      expect(share.single.single.mime, contains('spreadsheetml'));
      expect(readXlsx(File(share.single.single.path).readAsBytesSync()).sheets.first.name, 'Receipts');
      await tester.tap(find.byKey(const ValueKey('expenses-share-csv')));
      await settle(tester);
      expect(share.single.last.mime, 'text/csv');
      expect(File(share.single.last.path).readAsStringSync(), contains('Chai Point Cafe'));
      await tester.tap(find.byKey(const ValueKey('expenses-save')));
      await settle(tester);
      expect(save.files.single, matches(RegExp(r'^Expenses_\d{4}-\d{2}-\d{2}\.xlsx$')));
      await tester.tap(find.byKey(const ValueKey('expenses-open')));
      await settle(tester);
      expect(find.text('SHEET'), findsOneWidget);
    });

    testWidgets('Clear starts again and the totals can be copied', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('expenses-copy')));
      await tester.pump();
      expect(copied, 'Total ₹802.00 (3 bills)');
      await tester.tap(find.byKey(const ValueKey('expenses-clear')));
      await tester.pump();
      expect(find.byKey(const ValueKey('expenses-summary-INR')), findsNothing);
    });

    testWidgets('the camera adds one bill, and files with PDFs add a bill for each page', (tester) async {
      await open(tester, files: const ['/x/month.pdf']);
      await tester.tap(find.byKey(const ValueKey('expenses-camera')));
      await settle(tester);
      expect(find.byKey(const ValueKey('expenses-bill-b0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('expenses-files')));
      await settle(tester);
      expect(find.byKey(const ValueKey('expenses-bill-b1')), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-bill-b2')), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-bill-b3')), findsNothing);
    });

    testWidgets('the currency chosen first is used for bills that show none', (tester) async {
      await open(tester, images: const ['/x/tea.jpg']);
      await tester.tap(find.byKey(const ValueKey('expenses-currency')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('EUR').last);
      await tester.pumpAndSettle();
      await readPictures(tester);
      expect(textOf(tester, 'expenses-total-EUR'), '€80.00');
    });

    testWidgets('saved scans: those in the Receipts folder are ticked, locked ones are not offered', (tester) async {
      final root = Directory.systemTemp.createTempSync('sv_exp_root');
      addTearDown(() => root.deleteSync(recursive: true));
      final repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
      NewPage pageNamed(String name) {
        final f = File(p.join(dir.path, '$name.jpg'))..writeAsStringSync(name);
        return NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10);
      }

      final receipts = (await tester.runAsync(() => repo.createFolder('Receipts')))!.valueOrNull!;
      final secret = (await tester.runAsync(() => repo.createFolder('Secret')))!.valueOrNull!;
      await tester.runAsync(() async {
        await repo.updateFolderMeta(secret.id, locked: true);
        await repo.saveDocument(title: 'Lunch', pages: [pageNamed('lunch')], folderId: receipts.id);
        await repo.saveDocument(title: 'Passport', pages: [pageNamed('passport')]);
        await repo.saveDocument(title: 'Hidden', pages: [pageNamed('hidden')], folderId: secret.id);
      });
      final docs = DocumentsCubit(
        listDocuments: ListDocuments(repo),
        listFolders: ListFolders(repo),
        deleteDocument: DeleteDocument(repo),
        renameDocument: RenameDocument(repo),
        moveDocument: MoveDocument(repo),
        mergeDocuments: MergeDocuments(repo),
        createFolder: CreateFolder(repo),
        renameFolder: RenameFolder(repo),
        updateFolderMeta: UpdateFolderMeta(repo),
        deleteFolder: DeleteFolder(repo),
      );
      reader.texts['page_0.jpg'] = _lunch;
      await tester.runAsync(docs.load);
      share = FakeShare();
      save = FakeSave();
      sl
        ..registerSingleton<ShareService>(share)
        ..registerSingleton<SaveService>(save);
      tester.view.physicalSize = const Size(400 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      final settings = SettingsCubit(_Prefs());
      await tester.runAsync(settings.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: settings),
            BlocProvider.value(value: docs),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ExpensesPage(engine: reader, country: 'IN'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expenses-scans')));
      await tester.pumpAndSettle();
      final lunch = docs.state.documents.firstWhere((d) => d.title == 'Lunch');
      final passport = docs.state.documents.firstWhere((d) => d.title == 'Passport');
      expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('expenses-scan-${lunch.id}'))).value, isTrue);
      expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('expenses-scan-${passport.id}'))).value, isFalse);
      expect(find.text('Hidden'), findsNothing);
      expect(find.text('Read 1 scan'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('expenses-scan-${passport.id}')));
      await tester.pump();
      expect(find.text('Read 2 scans'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('expenses-scan-${passport.id}')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('expenses-scans-read')));
      await settle(tester);
      expect(reader.reads.map((r) => p.basename(r.path)), ['page_0.jpg']);
      expect(find.byKey(const ValueKey('expenses-bill-b0')), findsOneWidget);
    });

    testWidgets('with no saved scans the sheet says so', (tester) async {
      final docs = DocumentsCubit(
        listDocuments: ListDocuments(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        listFolders: ListFolders(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        deleteDocument: DeleteDocument(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        renameDocument: RenameDocument(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        moveDocument: MoveDocument(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        mergeDocuments: MergeDocuments(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        createFolder: CreateFolder(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        renameFolder: RenameFolder(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        updateFolderMeta: UpdateFolderMeta(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
        deleteFolder: DeleteFolder(DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: dir))),
      );
      sl.registerSingleton<ShareService>(FakeShare());
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final settings = SettingsCubit(_Prefs());
      await tester.runAsync(settings.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: settings),
            BlocProvider.value(value: docs),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ExpensesPage(engine: reader, country: 'IN'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('expenses-scans')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expenses-scans-empty')), findsOneWidget);
      expect(find.text('No saved scans'), findsOneWidget);
    });

    testWidgets('a small phone with large text does not overflow', (tester) async {
      await open(tester, width: 320, height: 568, scale: 1.4);
      await readPictures(tester);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('expenses-bill-b0')), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('expenses-bill-b0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -800));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('the Tools tab', () {
    testWidgets('Receipts to Excel is offered and opens the tool', (tester) async {
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
            path: '/expenses',
            builder: (_, _) => const Scaffold(body: Text('EXPENSES')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Receipts to Excel'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.text('Receipts to Excel'));
      await tester.pumpAndSettle();
      expect(find.text('EXPENSES'), findsOneWidget);
    });
  });
}

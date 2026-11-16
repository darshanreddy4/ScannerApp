import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/office/sheets/data/sheet_templates.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:doculoom/features/office/sheets/presentation/new_spreadsheet_sheet.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_page.dart';
import 'package:doculoom/features/text_edit/docx/doc_template_store.dart';

Object? valueAt(Workbook wb, String ref) {
  final c = CellRef.parse(ref)!;
  return switch (wb.sheets.first.cellAt(c.row, c.col).value) {
    NumberValue(:final number) => number,
    TextValue(:final text) => text,
    BoolValue(:final flag) => flag,
    ErrorValue(:final code) => code,
    EmptyValue() => null,
  };
}

SheetTemplate template(String id) => sheetTemplateById(id)!;

void main() {
  group('starter spreadsheets', () {
    test('every starter builds, calculates without errors, and survives a save and reopen', () {
      expect(sheetTemplates.map((t) => t.id).toSet().length, sheetTemplates.length);
      for (final t in sheetTemplates) {
        final wb = t.build();
        for (final e in wb.sheets.first.cells.entries) {
          final v = e.value.value;
          expect(v is ErrorValue, isFalse, reason: '${t.id} ${CellRef.a1(CellRef.rowOf(e.key), CellRef.colOf(e.key))} shows ${v is ErrorValue ? v.code : ''}');
          if (e.value.formula != null) expect(v is EmptyValue, isFalse, reason: '${t.id} ${CellRef.a1(CellRef.rowOf(e.key), CellRef.colOf(e.key))} was not calculated');
        }
        final again = readXlsx(writeXlsx(wb));
        expect(again.sheets, hasLength(1), reason: t.id);
        expect(again.sheets.first.cells.length, wb.sheets.first.cells.length, reason: t.id);
        final formulas = wb.sheets.first.cells.values.where((c) => c.formula != null).length;
        expect(again.sheets.first.cells.values.where((c) => c.formula != null).length, formulas, reason: '${t.id} keeps its formulas');
      }
    });

    test('the marks sheet works out totals, percent, grade and rank', () {
      final wb = template('marks').build();
      expect(valueAt(wb, 'F4'), 82 + 75 + 68 + 90);
      expect(valueAt(wb, 'G4'), closeTo(315 / 400, 1e-9));
      expect(valueAt(wb, 'H4'), 'B');
      expect(valueAt(wb, 'H5'), 'A');
      expect(valueAt(wb, 'H6'), 'D');
      expect(valueAt(wb, 'H8'), 'D');
      expect(valueAt(wb, 'I4'), 2);
      expect(valueAt(wb, 'I5'), 1);
      expect(valueAt(wb, 'I8'), 5);
      expect(valueAt(wb, 'F9'), '', reason: 'an empty row stays empty');
      expect(valueAt(wb, 'B15'), closeTo((82 + 91 + 55 + 73 + 38) / 5, 1e-9));
    });

    test('the budget, expenses, invoice and loan sheets add up', () {
      final budget = template('budget').build();
      expect(valueAt(budget, 'B7'), 32000);
      expect(valueAt(budget, 'B18'), 28000);
      expect(valueAt(budget, 'B20'), 4000);
      expect(valueAt(budget, 'D10'), 9000, reason: 'nothing spent yet, so the whole plan is left');

      final expenses = template('expenses').build();
      expect(valueAt(expenses, 'G4'), 120);
      expect(valueAt(expenses, 'G5'), 450);
      expect(valueAt(expenses, 'G10'), 120 + 450 + 90 + 299);
      expect(valueAt(expenses, 'G11'), 450);

      final invoice = template('invoice').build();
      expect(valueAt(invoice, 'D8'), 1000);
      expect(valueAt(invoice, 'D16'), 2200);
      expect(valueAt(invoice, 'D18'), closeTo(220, 1e-9));
      expect(valueAt(invoice, 'D19'), closeTo(2420, 1e-9));

      final loan = template('loan').build();
      expect(valueAt(loan, 'B8') as double, closeTo(2027.64, 0.01));
      expect(valueAt(loan, 'B10') as double, closeTo(2027.64 * 60 - 100000, 1.0));
    });

    test('attendance, savings, sales, stock and the project tracker give sensible answers', () {
      final attendance = template('attendance').build();
      expect((valueAt(attendance, 'L4') as double) + (valueAt(attendance, 'M4') as double), 10);
      expect(valueAt(attendance, 'N4') as double, inInclusiveRange(0, 1));
      expect(valueAt(attendance, 'N10'), '');

      final savings = template('savings').build();
      final monthly = valueAt(savings, 'B9') as double;
      expect(monthly, greaterThan(3500));
      expect(monthly, lessThan(3750));
      expect(valueAt(savings, 'B11') as double, greaterThan(0));

      final sales = template('sales').build();
      expect(valueAt(sales, 'D4'), 120 * 250);
      expect(valueAt(sales, 'B17'), 120 + 135 + 150 + 128 + 160 + 172);
      expect(valueAt(sales, 'D19'), 'June');

      final stock = template('stock').build();
      expect(valueAt(stock, 'F5'), 'Reorder');
      expect(valueAt(stock, 'F4'), 'OK');
      expect(valueAt(stock, 'E4'), 40 * 45);
      expect(valueAt(stock, 'E20'), 1);

      final project = template('project').build();
      expect(valueAt(project, 'F4'), 'Done');
      expect(valueAt(project, 'F5'), isA<double>());
      expect(valueAt(project, 'B17'), 1);
      expect(valueAt(project, 'B18'), 4);
      expect(valueAt(project, 'B19'), 0.25);
    });

    test('the blank starter is empty and the others carry their own look', () {
      expect(template('blank').build().sheets.first.cells, isEmpty);
      final marks = template('marks').build();
      expect(marks.styles.styles.length, greaterThan(3));
      expect(marks.sheets.first.colWidths, isNotEmpty);
    });
  });

  group('picking a starter', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_sheets'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Object?> pick(WidgetTester tester, String key, {DocTemplateStore? store}) async {
      Object? opened;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => startNewSpreadsheet(context, tempDir: () async => dir, store: store ?? DocTemplateStore.sheets(dir: () async => Directory(p.join(dir.path, 'mine')))),
                  child: const Text('start'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/sheet',
            builder: (_, state) {
              opened = state.extra;
              return const Scaffold(body: Text('editor'));
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.tap(find.text('start'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 20 && find.byKey(ValueKey(key)).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.tap(find.byKey(ValueKey(key)));
      for (var i = 0; i < 20 && opened == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('a starter is handed to the editor', (tester) async {
      final opened = await pick(tester, 'sheet-budget');
      expect(opened, isA<SheetArgs>());
      expect((opened! as SheetArgs).template!.id, 'budget');
    });

    testWidgets('a saved template is copied and opened by its file', (tester) async {
      final store = DocTemplateStore.sheets(dir: () async => Directory(p.join(dir.path, 'mine')));
      final src = File(p.join(dir.path, 'src.xlsx'))..writeAsBytesSync(writeXlsx(template('marks').build()));
      await tester.runAsync(() => store.save(src.path, 'My marks'));
      final opened = await pick(tester, 'mine-My marks', store: store);
      final args = opened! as SheetArgs;
      expect(args.path, p.join(dir.path, newSheetsFolder, 'My marks.xlsx'));
      expect(File(args.path!).existsSync(), isTrue);
    });
  });

  group('the editor with a starter', () {
    testWidgets('opens the starter with its cells shown and treats it as unsaved work', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: SheetPage(args: SheetArgs(template: template('loan')))));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('cell_0_0')), matching: find.text('Loan calculator')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sheet_back')));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
    });
  });
}

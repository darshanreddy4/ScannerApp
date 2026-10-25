import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/office/sheets/presentation/sheet_page.dart';

Widget host(SheetArgs args) => MaterialApp(
  theme: AppTheme.light(),
  home: SheetPage(args: args),
);

Finder inCell(int r, int c, String text) => find.descendant(of: find.byKey(ValueKey('cell_${r}_$c')), matching: find.text(text));

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('formula_field')), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

void main() {
  testWidgets('typing in the formula bar fills cells, formulas calculate, undo works', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(const SheetArgs()));
    await tester.pump();

    expect(find.byKey(const ValueKey('cell_0_0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cell_0_0')));
    await tester.pump();
    await type(tester, '5');
    await type(tester, '=A1*2');
    expect(inCell(0, 0, '5'), findsOneWidget);
    expect(inCell(1, 0, '10'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('ref_label')), matching: find.text('A3')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cell_0_0')));
    await tester.pump();
    await type(tester, '7');
    expect(inCell(1, 0, '14'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sheet_undo')));
    await tester.pump();
    expect(inCell(1, 0, '10'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sheet_redo')));
    await tester.pump();
    expect(inCell(1, 0, '14'), findsOneWidget);
  });

  testWidgets('bold, merging, sheets tabs and leaving with unsaved changes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(const SheetArgs()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    await type(tester, 'hello');
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tool_bold')));
    await tester.pump();
    final text = tester.widget<Text>(inCell(1, 1, 'hello'));
    expect(text.style!.fontWeight, FontWeight.w700);

    expect(find.byKey(const ValueKey('tab_0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tab_add')));
    await tester.pump();
    expect(find.byKey(const ValueKey('tab_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cell_1_1')), findsOneWidget);
    expect(inCell(1, 1, 'hello'), findsNothing, reason: 'the new sheet is empty');
    await tester.tap(find.byKey(const ValueKey('tab_0')));
    await tester.pump();
    expect(inCell(1, 1, 'hello'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sheet_back')));
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('formula_field')), findsOneWidget);
  });

  testWidgets('opens an .xlsx file and shows its cells, tabs and hides hidden sheets', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final path = File('test/fixtures/office/basic.xlsx').absolute.path;
    await tester.pumpWidget(host(SheetArgs(path: path)));
    for (var i = 0; i < 40 && find.byKey(const ValueKey('formula_field')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Hidden'), findsNothing);
    // The formula D2 = B2*C2 shows its result, and the formula bar shows the formula.
    expect(inCell(1, 3, '4.5'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cell_1_3')));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const ValueKey('formula_field'))).controller!.text, '=B2*C2');
  });

  testWidgets('a file that is not a spreadsheet shows a clear message', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bad_xlsx');
    final bad = File('${dir.path}/bad.xlsx')..writeAsBytesSync([1, 2, 3]);
    await tester.pumpWidget(host(SheetArgs(path: bad.path)));
    for (var i = 0; i < 40 && find.text('Go back').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('not a valid .xlsx'), findsOneWidget);
    dir.deleteSync(recursive: true);
  });
}

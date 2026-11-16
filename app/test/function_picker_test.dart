import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/office/sheets/domain/formula.dart';
import 'package:doculoom/features/office/sheets/domain/function_catalog.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_page.dart';

String fieldText(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('formula_field'))).controller!.text;

void main() {
  group('function catalog', () {
    test('lists only functions the sheet can calculate, once each, in known categories', () {
      final names = functionCatalog.map((f) => f.name).toList();
      expect(names.toSet().length, names.length, reason: 'no duplicates');
      for (final f in functionCatalog) {
        expect(FormulaEngine.isSupported('${f.name}(1)'), isTrue, reason: f.name);
        expect(functionCategories, contains(f.category), reason: f.name);
        expect(f.syntax, startsWith('${f.name}('), reason: f.name);
        expect(f.summary, isNotEmpty, reason: f.name);
      }
      expect(functionCatalog.length, greaterThan(100));
    });

    test('search puts names that start with the text first, then names and descriptions that contain it', () {
      final r = searchFunctions('sum').map((f) => f.name).toList();
      expect(r.first, 'SUM');
      expect(r.indexOf('SUMIF'), lessThan(r.indexOf('SUBTOTAL')), reason: 'a name that starts with it comes before one that only mentions it');
      expect(searchFunctions('lookup').map((f) => f.name), containsAll(['VLOOKUP', 'XLOOKUP', 'LOOKUP']));
      expect(searchFunctions('loan').map((f) => f.name), contains('PMT'), reason: 'found by its description');
      expect(searchFunctions('zzzz'), isEmpty);
      expect(searchFunctions('', category: 'Money').map((f) => f.category).toSet(), {'Money'});
      expect(searchFunctions('sum', category: 'Text'), isEmpty);
    });
  });

  group('the fx button', () {
    Future<void> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const SheetPage(args: SheetArgs())));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cell_0_0')));
      await tester.pump();
    }

    testWidgets('starts a formula with the chosen function', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('formula_fx')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('function_SUM')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('function_search')), 'xlook');
      await tester.pump();
      expect(find.byKey(const ValueKey('function_XLOOKUP')), findsOneWidget);
      expect(find.byKey(const ValueKey('function_SUM')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('function_XLOOKUP')));
      await tester.pumpAndSettle();
      expect(fieldText(tester), '=XLOOKUP(');
    });

    testWidgets('puts the function where the cursor is inside a formula', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('formula_field')), '=1+');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('formula_fx')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('function_cat_Math')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('function_search')), 'round');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('function_ROUND')));
      await tester.pumpAndSettle();
      expect(fieldText(tester), '=1+ROUND(');
    });

    testWidgets('a category with no match shows a message', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('formula_fx')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('function_cat_Math')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('function_search')), 'lookup');
      await tester.pump();
      expect(find.text('No function found'), findsOneWidget);
    });
  });
}

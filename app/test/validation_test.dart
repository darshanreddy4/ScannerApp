import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_edit.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:doculoom/features/office/sheets/domain/validation.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_cubit.dart';
import 'package:doculoom/features/office/sheets/presentation/validation_dialog.dart';

MergeRange range(String text) => CellRef.parseRange(text)!;

ValidationRule list(String ref, List<String> items) => ValidationRule(range: range(ref), kind: ValidationKind.list, items: items);
ValidationRule numbers(String ref, ValidationKind kind, String min, String max) => ValidationRule(range: range(ref), kind: kind, min: min, max: max);

String partText(Uint8List bytes, String name) => utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.readBytes()!);

Uint8List withSheetXml(Uint8List base, String Function(String) change) {
  final archive = ZipDecoder().decodeBytes(base);
  final out = Archive();
  for (final f in archive.files) {
    final bytes = f.name == 'xl/worksheets/sheet1.xml' ? utf8.encode(change(utf8.decode(f.readBytes()!))) : f.readBytes()!;
    out.addFile(ArchiveFile.bytes(f.name, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

void main() {
  group('what a rule allows', () {
    test('a list accepts its choices in any letter case and gives them back as written', () {
      final r = list('A1', ['Yes', 'No', 'Maybe']);
      expect(r.allows('yes'), isTrue);
      expect(r.allows(' MAYBE '), isTrue);
      expect(r.allows('Perhaps'), isFalse);
      expect(r.allows(''), isTrue, reason: 'clearing a cell is always fine');
      expect(r.allows('=A2'), isTrue, reason: 'formulas are not checked');
      expect(r.canonical('yes'), 'Yes');
      expect(r.canonical('other'), 'other');
    });

    test('number rules check the limits, in either order, and whole numbers refuse fractions', () {
      final whole = numbers('A1', ValidationKind.whole, '1', '10');
      expect([whole.allows('1'), whole.allows('10'), whole.allows('5'), whole.allows('0'), whole.allows('11'), whole.allows('2.5'), whole.allows('abc')], [true, true, true, false, false, false, false]);
      final dec = numbers('A1', ValidationKind.decimal, '10', '0');
      expect([dec.allows('2.5'), dec.allows('-1'), dec.allows('1,000')], [true, false, false]);
    });
  });

  group('in a spreadsheet', () {
    SheetCubit blank() => SheetCubit(workDir: () async => Directory.systemTemp)..startBlank();

    test('refused entries leave the cell as it was and say why; allowed ones are accepted', () {
      final c = blank();
      c.selectCell(0, 0);
      c.addValidation(list('A1', ['Yes', 'No']));
      expect(c.hasValidations, isTrue);
      expect(c.choicesForActiveCell, ['Yes', 'No']);

      c.commitInput('Maybe', moveDown: false);
      expect(c.state.notice, 'Not allowed here. Choose one of: Yes, No');
      expect(c.inputTextOf(0, 0), '');

      c.clearMessages();
      c.commitInput('yes', moveDown: false);
      expect(c.inputTextOf(0, 0), 'Yes', reason: 'stored as written in the list');

      c.selectCell(0, 1);
      expect(c.choicesForActiveCell, isEmpty, reason: 'no rule on B1');
      c.commitInput('anything', moveDown: false);
      expect(c.inputTextOf(0, 1), 'anything');
    });

    test('number rules refuse numbers outside their limits', () {
      final c = blank();
      c.selectCell(2, 0);
      c.addValidation(numbers('A3', ValidationKind.whole, '0', '100'));
      c.commitInput('101', moveDown: false);
      expect(c.state.notice, 'Not allowed here. Enter a whole number from 0 to 100');
      c.clearMessages();
      c.commitInput('99', moveDown: false);
      expect(c.inputTextOf(2, 0), '99');
    });

    test('a rule can be removed again and undone', () {
      final c = blank();
      c.selectCell(0, 0);
      c.addValidation(list('A1', ['x']));
      c.clearValidations();
      expect(c.hasValidations, isFalse);
      c.undo();
      expect(c.hasValidations, isTrue);
    });

    test('rules follow their cells when rows are inserted or removed', () {
      final wb = newWorkbook();
      final e = SheetEditor(wb);
      final s = wb.sheets.first;
      e.addValidation(s, list('B2:B5', ['a']));
      e.insertRows(s, 0, 2);
      expect(s.validations.single.range.toString(), 'B4:B7');
      expect(s.validationAt(3, 1), isNotNull);
      expect(s.validationAt(1, 1), isNull);
      e.deleteRows(s, 3, 4);
      expect(s.validations, isEmpty);
    });
  });

  group('saving and reopening', () {
    test('rules survive a save and the file gets real data validation', () {
      final wb = newWorkbook();
      final e = SheetEditor(wb);
      final s = wb.sheets.first;
      e.addValidation(s, list('A1:A10', ['Present', 'Absent', 'Late, excused']));
      e.addValidation(s, numbers('B1:B10', ValidationKind.whole, '0', '100'));
      e.addValidation(s, numbers('C1', ValidationKind.decimal, '0.5', '9.5'));
      final xml = partText(writeXlsx(wb), 'xl/worksheets/sheet1.xml');
      expect(xml, contains('<dataValidations count="3">'));
      expect(xml, contains('type="list"'));
      expect(xml, contains('type="whole"'));
      expect(xml, contains('type="decimal"'));

      final back = readXlsx(writeXlsx(wb)).sheets.first.validations;
      expect(back, hasLength(3));
      expect(back[0].kind, ValidationKind.list);
      expect(back[0].range.toString(), 'A1:A10');
      expect(back[0].items, ['Present', 'Absent', 'Late', 'excused'], reason: 'a comma always starts a new choice');
      expect((back[1].min, back[1].max, back[1].kind), ('0', '100', ValidationKind.whole));
      expect((back[2].min, back[2].max, back[2].kind), ('0.5', '9.5', ValidationKind.decimal));
    });

    test('rules the app does not know stay in the file', () {
      final base = writeXlsx(newWorkbook());
      final changed = withSheetXml(
        base,
        (x) => x.replaceFirst(
          '</worksheet>',
          '<dataValidations count="2">'
          '<dataValidation type="list" sqref="D1:D5"><formula1>\$A\$1:\$A\$3</formula1></dataValidation>'
          '<dataValidation type="date" operator="greaterThan" sqref="E1"><formula1>45000</formula1></dataValidation>'
          '</dataValidations></worksheet>',
        ),
      );
      final wb = readXlsx(changed);
      expect(wb.sheets.first.validations, isEmpty);
      SheetEditor(wb).addValidation(wb.sheets.first, list('A1', ['x', 'y']));
      final saved = partText(writeXlsx(wb), 'xl/worksheets/sheet1.xml');
      expect(saved, contains('<dataValidations count="3">'));
      expect(saved, contains(r'$A$1:$A$3'));
      expect(saved, contains('type="date"'));
      expect(saved, contains('"x,y"'));

      final again = readXlsx(writeXlsx(wb));
      SheetEditor(again).clearValidations(again.sheets.first, range('A1:A1'));
      final cleared = partText(writeXlsx(again), 'xl/worksheets/sheet1.xml');
      expect(cleared, contains('<dataValidations count="2">'));
      expect(cleared, isNot(contains('"x,y"')));
    });

    test('removing the last rule removes the empty container', () {
      final wb = newWorkbook();
      final e = SheetEditor(wb);
      e.addValidation(wb.sheets.first, list('A1', ['x']));
      final reopened = readXlsx(writeXlsx(wb));
      SheetEditor(reopened).clearValidations(reopened.sheets.first, range('A1'));
      expect(partText(writeXlsx(reopened), 'xl/worksheets/sheet1.xml'), isNot(contains('dataValidations')));
    });
  });

  group('the rule sheet', () {
    Future<ValidationRule?> open(WidgetTester tester, Future<void> Function() act) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      ValidationRule? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(builder: (context) => TextButton(onPressed: () async => result = await askValidation(context), child: const Text('open'))),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      return result;
    }

    testWidgets('a list needs at least one choice and splits them at the commas', (tester) async {
      final rule = (await open(tester, () async {
        expect(tester.widget<FilledButton>(find.byKey(const ValueKey('valid_apply'))).onPressed, isNull);
        await tester.enterText(find.byKey(const ValueKey('valid_items')), 'Red, Green ,, Blue');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('valid_apply')));
        await tester.pumpAndSettle();
      }))!;
      expect(rule.kind, ValidationKind.list);
      expect(rule.items, ['Red', 'Green', 'Blue']);
    });

    testWidgets('a number rule needs both limits as numbers', (tester) async {
      final rule = (await open(tester, () async {
        await tester.tap(find.byKey(const ValueKey('valid_kind_decimal')));
        await tester.pump();
        await tester.enterText(find.byKey(const ValueKey('valid_min')), '0');
        await tester.enterText(find.byKey(const ValueKey('valid_max')), 'x');
        await tester.pump();
        expect(tester.widget<FilledButton>(find.byKey(const ValueKey('valid_apply'))).onPressed, isNull);
        await tester.enterText(find.byKey(const ValueKey('valid_max')), '5.5');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('valid_apply')));
        await tester.pumpAndSettle();
      }))!;
      expect((rule.kind, rule.min, rule.max), (ValidationKind.decimal, '0', '5.5'));
    });
  });
}

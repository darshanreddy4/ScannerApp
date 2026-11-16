import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/cond_format.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_edit.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:doculoom/features/office/sheets/presentation/cond_format_dialog.dart';

const _red = DxfStyle(fill: 0xFFFFC7CE, fontColor: 0xFF9C0006);
const _green = DxfStyle(fill: 0xFFC6EFCE, fontColor: 0xFF006100, bold: true);

MergeRange range(String text) => CellRef.parseRange(text)!;

Workbook workbookWith(Map<String, Object> values) {
  final wb = newWorkbook();
  final e = SheetEditor(wb);
  values.forEach((ref, v) {
    final p = CellRef.parse(ref)!;
    e.setInput(wb.sheets.first, p.row, p.col, '$v');
  });
  return wb;
}

CellStyle styled(Sheet s, String ref, {CellStyle base = CellStyle.plain}) {
  final p = CellRef.parse(ref)!;
  return CondContext(s).apply(base, p.row, p.col);
}

String partText(Uint8List bytes, String name) => utf8.decode(ZipDecoder().decodeBytes(bytes).findFile(name)!.readBytes()!);

void main() {
  group('which cells a rule picks', () {
    Sheet sheetOf(Map<String, Object> values) => workbookWith(values).sheets.first;

    test('numbers are compared as numbers, text as text, and empty cells never match', () {
      final s = sheetOf({'A1': 5, 'A2': 10, 'A3': 15, 'A4': 'abc', 'A5': 'Zed'});
      s.condRules.add(CondRule(range: range('A1:A6'), kind: CondKind.greater, a: '9', look: _red));
      expect(styled(s, 'A1').fill, isNull);
      expect(styled(s, 'A2').fill, _red.fill);
      expect(styled(s, 'A3').fontColor, _red.fontColor);
      expect(styled(s, 'A4').fill, isNull, reason: 'text is not greater than a number');
      expect(styled(s, 'A6').fill, isNull, reason: 'empty');

      s.condRules
        ..clear()
        ..add(CondRule(range: range('A1:A5'), kind: CondKind.greater, a: 'b', look: _red));
      expect(styled(s, 'A4').fill, isNull, reason: 'abc sorts before b');
      expect(styled(s, 'A5').fill, _red.fill, reason: 'Zed sorts after b when case is ignored');
    });

    test('less, equal, not equal and between', () {
      final s = sheetOf({'A1': 5, 'A2': 10, 'A3': 15});
      bool hit(CondKind k, String a, [String b = '']) {
        s.condRules
          ..clear()
          ..add(CondRule(range: range('A1:A3'), kind: k, a: a, b: b, look: _red));
        return [for (final r in ['A1', 'A2', 'A3']) styled(s, r).fill == _red.fill].where((x) => x).length == 1;
      }

      expect(hit(CondKind.less, '6'), isTrue);
      expect(hit(CondKind.equal, '10'), isTrue);
      expect(hit(CondKind.between, '12', '20'), isTrue, reason: 'only 15');
      expect(hit(CondKind.between, '20', '12'), isTrue, reason: 'the limits may be given in any order');
      s.condRules
        ..clear()
        ..add(CondRule(range: range('A1:A3'), kind: CondKind.notEqual, a: '10', look: _red));
      expect([for (final r in ['A1', 'A2', 'A3']) styled(s, r).fill == _red.fill], [true, false, true]);
    });

    test('text contains ignores case; duplicates are found inside the range only', () {
      final s = sheetOf({'A1': 'Paid in full', 'A2': 'Due', 'A3': 'PAID', 'B1': 'due', 'B2': 'due', 'B3': 'Due'});
      s.condRules.add(CondRule(range: range('A1:A3'), kind: CondKind.textContains, a: 'paid', look: _green));
      expect([for (final r in ['A1', 'A2', 'A3']) styled(s, r).bold], [true, false, true]);
      s.condRules
        ..clear()
        ..add(CondRule(range: range('B1:B3'), kind: CondKind.duplicates, look: _red));
      expect([for (final r in ['B1', 'B2', 'B3']) styled(s, r).fill == _red.fill], [true, true, true], reason: 'due, due and Due are the same');
      expect(styled(s, 'A2').fill, isNull, reason: 'A2 is outside the range');
    });

    test('the first rule wins where two change the same thing, and others keep their look', () {
      final s = sheetOf({'A1': 50});
      s.condRules
        ..add(CondRule(range: range('A1'), kind: CondKind.greater, a: '10', look: _red))
        ..add(CondRule(range: range('A1'), kind: CondKind.greater, a: '20', look: _green));
      final out = styled(s, 'A1', base: const CellStyle(italic: true, numFmt: '0.00'));
      expect(out.fill, _red.fill);
      expect(out.fontColor, _red.fontColor);
      expect(out.bold, isTrue, reason: 'bold from the second rule is still added');
      expect(out.italic, isTrue);
      expect(out.numFmt, '0.00');
    });

    test('a colour scale runs from the lowest to the highest number', () {
      final s = sheetOf({'A1': 0, 'A2': 5, 'A3': 10, 'A4': 'text'});
      s.condRules.add(CondRule(range: range('A1:A4'), kind: CondKind.scale, scale: const [0xFF000000, 0xFFFFFFFF]));
      expect(styled(s, 'A1').fill, 0xFF000000);
      expect(styled(s, 'A3').fill, 0xFFFFFFFF);
      expect(styled(s, 'A2').fill, 0xFF808080);
      expect(styled(s, 'A4').fill, isNull);
      s.condRules
        ..clear()
        ..add(CondRule(range: range('A1:A3'), kind: CondKind.scale, scale: const [0xFFFF0000, 0xFFFFFF00, 0xFF00FF00]));
      expect(styled(s, 'A1').fill, 0xFFFF0000);
      expect(styled(s, 'A2').fill, 0xFFFFFF00, reason: 'the middle is the median');
      expect(styled(s, 'A3').fill, 0xFF00FF00);
    });
  });

  group('saving and reopening', () {
    test('rules and their looks survive a save, and the file gets real conditional formatting', () {
      final wb = workbookWith({'A1': 5, 'A2': 50, 'B1': 'x', 'B2': 'y'});
      final e = SheetEditor(wb);
      final s = wb.sheets.first;
      e.addCondRule(s, CondRule(range: range('A1:A2'), kind: CondKind.between, a: '10', b: '60', look: _green));
      e.addCondRule(s, CondRule(range: range('B1:B2'), kind: CondKind.textContains, a: 'say "x"', look: _red));
      e.addCondRule(s, CondRule(range: range('A1:A2'), kind: CondKind.scale, scale: const [0xFFF8696B, 0xFFFFEB84, 0xFF63BE7B]));
      e.addCondRule(s, CondRule(range: range('B1'), kind: CondKind.duplicates, look: _red));
      final bytes = writeXlsx(wb);

      final sheetXml = partText(bytes, 'xl/worksheets/sheet1.xml');
      expect(sheetXml, contains('type="cellIs"'));
      expect(sheetXml, contains('operator="between"'));
      expect(sheetXml, contains('type="containsText"'));
      expect(sheetXml, contains('type="colorScale"'));
      expect(sheetXml, contains('type="duplicateValues"'));
      expect(sheetXml.indexOf('</sheetData>'), lessThan(sheetXml.indexOf('<conditionalFormatting')), reason: 'rules come after the cells');
      final styles = partText(bytes, 'xl/styles.xml');
      expect(styles, contains('<dxfs count="2">'), reason: 'the red look is shared');

      final back = readXlsx(bytes).sheets.first;
      expect(back.condRules, hasLength(4));
      final between = back.condRules.firstWhere((r) => r.kind == CondKind.between);
      expect((between.a, between.b, between.range.toString(), between.look), ('10', '60', 'A1:A2', _green));
      final text = back.condRules.firstWhere((r) => r.kind == CondKind.textContains);
      expect(text.a, 'say "x"');
      expect(text.look, _red);
      expect(back.condRules.firstWhere((r) => r.kind == CondKind.scale).scale, [0xFFF8696B, 0xFFFFEB84, 0xFF63BE7B]);
      final dup = back.condRules.firstWhere((r) => r.kind == CondKind.duplicates);
      expect(dup.range.toString(), 'B1:B1');
    });

    test('rules the app does not know stay in the file when others are changed', () {
      final base = writeXlsx(workbookWith({'A1': 1, 'A2': 2}));
      final archive = ZipDecoder().decodeBytes(base);
      final xml = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.readBytes()!).replaceFirst(
        '</worksheet>',
        '<conditionalFormatting sqref="A1:A2"><cfRule type="dataBar" priority="1"><dataBar><cfvo type="min"/><cfvo type="max"/><color rgb="FF638EC6"/></dataBar></cfRule></conditionalFormatting>'
        '<conditionalFormatting sqref="A1"><cfRule type="expression" dxfId="0" priority="2"><formula>MOD(ROW(),2)=0</formula></cfRule></conditionalFormatting></worksheet>',
      );
      final out = Archive();
      for (final f in archive.files) {
        out.addFile(f.name == 'xl/worksheets/sheet1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(xml)) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      final wb = readXlsx(Uint8List.fromList(ZipEncoder().encode(out)));
      expect(wb.sheets.first.condRules, isEmpty, reason: 'not shown by the app');

      SheetEditor(wb).addCondRule(wb.sheets.first, CondRule(range: range('A1:A2'), kind: CondKind.greater, a: '1', look: _red));
      final saved = partText(writeXlsx(wb), 'xl/worksheets/sheet1.xml');
      expect(saved, contains('type="dataBar"'));
      expect(saved, contains('type="expression"'));
      expect(saved, contains('type="cellIs"'));

      // Changing the app's own rules again does not duplicate them or touch the others.
      final again = readXlsx(writeXlsx(wb));
      SheetEditor(again).clearCondRules(again.sheets.first, null);
      final cleared = partText(writeXlsx(again), 'xl/worksheets/sheet1.xml');
      expect(cleared, contains('type="dataBar"'));
      expect(cleared, isNot(contains('type="cellIs"')));
    });

    test('rules from Excel that use cell references or other operators are left alone', () {
      final base = writeXlsx(workbookWith({'A1': 1}));
      final archive = ZipDecoder().decodeBytes(base);
      final xml = utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.readBytes()!).replaceFirst(
        '</worksheet>',
        '<conditionalFormatting sqref="A1"><cfRule type="cellIs" dxfId="0" priority="1" operator="greaterThan"><formula>\$B\$1</formula></cfRule></conditionalFormatting>'
        '<conditionalFormatting sqref="A1"><cfRule type="containsText" dxfId="0" priority="2" operator="beginsWith" text="a"><formula>LEFT(A1,1)="a"</formula></cfRule></conditionalFormatting></worksheet>',
      );
      final out = Archive();
      for (final f in archive.files) {
        out.addFile(f.name == 'xl/worksheets/sheet1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(xml)) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      expect(readXlsx(Uint8List.fromList(ZipEncoder().encode(out))).sheets.first.condRules, isEmpty);
    });

    test('a file with its own looks keeps them, and the same look is not added twice', () {
      final wb = workbookWith({'A1': 5});
      final e = SheetEditor(wb);
      e.addCondRule(wb.sheets.first, CondRule(range: range('A1'), kind: CondKind.greater, a: '1', look: _red));
      final first = writeXlsx(wb);
      final reopened = readXlsx(first);
      SheetEditor(reopened).addCondRule(reopened.sheets.first, CondRule(range: range('A2:A3'), kind: CondKind.less, a: '1', look: _red));
      final second = partText(writeXlsx(reopened), 'xl/styles.xml');
      expect(second, contains('<dxfs count="1">'));
    });
  });

  group('editing', () {
    test('undo and redo bring rules back and take them away', () {
      final wb = workbookWith({'A1': 5});
      final e = SheetEditor(wb);
      final s = wb.sheets.first;
      e.addCondRule(s, CondRule(range: range('A1'), kind: CondKind.greater, a: '1', look: _red));
      expect(s.condRules, hasLength(1));
      e.undo();
      expect(s.condRules, isEmpty);
      e.redo();
      expect(s.condRules, hasLength(1));
      expect(e.clearCondRules(s, range('C1:C2')), 0, reason: 'nothing touches that range');
      expect(e.clearCondRules(s, range('A1:B5')), 1);
      expect(s.condRules, isEmpty);
    });

    test('rules follow their cells when rows and columns are inserted or removed', () {
      final wb = workbookWith({'A2': 5});
      final e = SheetEditor(wb);
      final s = wb.sheets.first;
      e.addCondRule(s, CondRule(range: range('B2:C4'), kind: CondKind.greater, a: '1', look: _red));
      e.insertRows(s, 0);
      expect(s.condRules.single.range.toString(), 'B3:C5');
      e.deleteRows(s, 2, 2);
      expect(s.condRules.single.range.toString(), 'B3:C3');
      e.insertCols(s, 0);
      expect(s.condRules.single.range.toString(), 'C3:D3');
      e.deleteRows(s, 2);
      expect(s.condRules, isEmpty, reason: 'its only row was removed');
    });
  });

  group('the highlight sheet', () {
    Future<CondRule?> open(WidgetTester tester, Future<void> Function() act) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      CondRule? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(onPressed: () async => result = await askHighlight(context), child: const Text('open')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      return result;
    }

    testWidgets('a value rule needs its value, then comes back with the chosen look', (tester) async {
      final result = open(tester, () async {
        expect(tester.widget<FilledButton>(find.byKey(const ValueKey('cond_apply'))).onPressed, isNull);
        await tester.enterText(find.byKey(const ValueKey('cond_a')), '100');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('cond_look_2')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('cond_apply')));
        await tester.pumpAndSettle();
      });
      final rule = (await result)!;
      expect((rule.kind, rule.a, rule.look), (CondKind.greater, '100', condLooks[2].$2));
    });

    testWidgets('between asks for two values', (tester) async {
      final rule = (await open(tester, () async {
        await tester.tap(find.byKey(const ValueKey('cond_kind_between')));
        await tester.pump();
        await tester.enterText(find.byKey(const ValueKey('cond_a')), '1');
        await tester.pump();
        expect(tester.widget<FilledButton>(find.byKey(const ValueKey('cond_apply'))).onPressed, isNull);
        await tester.enterText(find.byKey(const ValueKey('cond_b')), '9');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('cond_apply')));
        await tester.pumpAndSettle();
      }))!;
      expect((rule.kind, rule.a, rule.b), (CondKind.between, '1', '9'));
    });

    testWidgets('duplicates and colour scales need no value', (tester) async {
      final rule = (await open(tester, () async {
        await tester.tap(find.byKey(const ValueKey('cond_kind_scale')));
        await tester.pump();
        expect(find.byKey(const ValueKey('cond_a')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('cond_scale_2')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('cond_apply')));
        await tester.pumpAndSettle();
      }))!;
      expect(rule.kind, CondKind.scale);
      expect(rule.scale, condScales[2].$2);
    });
  });
}

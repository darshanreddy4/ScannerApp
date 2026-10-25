import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/office/sheets/domain/sheet_edit.dart';
import 'package:scanvault/features/office/sheets/domain/sheet_model.dart';

SheetEditor editor({int sheets = 1}) {
  final wb = Workbook(
    sheets: [for (var i = 0; i < sheets; i++) Sheet(name: i == 0 ? 'Sheet1' : 'Other ${i + 1}')],
    styles: StyleTable(),
  );
  return SheetEditor(wb);
}

CellValue v(Sheet s, String ref) {
  final p = CellRef.parse(ref)!;
  return s.cellAt(p.row, p.col).value;
}

double num(Sheet s, String ref) => (v(s, ref) as NumberValue).number;
String? formula(Sheet s, String ref) {
  final p = CellRef.parse(ref)!;
  return s.cellAt(p.row, p.col).formula;
}

void put(SheetEditor e, Sheet s, String ref, String text) {
  final p = CellRef.parse(ref)!;
  e.setInput(s, p.row, p.col, text);
}

void main() {
  test('typed text becomes numbers, formulas, booleans, dates, percents and text', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', '12.5');
    put(e, s, 'A2', '1,234');
    put(e, s, 'A3', '=A1*2');
    put(e, s, 'A4', 'true');
    put(e, s, 'A5', '25%');
    put(e, s, 'A6', '2024-03-05');
    put(e, s, 'A7', "'007");
    put(e, s, 'A8', 'hello');
    expect(num(s, 'A1'), 12.5);
    expect(num(s, 'A2'), 1234);
    expect(num(s, 'A3'), 25);
    expect((v(s, 'A4') as BoolValue).flag, isTrue);
    expect(num(s, 'A5'), 0.25);
    expect(e.workbook.styles.at(s.cellAt(4, 0).style).numFmt, '0%');
    expect(num(s, 'A6'), 45356);
    expect(e.workbook.styles.at(s.cellAt(5, 0).style).numFmt, 'yyyy-mm-dd');
    expect((v(s, 'A7') as TextValue).text, '007');
    expect((v(s, 'A8') as TextValue).text, 'hello');
  });

  test('editing recalculates dependants, and undo and redo restore everything', () {
    final e = editor(sheets: 2);
    final a = e.workbook.sheets[0], b = e.workbook.sheets[1];
    put(e, a, 'A1', '5');
    put(e, b, 'A1', "='Sheet1'!A1*10");
    expect(num(b, 'A1'), 50);
    put(e, a, 'A1', '6');
    expect(num(b, 'A1'), 60);
    e.undo();
    expect(num(a, 'A1'), 5);
    expect(num(b, 'A1'), 50);
    e.undo();
    expect(v(b, 'A1'), isA<EmptyValue>());
    e.redo();
    expect(num(b, 'A1'), 50);
    e.redo();
    expect(num(b, 'A1'), 60);
    expect(e.canRedo, isFalse);
  });

  test('inserting and deleting rows moves cells and keeps formulas pointing at the same data', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', '1');
    put(e, s, 'A2', '2');
    put(e, s, 'A3', '3');
    put(e, s, 'B1', '=SUM(A1:A3)');
    put(e, s, 'B2', r'=$A$3+A2');
    e.insertRows(s, 1);
    expect(num(s, 'A3'), 2);
    expect(num(s, 'A4'), 3);
    expect(formula(s, 'B1'), 'SUM(A1:A4)');
    expect(formula(s, 'B3'), r'$A$4+A3');
    expect(num(s, 'B1'), 6);
    e.deleteRows(s, 1);
    expect(formula(s, 'B1'), 'SUM(A1:A3)');
    e.deleteRows(s, 1);
    expect(num(s, 'B1'), 4);
    expect(formula(s, 'B1'), 'SUM(A1:A2)');
    expect(formula(s, 'B2'), isNull, reason: 'the row that held B2 was deleted');
    e.undo();
    e.undo();
    e.undo();
    expect(formula(s, 'B1'), 'SUM(A1:A3)');
    expect(num(s, 'A2'), 2);
  });

  test('deleting a referenced row gives #REF!', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', '1');
    put(e, s, 'A2', '2');
    put(e, s, 'B1', '=A2+1');
    e.deleteRows(s, 1);
    expect(formula(s, 'B1'), '#REF!+1');
    expect((v(s, 'B1') as ErrorValue).code, isNotEmpty);
  });

  test('inserting columns moves widths, merges and references on other sheets', () {
    final e = editor(sheets: 2);
    final a = e.workbook.sheets[0], b = e.workbook.sheets[1];
    put(e, a, 'B1', '4');
    a.colWidths[1] = 30;
    e.merge(a, const MergeRange(0, 1, 0, 2));
    put(e, b, 'A1', '=Sheet1!B1+1');
    e.insertCols(a, 0);
    expect(num(a, 'C1'), 4);
    expect(a.colWidths[2], 30);
    expect(a.merges.single.toString(), 'C1:D1');
    expect(formula(b, 'A1'), 'Sheet1!C1+1');
    expect(num(b, 'A1'), 5);
  });

  test('copy and paste shifts relative references, cut keeps them', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', '2');
    put(e, s, 'B1', '=A1*3');
    e.paste(s, 1, 0, e.copy(s, const MergeRange(0, 0, 0, 1)));
    expect(formula(s, 'B2'), 'A2*3');
    e.paste(s, 3, 0, e.copy(s, const MergeRange(0, 0, 0, 1), cut: true));
    expect(formula(s, 'B4'), 'A1*3');
    expect(v(s, 'A1'), isA<EmptyValue>());
  });

  test('sorting orders rows, keeps formulas on their row, and leaves a header', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    for (final (i, n) in [(1, 'pear'), (2, 'Apple'), (3, 'fig')]) {
      put(e, s, 'A${i + 1}', n);
      put(e, s, 'B${i + 1}', '${i * 10}');
      put(e, s, 'C${i + 1}', '=B${i + 1}*2');
    }
    put(e, s, 'A1', 'Name');
    e.sort(s, const MergeRange(0, 0, 3, 2), byCol: 0, ascending: true, hasHeader: true);
    expect([v(s, 'A1'), v(s, 'A2'), v(s, 'A3'), v(s, 'A4')].map((x) => (x as TextValue).text), ['Name', 'Apple', 'fig', 'pear']);
    expect(num(s, 'B2'), 20);
    expect(formula(s, 'C2'), 'B2*2');
    expect(num(s, 'C2'), 40);
    e.sort(s, const MergeRange(0, 0, 3, 2), byCol: 1, ascending: false, hasHeader: true);
    expect(num(s, 'B2'), 30);
  });

  test('style changes make new styles once and apply to empty cells too', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', '1');
    e.setStyle(s, const MergeRange(0, 0, 1, 1), (st) => st.copyWith(bold: true));
    expect(e.workbook.styles.at(s.cellAt(0, 0).style).bold, isTrue);
    expect(e.workbook.styles.at(s.cellAt(1, 1).style).bold, isTrue);
    expect(e.workbook.styles.styles.length, 2);
    e.undo();
    expect(e.workbook.styles.at(s.cellAt(0, 0).style).bold, isFalse);
  });

  test('sheets can be added, renamed (formulas follow), moved, duplicated and deleted (references break)', () {
    final e = editor();
    final a = e.workbook.sheets.first;
    final b = e.addSheet('Data');
    put(e, b, 'A1', '9');
    put(e, a, 'A1', '=Data!A1+1');
    expect(num(a, 'A1'), 10);
    expect(e.renameSheet(b, 'My Data'), isTrue);
    expect(formula(a, 'A1'), "'My Data'!A1+1");
    expect(num(a, 'A1'), 10);
    expect(e.renameSheet(b, 'sheet1'), isFalse);
    final c = e.duplicateSheet(b);
    expect(c.partPath, isNull);
    expect(num(c, 'A1'), 9);
    e.moveSheet(2, 0);
    expect(e.workbook.sheets.first, c);
    expect(e.deleteSheet(b), isTrue);
    expect(formula(a, 'A1'), '#REF!+1');
    e.undo();
    expect(e.workbook.sheets, contains(b));
    expect(formula(a, 'A1'), "'My Data'!A1+1");
    expect(e.workbook.structureChanged, isTrue);
  });

  test('the last visible sheet cannot be deleted', () {
    final e = editor();
    expect(e.deleteSheet(e.workbook.sheets.first), isFalse);
  });

  test('find looks at shown text and formulas', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', 'Apple pie');
    put(e, s, 'B2', '=LEN(A1)');
    put(e, s, 'C3', '42');
    expect(e.find(s, 'apple').map((p) => '${p.row},${p.col}'), ['0,0']);
    expect(e.find(s, 'len(').length, 1);
    expect(e.find(s, 'APPLE', matchCase: true), isEmpty);
  });

  test('merge keeps only the top-left value and unmerge frees the cells', () {
    final e = editor();
    final s = e.workbook.sheets.first;
    put(e, s, 'A1', 'keep');
    put(e, s, 'B1', 'drop');
    e.merge(s, const MergeRange(0, 0, 0, 1));
    expect(v(s, 'B1'), isA<EmptyValue>());
    expect(s.mergeAt(0, 1), isNotNull);
    e.unmerge(s, const MergeRange(0, 0, 0, 0));
    expect(s.merges, isEmpty);
  });
}

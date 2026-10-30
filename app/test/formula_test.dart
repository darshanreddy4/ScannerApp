import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/domain/formula.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';

Workbook book(Map<String, Object?> cells, {Map<String, Object?>? second}) {
  Sheet make(String name, Map<String, Object?> data) {
    final s = Sheet(name: name);
    data.forEach((ref, v) {
      final p = CellRef.parse(ref)!;
      if (v is String && v.startsWith('=')) {
        s.setCell(p.row, p.col, SheetCell(formula: v.substring(1)));
      } else {
        s.setCell(p.row, p.col, SheetCell(value: v is num ? NumberValue(v.toDouble()) : (v is bool ? BoolValue(v) : TextValue(v as String))));
      }
    });
    return s;
  }

  return Workbook(sheets: [make('Sheet1', cells), if (second != null) make('Other Sheet', second)], styles: StyleTable());
}

Object? calc(String formula, [Map<String, Object?> cells = const {}, Map<String, Object?>? second]) {
  final wb = book({...cells, 'Z99': '=$formula'}, second: second);
  FormulaEngine(wb, now: DateTime(2024, 5, 17, 10, 30)).recalculateAll();
  final v = wb.sheets.first.cellAt(98, 25).value;
  return switch (v) {
    NumberValue(:final number) => number,
    TextValue(:final text) => text,
    BoolValue(:final flag) => flag,
    ErrorValue(:final code) => code,
    EmptyValue() => null,
  };
}

void main() {
  const data = {'A1': 1, 'A2': 2, 'A3': 3, 'A4': 'x', 'B1': 10, 'B2': 20, 'B3': 30, 'C1': 'apple', 'C2': 'Banana', 'C3': 'apricot'};

  test('arithmetic, precedence and operators', () {
    expect(calc('1+2*3'), 7);
    expect(calc('(1+2)*3'), 9);
    expect(calc('2^3^2'), 64, reason: 'left to right as Excel does');
    expect(calc('-2^2'), 4);
    expect(calc('50%'), 0.5);
    expect(calc('10/4'), 2.5);
    expect(calc('1/0'), '#DIV/0!');
    expect(calc('"a"&"b"&1'), 'ab1');
    expect(calc('1<2'), true);
    expect(calc('"a"="A"'), true);
    expect(calc('1<>1'), false);
    expect(calc('"7"+1'), 8);
    expect(calc('"abc"+1'), '#VALUE!');
  });

  test('references, ranges and cross-sheet references', () {
    expect(calc('A1+B2', data), 21);
    expect(calc('SUM(A1:A3)', data), 6);
    expect(calc('SUM(A:A)', data), 6);
    expect(calc('SUM(1:1)', data), 11);
    expect(calc("'Other Sheet'!A1*2", data, {'A1': 4}), 8);
    expect(calc('Nope!A1', data), '#REF!');
    expect(calc(r'SUM($A$1:$A$3)', data), 6);
  });

  test('math and aggregates', () {
    expect(calc('AVERAGE(A1:A3)', data), 2);
    expect(calc('MIN(A1:B3)', data), 1);
    expect(calc('MAX(A1:B3)', data), 30);
    expect(calc('COUNT(A1:A4)', data), 3);
    expect(calc('COUNTA(A1:A4)', data), 4);
    expect(calc('COUNTBLANK(A1:A5)', data), 1);
    expect(calc('MEDIAN(1,2,3,4)'), 2.5);
    expect(calc('PRODUCT(2,3,4)'), 24);
    expect(calc('ROUND(2.675,2)'), 2.68);
    expect(calc('ROUND(-2.5,0)'), -3);
    expect(calc('ROUND(1234,-2)'), 1200);
    expect(calc('ROUNDUP(1.21,1)'), 1.3);
    expect(calc('ROUNDDOWN(-1.99,1)'), -1.9);
    expect(calc('INT(-1.5)'), -2);
    expect(calc('MOD(-3,2)'), 1);
    expect(calc('SQRT(-1)'), '#NUM!');
    expect(calc('POWER(2,10)'), 1024);
    expect(calc('LARGE(A1:A3,2)', data), 2);
    expect(calc('SUMPRODUCT(A1:A3,B1:B3)', data), 140);
    expect(calc('AVERAGE(A4)', data), '#DIV/0!');
  });

  test('logic', () {
    expect(calc('IF(A1>0,"yes","no")', data), 'yes');
    expect(calc('IF(A1>5,"yes")', data), false);
    expect(calc('IFERROR(1/0,"oops")'), 'oops');
    expect(calc('AND(1,A1=1)', data), true);
    expect(calc('OR(0,0)'), false);
    expect(calc('NOT(TRUE)'), false);
    expect(calc('IFS(A1>5,"big",A1>0,"small")', data), 'small');
    expect(calc('SWITCH(A2,1,"one",2,"two","many")', data), 'two');
    expect(calc('CHOOSE(2,"a","b")'), 'b');
    expect(calc('ISBLANK(Q5)'), true);
    expect(calc('ISNUMBER(A1)', data), true);
    expect(calc('ISERROR(1/0)'), true);
  });

  test('text', () {
    expect(calc('LEN("hello")'), 5);
    expect(calc('UPPER("ab")&LOWER("CD")'), 'ABcd');
    expect(calc('LEFT("hello",2)&RIGHT("hello",2)'), 'helo');
    expect(calc('MID("hello",2,3)'), 'ell');
    expect(calc('TRIM("  a   b ")'), 'a b');
    expect(calc('SUBSTITUTE("a-b-c","-","+")'), 'a+b+c');
    expect(calc('SUBSTITUTE("a-b-c","-","+",2)'), 'a-b+c');
    expect(calc('FIND("l","hello")'), 3);
    expect(calc('SEARCH("L","hello")'), 3);
    expect(calc('FIND("z","hello")'), '#VALUE!');
    expect(calc('REPT("ab",3)'), 'ababab');
    expect(calc('CONCATENATE("a",1,TRUE)'), 'a1TRUE');
    expect(calc('PROPER("hello wORLD")'), 'Hello World');
    expect(calc('TEXT(1234.5,"#,##0.00")'), '1,234.50');
    expect(calc('VALUE("12.5")'), 12.5);
  });

  test('conditional aggregates and lookups', () {
    expect(calc('SUMIF(A1:A3,">1")', data), 5);
    expect(calc('SUMIF(A1:A3,">=2",B1:B3)', data), 50);
    expect(calc('COUNTIF(C1:C3,"a*")', data), 2);
    expect(calc('COUNTIF(C1:C3,"banana")', data), 1);
    expect(calc('COUNTIF(A1:A3,2)', data), 1);
    expect(calc('AVERAGEIF(A1:A3,"<3")', data), 1.5);
    expect(calc('COUNTIFS(A1:A3,">1",B1:B3,"<30")', data), 1);
    expect(calc('SUMIFS(B1:B3,A1:A3,">1")', data), 50);
    expect(calc('VLOOKUP(2,A1:B3,2,FALSE)', data), 20);
    expect(calc('VLOOKUP(2.5,A1:B3,2)', data), 20);
    expect(calc('VLOOKUP(9,A1:B3,2,FALSE)', data), '#N/A');
    expect(calc('HLOOKUP(10,A1:B3,2,FALSE)', data), 20);
    expect(calc('INDEX(A1:B3,2,2)', data), 20);
    expect(calc('MATCH(30,B1:B3,0)', data), 3);
    expect(calc('MATCH(25,B1:B3,1)', data), 2);
  });

  test('dates', () {
    expect(calc('DATE(2024,5,17)'), 45429);
    expect(calc('YEAR(45429)'), 2024);
    expect(calc('MONTH(45429)'), 5);
    expect(calc('DAY(45429)'), 17);
    expect(calc('TODAY()'), 45429);
    expect(calc('WEEKDAY(45429)'), 6);
  });

  test('formulas depending on formulas recalculate in order, even listed backwards', () {
    final wb = book({'A1': 5, 'A2': '=A3*2', 'A3': '=A1+1', 'A4': '=SUM(A1:A3)'});
    FormulaEngine(wb).recalculateAll();
    double v(String r) {
      final p = CellRef.parse(r)!;
      return (wb.sheets.first.cellAt(p.row, p.col).value as NumberValue).number;
    }

    expect(v('A3'), 6);
    expect(v('A2'), 12);
    expect(v('A4'), 23);
    wb.sheets.first.setCell(0, 0, const SheetCell(value: NumberValue(10)));
    FormulaEngine(wb).recalculateAll();
    expect(v('A4'), 10 + 22 + 11);
  });

  test('circular references show an error instead of hanging', () {
    final wb = book({'A1': '=B1+1', 'B1': '=A1+1'});
    FormulaEngine(wb).recalculateAll();
    expect(wb.sheets.first.cellAt(0, 0).value, isA<ErrorValue>());
  });

  test('unknown functions keep the value stored in the file', () {
    final wb = book({'A1': 7});
    wb.sheets.first.setCell(1, 0, const SheetCell(value: NumberValue(99), formula: 'XLOOKUP(1,A1:A1,A1:A1)'));
    wb.sheets.first.setCell(2, 0, const SheetCell(formula: 'A2+1'));
    FormulaEngine(wb).recalculateAll();
    expect((wb.sheets.first.cellAt(1, 0).value as NumberValue).number, 99);
    expect((wb.sheets.first.cellAt(2, 0).value as NumberValue).number, 100);
    expect(FormulaEngine.isSupported('XLOOKUP(1,A1,A2)'), isFalse);
    expect(FormulaEngine.isSupported('SUM(A1:A3)'), isTrue);
  });

  test('syntax errors do not throw', () {
    expect(calc('1+'), '#VALUE!');
    expect(calc('SUM(1,'), '#VALUE!');
    expect(calc('"open'), '#VALUE!');
  });
}

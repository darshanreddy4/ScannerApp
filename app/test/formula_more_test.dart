import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/domain/formula.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';

Object? calc(String formula, [Map<String, Object?> cells = const {}]) {
  final s = Sheet(name: 'Sheet1');
  void put(String ref, Object? v) {
    final p = CellRef.parse(ref)!;
    if (v is String && v.startsWith('=')) {
      s.setCell(p.row, p.col, SheetCell(formula: v.substring(1)));
    } else {
      s.setCell(p.row, p.col, SheetCell(value: v is num ? NumberValue(v.toDouble()) : (v is bool ? BoolValue(v) : TextValue(v as String))));
    }
  }

  cells.forEach(put);
  put('Z99', '=$formula');
  final wb = Workbook(sheets: [s], styles: StyleTable());
  FormulaEngine(wb, now: DateTime(2024, 5, 17, 10, 30)).recalculateAll();
  return switch (s.cellAt(98, 25).value) {
    NumberValue(:final number) => number,
    TextValue(:final text) => text,
    BoolValue(:final flag) => flag,
    ErrorValue(:final code) => code,
    EmptyValue() => null,
  };
}

void main() {
  const data = {'A1': 1, 'A2': 2, 'A3': 3, 'B1': 10, 'B2': 20, 'B3': 30, 'C1': 'apple', 'C2': 'Banana', 'C3': 'apricot'};

  test('conditional averages, maximum and minimum', () {
    expect(calc('AVERAGEIFS(B1:B3,A1:A3,">1")', data), 25);
    expect(calc('MAXIFS(B1:B3,A1:A3,"<3")', data), 20);
    expect(calc('MINIFS(B1:B3,A1:A3,">1")', data), 20);
    expect(calc('AVERAGEIFS(B1:B3,A1:A3,">9")', data), '#DIV/0!');
    expect(calc('MAXIFS(B1:B3,C1:C3,"a*")', data), 30);
  });

  test('XLOOKUP and LOOKUP', () {
    expect(calc('XLOOKUP(2,A1:A3,B1:B3)', data), 20);
    expect(calc('XLOOKUP(5,A1:A3,B1:B3,"none")', data), 'none');
    expect(calc('XLOOKUP(5,A1:A3,B1:B3)', data), '#N/A');
    expect(calc('XLOOKUP(2.5,A1:A3,B1:B3,,-1)', data), 20);
    expect(calc('XLOOKUP(2.5,A1:A3,B1:B3,,1)', data), 30);
    expect(calc('XLOOKUP("b*",C1:C3,A1:A3,,2)', data), 2);
    expect(calc('XLOOKUP("apple",C1:C3,A1:A3)', data), 1);
    expect(calc('LOOKUP(2.5,A1:A3,B1:B3)', data), 20);
    expect(calc('LOOKUP(0,A1:A3,B1:B3)', data), '#N/A');
  });

  test('text', () {
    expect(calc('TEXTJOIN(", ",TRUE,"a","","c")'), 'a, c');
    expect(calc('TEXTJOIN(", ",FALSE,"a","","c")'), 'a, , c');
    expect(calc('TEXTJOIN("-",TRUE,A1:A3)', data), '1-2-3');
    expect(calc('REPLACE("abcdef",2,3,"X")'), 'aXef');
    expect(calc('CODE("A")'), 65);
    expect(calc('CHAR(66)'), 'B');
    expect(calc('CLEAN("a"&CHAR(7)&"b")'), 'ab');
    expect(calc('T("x")'), 'x');
    expect(calc('T(1)'), '');
    expect(calc('N("x")'), 0);
    expect(calc('N(TRUE)'), 1);
    expect(calc('TEXTBEFORE("a-b-c","-")'), 'a');
    expect(calc('TEXTAFTER("a-b-c","-")'), 'b-c');
    expect(calc('TEXTBEFORE("a-b-c","-",2)'), 'a-b');
    expect(calc('TEXTAFTER("a-b-c","-",2)'), 'c');
    expect(calc('TEXTAFTER("abc","-")'), '#N/A');
  });

  test('dates', () {
    const from = 'DATE(2020,1,15)', to = 'DATE(2024,5,17)';
    expect(calc('DATEDIF($from,$to,"Y")'), 4);
    expect(calc('DATEDIF($from,$to,"M")'), 52);
    expect(calc('DATEDIF($from,$to,"D")'), 1584);
    expect(calc('DATEDIF($from,$to,"YM")'), 4);
    expect(calc('DATEDIF($from,$to,"MD")'), 2);
    expect(calc('DATEDIF($from,$to,"YD")'), 123);
    expect(calc('DATEDIF($to,$from,"D")'), '#NUM!');
    expect(calc('EDATE(DATE(2024,1,31),1)=DATE(2024,2,29)'), true);
    expect(calc('EDATE(DATE(2024,3,15),-3)=DATE(2023,12,15)'), true);
    expect(calc('EOMONTH(DATE(2024,2,10),0)=DATE(2024,2,29)'), true);
    expect(calc('EOMONTH(DATE(2024,2,10),1)=DATE(2024,3,31)'), true);
    expect(calc('DAYS(DATE(2024,5,17),DATE(2024,5,1))'), 16);
    expect(calc('NETWORKDAYS(DATE(2024,5,13),DATE(2024,5,19))'), 5);
    expect(calc('NETWORKDAYS(DATE(2024,5,19),DATE(2024,5,13))'), -5);
    expect(calc('NETWORKDAYS(DATE(2024,5,13),DATE(2024,5,19),A1)', {'A1': '=DATE(2024,5,15)'}), 4);
    expect(calc('WORKDAY(DATE(2024,5,17),1)=DATE(2024,5,20)'), true);
    expect(calc('WORKDAY(DATE(2024,5,17),-5)=DATE(2024,5,10)'), true);
    expect(calc('WEEKNUM(DATE(2024,5,17))'), 20);
    expect(calc('WEEKNUM(DATE(2024,1,1))'), 1);
    expect(calc('WEEKNUM(DATE(2024,5,17),2)'), 20);
  });

  test('statistics', () {
    const list = '2,4,4,4,5,5,7,9';
    expect(calc('STDEV.P($list)') as double, closeTo(2, 1e-9));
    expect(calc('STDEV.S($list)') as double, closeTo(2.1380899353, 1e-9));
    expect(calc('STDEV($list)') as double, closeTo(2.1380899353, 1e-9));
    expect(calc('VAR.P($list)') as double, closeTo(4, 1e-9));
    expect(calc('VAR.S($list)') as double, closeTo(4.5714285714, 1e-9));
    expect(calc('STDEV(1)'), '#DIV/0!');
    expect(calc('RANK(30,B1:B3)', data), 1);
    expect(calc('RANK(30,B1:B3,1)', data), 3);
    expect(calc('RANK(25,B1:B3)', data), '#N/A');
    expect(calc('PERCENTILE(B1:B3,0.5)', data), 20);
    expect(calc('PERCENTILE(B1:B3,0.25)', data), 15);
    expect(calc('PERCENTILE(B1:B3,2)', data), '#NUM!');
    expect(calc('QUARTILE(B1:B3,1)', data), 15);
    expect(calc('QUARTILE(B1:B3,4)', data), 30);
    expect(calc('MODE(1,2,2,3)'), 2);
    expect(calc('MODE(1,2,3)'), '#N/A');
    expect(calc('CORREL(A1:A3,B1:B3)', data) as double, closeTo(1, 1e-12));
    expect(calc('SLOPE(B1:B3,A1:A3)', data) as double, closeTo(10, 1e-12));
    expect(calc('INTERCEPT(B1:B3,A1:A3)', data) as double, closeTo(0, 1e-12));
    expect(calc('FORECAST(4,B1:B3,A1:A3)', data) as double, closeTo(40, 1e-12));
    expect(calc('SUBTOTAL(9,A1:A3)', data), 6);
    expect(calc('SUBTOTAL(1,A1:A3)', data), 2);
    expect(calc('SUBTOTAL(109,A1:A3)', data), 6);
    expect(calc('SUBTOTAL(2,A1:A3)', data), 3);
  });

  test('maths', () {
    expect(calc('FACT(5)'), 120);
    expect(calc('FACT(0)'), 1);
    expect(calc('FACT(-1)'), '#NUM!');
    expect(calc('COMBIN(5,2)'), 10);
    expect(calc('PERMUT(5,2)'), 20);
    expect(calc('GCD(12,18)'), 6);
    expect(calc('GCD(12,18,8)'), 2);
    expect(calc('LCM(4,6)'), 12);
    expect(calc('QUOTIENT(7,2)'), 3);
    expect(calc('QUOTIENT(-7,2)'), -3);
    expect(calc('MROUND(10,3)'), 9);
    expect(calc('MROUND(11,3)'), 12);
    expect(calc('MROUND(-10,3)'), '#NUM!');
    expect(calc('SIN(PI()/2)') as double, closeTo(1, 1e-12));
    expect(calc('COS(0)'), 1);
    expect(calc('ATAN2(1,1)') as double, closeTo(0.7853981634, 1e-9));
    expect(calc('ASIN(2)'), '#NUM!');
    expect(calc('RADIANS(180)') as double, closeTo(3.1415926536, 1e-9));
    expect(calc('DEGREES(PI())') as double, closeTo(180, 1e-9));
    expect(calc('ISEVEN(4)'), true);
    expect(calc('ISODD(4)'), false);
  });

  test('loans and savings', () {
    expect(calc('PMT(0.05/12,60,10000)') as double, closeTo(-188.7123359, 1e-6));
    expect(calc('PMT(0,10,1000)'), -100);
    expect(calc('FV(0.05/12,60,-100)') as double, closeTo(6800.6086, 1e-3));
    expect(calc('PV(0.05/12,60,-188.7123359)') as double, closeTo(10000, 1e-3));
    expect(calc('NPER(0.05/12,-188.7123359,10000)') as double, closeTo(60, 1e-6));
    expect(calc('NPV(0.1,100,100)') as double, closeTo(173.5537190, 1e-6));
    expect(calc('NPER(0.05,-1,10000)'), '#NUM!');
  });

  test('the new functions are listed as supported, not left unevaluated', () {
    for (final f in ['XLOOKUP(1,A1:A3,B1:B3)', 'TEXTJOIN(",",TRUE,"a")', 'PMT(0.01,12,100)', 'STDEV.S(1,2,3)']) {
      expect(calc(f, data), isNot(isA<String>().having((s) => s.startsWith('#NAME'), 'is name error', true)), reason: f);
    }
  });
}

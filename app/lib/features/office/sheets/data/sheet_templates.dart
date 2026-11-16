import '../domain/formula.dart';
import '../domain/number_format.dart';
import '../domain/sheet_model.dart';
import 'xlsx_writer.dart';

/// A ready-made spreadsheet to start from.
class SheetTemplate {
  const SheetTemplate({required this.id, required this.title, required this.hint, required this.group, required this.build});
  final String id;
  final String title;
  final String hint;

  /// For the picker: 'study', 'money' or 'work'.
  final String group;
  final Workbook Function() build;
}

const _head = CellStyle(bold: true, fontColor: 0xFFFFFFFF, fill: 0xFF2563EB, align: HAlign.center, wrap: true);
const _title = CellStyle(bold: true, fontSize: 16, fontColor: 0xFF1E3A8A);
const _label = CellStyle(bold: true);
const _note = CellStyle(italic: true, fontColor: 0xFF64748B);
const _money = CellStyle(numFmt: '#,##0.00');
const _moneyTotal = CellStyle(bold: true, numFmt: '#,##0.00', fill: 0xFFE8EEFB);
const _totalLabel = CellStyle(bold: true, fill: 0xFFE8EEFB);
const _pct = CellStyle(numFmt: '0.0%');
const _pctIn = CellStyle(numFmt: '0.0%', fill: 0xFFFFF8DB);
const _dateIn = CellStyle(numFmt: 'dd/mm/yyyy', align: HAlign.left, fill: 0xFFFFF8DB);
const _input = CellStyle(fill: 0xFFFFF8DB);
const _moneyIn = CellStyle(numFmt: '#,##0.00', fill: 0xFFFFF8DB);
const _center = CellStyle(align: HAlign.center);

/// Builds one sheet from cells given as A1 references.
class _T {
  _T(String name) : wb = newWorkbook(sheetName: name) {
    sheet = wb.sheets.first;
  }

  final Workbook wb;
  late final Sheet sheet;

  int _s(CellStyle? s) => s == null ? 0 : wb.styles.indexOf(s);

  void _put(String ref, SheetCell cell) {
    final p = CellRef.parse(ref)!;
    sheet.setCell(p.row, p.col, cell);
  }

  void text(String ref, String v, [CellStyle? s]) => _put(ref, SheetCell(value: TextValue(v), style: _s(s)));
  void number(String ref, double v, [CellStyle? s]) => _put(ref, SheetCell(value: NumberValue(v), style: _s(s)));
  void formula(String ref, String f, [CellStyle? s]) => _put(ref, SheetCell(formula: f, style: _s(s)));

  /// An empty cell that only carries a look, such as the yellow of a cell to type in.
  void blank(String ref, CellStyle s) => _put(ref, SheetCell(style: _s(s)));

  void blanks(String from, String to, CellStyle s) {
    final r = CellRef.parseRange('$from:$to')!;
    for (var row = r.firstRow; row <= r.lastRow; row++) {
      for (var col = r.firstCol; col <= r.lastCol; col++) {
        if (sheet.cellAt(row, col).isEmpty) sheet.setCell(row, col, SheetCell(style: _s(s)));
      }
    }
  }

  void headers(int row, List<String> names, {int firstCol = 0}) {
    for (var i = 0; i < names.length; i++) {
      sheet.setCell(row - 1, firstCol + i, SheetCell(value: TextValue(names[i]), style: _s(_head)));
    }
  }

  void widths(List<double> w) {
    for (var i = 0; i < w.length; i++) {
      sheet.colWidths[i] = w[i];
    }
    sheet.colsDirty = true;
  }

  Workbook done() {
    FormulaEngine(wb).recalculateAll();
    return wb;
  }
}

double _date0(int y, int m, int d) => NumberFormatter.dateToSerial(DateTime(y, m, d)).floorToDouble();

String _col(int i) => CellRef.columnName(i);

Workbook _blank() {
  final t = _T('Sheet1');
  return t.done();
}

Workbook _budget() {
  final t = _T('Budget')
    ..text('A1', 'Monthly budget', _title)
    ..text('A2', 'Type in the yellow cells. Differences and totals are worked out for you.', _note)
    ..headers(3, ['Income', 'Planned', 'Actual']);
  const income = [('Salary or pocket money', 30000.0), ('Other income', 2000.0), ('', 0.0)];
  for (var i = 0; i < income.length; i++) {
    final r = 4 + i;
    if (income[i].$1.isNotEmpty) t.text('A$r', income[i].$1);
    t.number('B$r', income[i].$2, _moneyIn);
    t.blank('C$r', _moneyIn);
  }
  t
    ..text('A7', 'Total income', _totalLabel)
    ..formula('B7', 'SUM(B4:B6)', _moneyTotal)
    ..formula('C7', 'SUM(C4:C6)', _moneyTotal)
    ..headers(9, ['Spending', 'Planned', 'Actual', 'Difference']);
  const spending = [('Rent', 9000.0), ('Food', 6000.0), ('Travel', 2000.0), ('Bills and phone', 2500.0), ('Education', 3000.0), ('Health', 1000.0), ('Fun', 1500.0), ('Savings', 3000.0)];
  for (var i = 0; i < spending.length; i++) {
    final r = 10 + i;
    t
      ..text('A$r', spending[i].$1)
      ..number('B$r', spending[i].$2, _moneyIn)
      ..blank('C$r', _moneyIn)
      ..formula('D$r', 'B$r-C$r', _money);
  }
  t
    ..text('A18', 'Total spending', _totalLabel)
    ..formula('B18', 'SUM(B10:B17)', _moneyTotal)
    ..formula('C18', 'SUM(C10:C17)', _moneyTotal)
    ..formula('D18', 'B18-C18', _moneyTotal)
    ..text('A20', 'Left over (planned)', _label)
    ..formula('B20', 'B7-B18', _moneyTotal)
    ..text('A21', 'Left over (actual)', _label)
    ..formula('C21', 'C7-C18', _moneyTotal)
    ..widths([26, 14, 14, 14]);
  return t.done();
}

Workbook _expenses() {
  final t = _T('Expenses')
    ..text('A1', 'Expense tracker', _title)
    ..text('A2', 'Add one line for each purchase. The totals on the right update by themselves.', _note)
    ..headers(3, ['Date', 'What', 'Category', 'Amount'])
    ..headers(3, ['Category', 'Total'], firstCol: 5);
  const rows = [
    (2026, 11, 1, 'Lunch', 'Food', 120.0),
    (2026, 11, 2, 'Bus pass', 'Travel', 450.0),
    (2026, 11, 3, 'Notebook', 'Shopping', 90.0),
    (2026, 11, 4, 'Phone recharge', 'Bills', 299.0),
  ];
  for (var i = 0; i < 40; i++) {
    final r = 4 + i;
    if (i < rows.length) {
      final x = rows[i];
      t
        ..number('A$r', _date0(x.$1, x.$2, x.$3), _dateIn)
        ..text('B$r', x.$4, _input)
        ..text('C$r', x.$5, _input)
        ..number('D$r', x.$6, _moneyIn);
    } else {
      t
        ..blank('A$r', _dateIn)
        ..blank('B$r', _input)
        ..blank('C$r', _input)
        ..blank('D$r', _moneyIn);
    }
  }
  const cats = ['Food', 'Travel', 'Shopping', 'Bills', 'Fun', 'Other'];
  for (var i = 0; i < cats.length; i++) {
    final r = 4 + i;
    t
      ..text('F$r', cats[i])
      ..formula('G$r', 'SUMIF(\$C\$4:\$C\$43,F$r,\$D\$4:\$D\$43)', _money);
  }
  t
    ..text('F10', 'All spending', _totalLabel)
    ..formula('G10', 'SUM(D4:D43)', _moneyTotal)
    ..text('F11', 'Biggest purchase', _label)
    ..formula('G11', 'MAX(D4:D43)', _money)
    ..widths([13, 22, 14, 13, 3, 16, 14]);
  return t.done();
}

Workbook _marks() {
  final t = _T('Marks')
    ..text('A1', 'Marks and grades', _title)
    ..text('A2', 'Maximum marks for each subject', _label)
    ..number('B2', 100, _input)
    ..headers(3, ['Student', 'Maths', 'Science', 'English', 'Social', 'Total', 'Percent', 'Grade', 'Rank']);
  const names = ['Student 1', 'Student 2', 'Student 3', 'Student 4', 'Student 5'];
  const marks = [
    [82.0, 75.0, 68.0, 90.0],
    [91.0, 88.0, 79.0, 85.0],
    [55.0, 61.0, 48.0, 70.0],
    [73.0, 69.0, 80.0, 77.0],
    [38.0, 45.0, 52.0, 40.0],
  ];
  for (var i = 0; i < 10; i++) {
    final r = 4 + i;
    if (i < names.length) {
      t.text('A$r', names[i], _input);
      for (var c = 0; c < 4; c++) {
        t.number('${_col(c + 1)}$r', marks[i][c], _input);
      }
    } else {
      t.blank('A$r', _input);
      t.blanks('B$r', 'E$r', _input);
    }
    t
      ..formula('F$r', 'IF(COUNT(B$r:E$r)=0,"",SUM(B$r:E$r))', _center)
      ..formula('G$r', 'IF(F$r="","",F$r/(\$B\$2*COUNTA(\$B\$3:\$E\$3)))', _pct)
      ..formula('H$r', 'IF(G$r="","",IFS(G$r>=0.9,"A+",G$r>=0.8,"A",G$r>=0.7,"B",G$r>=0.6,"C",G$r>=0.4,"D",TRUE,"F"))', _center)
      ..formula('I$r', 'IF(F$r="","",RANK(F$r,\$F\$4:\$F\$13))', _center);
  }
  t.text('A15', 'Class average', _totalLabel);
  for (var c = 1; c <= 6; c++) {
    t.formula('${_col(c)}15', 'IFERROR(AVERAGE(${_col(c)}4:${_col(c)}13),"")', _moneyTotal);
  }
  t
    ..text('A16', 'Highest total', _label)
    ..formula('F16', 'IF(COUNT(F4:F13)=0,"",MAX(F4:F13))', _center)
    ..widths([16, 10, 10, 10, 10, 10, 11, 9, 8]);
  return t.done();
}

Workbook _attendance() {
  final t = _T('Attendance')
    ..text('A1', 'Attendance', _title)
    ..text('A2', 'Type P for present and A for absent in the yellow cells.', _note)
    ..headers(3, ['Name', ...List.generate(10, (i) => 'Day ${i + 1}'), 'Present', 'Absent', 'Attendance']);
  const pattern = ['P', 'P', 'A', 'P', 'P', 'P', 'A', 'P', 'P', 'P'];
  for (var i = 0; i < 12; i++) {
    final r = 4 + i;
    if (i < 5) {
      t.text('A$r', 'Student ${i + 1}', _input);
      for (var d = 0; d < 10; d++) {
        t.text('${_col(d + 1)}$r', (d + i) % 7 == 0 ? 'A' : pattern[d], _input);
      }
    } else {
      t.blank('A$r', _input);
      t.blanks('B$r', 'K$r', _input);
    }
    t
      ..formula('L$r', 'COUNTIF(B$r:K$r,"P")', _center)
      ..formula('M$r', 'COUNTIF(B$r:K$r,"A")', _center)
      ..formula('N$r', 'IF(L$r+M$r=0,"",L$r/(L$r+M$r))', _pct);
  }
  t
    ..text('A17', 'Present each day', _totalLabel);
  for (var d = 1; d <= 10; d++) {
    t.formula('${_col(d)}17', 'COUNTIF(${_col(d)}4:${_col(d)}15,"P")', _moneyTotal);
  }
  t.widths([16, ...List.filled(10, 7), 9, 9, 12]);
  return t.done();
}

Workbook _timetable() {
  final t = _T('Timetable')
    ..text('A1', 'Weekly timetable', _title)
    ..headers(3, ['Time', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']);
  const slots = ['8:00 - 9:00', '9:00 - 10:00', '10:00 - 11:00', '11:00 - 12:00', '12:00 - 1:00', '1:00 - 2:00', '2:00 - 3:00', '3:00 - 4:00'];
  const sample = {
    '4': ['Maths', 'Science', 'English', 'Maths', 'Social', 'Sports'],
    '5': ['English', 'Maths', 'Science', 'English', 'Maths', 'Art'],
    '6': ['Science', 'English', 'Maths', 'Science', 'English', ''],
  };
  for (var i = 0; i < slots.length; i++) {
    final r = 4 + i;
    t.text('A$r', slots[i], _label);
    final row = sample['$r'];
    for (var d = 0; d < 6; d++) {
      final value = row == null ? '' : row[d];
      if (value.isEmpty) {
        t.blank('${_col(d + 1)}$r', _input);
      } else {
        t.text('${_col(d + 1)}$r', value, _input);
      }
    }
  }
  t
    ..text('A13', 'Break: write it into the lunch row, or change the times in column A.', _note)
    ..widths([14, 13, 13, 13, 13, 13, 13]);
  return t.done();
}

Workbook _savings() {
  final t = _T('Savings goal')
    ..text('A1', 'Savings goal', _title)
    ..text('A2', 'Change the yellow cells to see what to save each month.', _note)
    ..text('A4', 'Goal amount', _label)
    ..number('B4', 50000, _moneyIn)
    ..text('A5', 'Already saved', _label)
    ..number('B5', 5000, _moneyIn)
    ..text('A6', 'Months to save', _label)
    ..number('B6', 12, _input)
    ..text('A7', 'Yearly interest', _label)
    ..number('B7', 0.04, _pctIn)
    ..text('A9', 'Save each month', _totalLabel)
    ..formula('B9', '-PMT(B7/12,B6,-B5,B4)', _moneyTotal)
    ..text('A10', 'Total you put in', _label)
    ..formula('B10', 'B5+B9*B6', _money)
    ..text('A11', 'Interest earned', _label)
    ..formula('B11', 'B4-B10', _money)
    ..widths([22, 16]);
  return t.done();
}

Workbook _loan() {
  final t = _T('Loan')
    ..text('A1', 'Loan calculator', _title)
    ..text('A2', 'Change the yellow cells to see the monthly payment.', _note)
    ..text('A4', 'Loan amount', _label)
    ..number('B4', 100000, _moneyIn)
    ..text('A5', 'Yearly interest rate', _label)
    ..number('B5', 0.08, _pctIn)
    ..text('A6', 'Years', _label)
    ..number('B6', 5, _input)
    ..text('A8', 'Monthly payment', _totalLabel)
    ..formula('B8', '-PMT(B5/12,B6*12,B4)', _moneyTotal)
    ..text('A9', 'Total paid back', _label)
    ..formula('B9', 'B8*B6*12', _money)
    ..text('A10', 'Total interest', _label)
    ..formula('B10', 'B9-B4', _money)
    ..widths([24, 16]);
  return t.done();
}

Workbook _invoice() {
  final t = _T('Invoice')
    ..text('A1', 'Invoice', _title)
    ..text('A3', 'Bill to', _label)
    ..blank('B3', _input)
    ..text('A4', 'Date', _label)
    ..number('B4', _date0(2026, 11, 1), _dateIn)
    ..text('A5', 'Invoice number', _label)
    ..number('B5', 1001, _input)
    ..headers(7, ['Description', 'Quantity', 'Price', 'Amount']);
  const items = [('Item or service', 2.0, 500.0), ('Another item', 1.0, 1200.0)];
  for (var i = 0; i < 8; i++) {
    final r = 8 + i;
    if (i < items.length) {
      t
        ..text('A$r', items[i].$1, _input)
        ..number('B$r', items[i].$2, _input)
        ..number('C$r', items[i].$3, _moneyIn);
    } else {
      t
        ..blank('A$r', _input)
        ..blank('B$r', _input)
        ..blank('C$r', _moneyIn);
    }
    t.formula('D$r', 'IF(B$r="","",B$r*C$r)', _money);
  }
  t
    ..text('C16', 'Subtotal', _label)
    ..formula('D16', 'SUM(D8:D15)', _money)
    ..text('C17', 'Tax rate', _label)
    ..number('D17', 0.1, _pctIn)
    ..text('C18', 'Tax', _label)
    ..formula('D18', 'D16*D17', _money)
    ..text('C19', 'Total due', _totalLabel)
    ..formula('D19', 'D16+D18', _moneyTotal)
    ..widths([28, 12, 14, 16]);
  return t.done();
}

Workbook _project() {
  final t = _T('Tasks')
    ..text('A1', 'Project tracker', _title)
    ..text('A2', 'Set Status to Done when a task is finished. Days left counts from today.', _note)
    ..headers(3, ['Task', 'Owner', 'Start', 'Due', 'Status', 'Days left']);
  const tasks = [
    ('Plan the work', 'Asha', 2026, 11, 1, 2026, 11, 5, 'Done'),
    ('First draft', 'Ravi', 2026, 11, 6, 2026, 11, 15, 'In progress'),
    ('Review', 'Asha', 2026, 11, 16, 2026, 11, 20, 'Not started'),
    ('Final version', 'Ravi', 2026, 11, 21, 2026, 11, 28, 'Not started'),
  ];
  for (var i = 0; i < 12; i++) {
    final r = 4 + i;
    if (i < tasks.length) {
      final x = tasks[i];
      t
        ..text('A$r', x.$1, _input)
        ..text('B$r', x.$2, _input)
        ..number('C$r', _date0(x.$3, x.$4, x.$5), _dateIn)
        ..number('D$r', _date0(x.$6, x.$7, x.$8), _dateIn)
        ..text('E$r', x.$9, _input);
    } else {
      t
        ..blank('A$r', _input)
        ..blank('B$r', _input)
        ..blank('C$r', _dateIn)
        ..blank('D$r', _dateIn)
        ..blank('E$r', _input);
    }
    t.formula('F$r', 'IF(D$r="","",IF(E$r="Done","Done",D$r-TODAY()))', _center);
  }
  t
    ..text('A17', 'Tasks done', _label)
    ..formula('B17', 'COUNTIF(E4:E15,"Done")', _center)
    ..text('A18', 'All tasks', _label)
    ..formula('B18', 'COUNTA(A4:A15)', _center)
    ..text('A19', 'Progress', _totalLabel)
    ..formula('B19', 'IF(B18=0,0,B17/B18)', _pct)
    ..widths([22, 12, 13, 13, 14, 11]);
  return t.done();
}

Workbook _sales() {
  final t = _T('Sales')
    ..text('A1', 'Sales summary', _title)
    ..headers(3, ['Month', 'Units sold', 'Price each', 'Sales']);
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const units = [120.0, 135.0, 150.0, 128.0, 160.0, 172.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
  for (var i = 0; i < 12; i++) {
    final r = 4 + i;
    t.text('A$r', months[i]);
    if (units[i] > 0) {
      t.number('B$r', units[i], _input);
      t.number('C$r', 250, _moneyIn);
    } else {
      t.blank('B$r', _input);
      t.blank('C$r', _moneyIn);
    }
    t.formula('D$r', 'IF(B$r="","",B$r*C$r)', _money);
  }
  t
    ..text('A17', 'Total', _totalLabel)
    ..formula('B17', 'SUM(B4:B15)', _moneyTotal)
    ..blank('C17', _totalLabel)
    ..formula('D17', 'SUM(D4:D15)', _moneyTotal)
    ..text('A18', 'Average per month', _label)
    ..formula('D18', 'IFERROR(AVERAGE(D4:D15),"")', _money)
    ..text('A19', 'Best month', _label)
    ..formula('D19', 'IFERROR(INDEX(A4:A15,MATCH(MAX(D4:D15),D4:D15,0)),"")', _center)
    ..widths([20, 13, 13, 16]);
  return t.done();
}

Workbook _stock() {
  final t = _T('Stock')
    ..text('A1', 'Stock list', _title)
    ..text('A2', 'Status shows Reorder when the stock is at or below the reorder level.', _note)
    ..headers(3, ['Item', 'In stock', 'Reorder level', 'Unit price', 'Value', 'Status']);
  const items = [('Notebooks', 40.0, 20.0, 45.0), ('Pens (box)', 8.0, 10.0, 120.0), ('Staples', 25.0, 10.0, 30.0), ('Folders', 60.0, 25.0, 15.0)];
  for (var i = 0; i < 14; i++) {
    final r = 4 + i;
    if (i < items.length) {
      t
        ..text('A$r', items[i].$1, _input)
        ..number('B$r', items[i].$2, _input)
        ..number('C$r', items[i].$3, _input)
        ..number('D$r', items[i].$4, _moneyIn);
    } else {
      t
        ..blank('A$r', _input)
        ..blank('B$r', _input)
        ..blank('C$r', _input)
        ..blank('D$r', _moneyIn);
    }
    t
      ..formula('E$r', 'IF(B$r="","",B$r*D$r)', _money)
      ..formula('F$r', 'IF(A$r="","",IF(B$r<=C$r,"Reorder","OK"))', _center);
  }
  t
    ..text('A19', 'Total value', _totalLabel)
    ..formula('E19', 'SUM(E4:E17)', _moneyTotal)
    ..text('A20', 'Items to reorder', _label)
    ..formula('E20', 'COUNTIF(F4:F17,"Reorder")', _center)
    ..widths([22, 11, 14, 12, 14, 11]);
  return t.done();
}

final sheetTemplates = <SheetTemplate>[
  SheetTemplate(id: 'blank', title: 'Blank spreadsheet', hint: 'An empty workbook', group: 'study', build: _blank),
  SheetTemplate(id: 'marks', title: 'Marks and grades', hint: 'Totals, percent, grade and rank', group: 'study', build: _marks),
  SheetTemplate(id: 'attendance', title: 'Attendance', hint: 'P or A for each day, with percent', group: 'study', build: _attendance),
  SheetTemplate(id: 'timetable', title: 'Weekly timetable', hint: 'Subjects by day and time', group: 'study', build: _timetable),
  SheetTemplate(id: 'budget', title: 'Monthly budget', hint: 'Income, spending, what is left', group: 'money', build: _budget),
  SheetTemplate(id: 'expenses', title: 'Expense tracker', hint: 'Every purchase and totals by category', group: 'money', build: _expenses),
  SheetTemplate(id: 'savings', title: 'Savings goal', hint: 'How much to save each month', group: 'money', build: _savings),
  SheetTemplate(id: 'loan', title: 'Loan calculator', hint: 'Monthly payment and total interest', group: 'money', build: _loan),
  SheetTemplate(id: 'invoice', title: 'Invoice', hint: 'Items, tax and total due', group: 'work', build: _invoice),
  SheetTemplate(id: 'project', title: 'Project tracker', hint: 'Tasks, owners, dates and progress', group: 'work', build: _project),
  SheetTemplate(id: 'sales', title: 'Sales summary', hint: 'Sales by month, average and best month', group: 'work', build: _sales),
  SheetTemplate(id: 'stock', title: 'Stock list', hint: 'Quantities, value and what to reorder', group: 'work', build: _stock),
];

SheetTemplate? sheetTemplateById(String id) => sheetTemplates.where((t) => t.id == id).firstOrNull;

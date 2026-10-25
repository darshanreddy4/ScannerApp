import 'dart:math' as math;

import 'number_format.dart';
import 'sheet_model.dart';

/// A spreadsheet error travelling up through a formula.
class FormulaError implements Exception {
  const FormulaError(this.code);
  final String code;
}

/// The formula uses something this engine does not calculate; the cell keeps the value the file stored.
class UnsupportedFormula implements Exception {
  const UnsupportedFormula(this.what);
  final String what;
}

// ---------------------------------------------------------------- syntax tree

sealed class _Node {
  const _Node();
}

class _Num extends _Node {
  const _Num(this.v);
  final double v;
}

class _Str extends _Node {
  const _Str(this.v);
  final String v;
}

class _Bool extends _Node {
  const _Bool(this.v);
  final bool v;
}

class _Err extends _Node {
  const _Err(this.code);
  final String code;
}

class _Ref extends _Node {
  const _Ref(this.sheet, this.r1, this.c1, this.r2, this.c2);
  final String? sheet;
  final int r1, c1, r2, c2;
  bool get isRange => r1 != r2 || c1 != c2;
}

class _Unary extends _Node {
  const _Unary(this.op, this.a);
  final String op;
  final _Node a;
}

class _Binary extends _Node {
  const _Binary(this.op, this.a, this.b);
  final String op;
  final _Node a, b;
}

class _Percent extends _Node {
  const _Percent(this.a);
  final _Node a;
}

class _Call extends _Node {
  const _Call(this.name, this.args);
  final String name;
  final List<_Node> args;
}

// --------------------------------------------------------------------- parser

class _Token {
  const _Token(this.kind, this.text, [this.ref]);
  final String kind; // num str ref name func op bool err end
  final String text;
  final _Ref? ref;
}

final _refRe = RegExp(r"^(?:(?:'((?:[^']|'')+)'|([A-Za-z_][A-Za-z0-9_.]*))!)?\$?([A-Za-z]{1,3})\$?(\d{1,7})(?::\$?([A-Za-z]{1,3})\$?(\d{1,7}))?");
final _colRangeRe = RegExp(r"^(?:(?:'((?:[^']|'')+)'|([A-Za-z_][A-Za-z0-9_.]*))!)?\$?([A-Za-z]{1,3}):\$?([A-Za-z]{1,3})(?![A-Za-z0-9_(])");
final _rowRangeRe = RegExp(r"^(?:(?:'((?:[^']|'')+)'|([A-Za-z_][A-Za-z0-9_.]*))!)?\$?(\d{1,7}):\$?(\d{1,7})(?![A-Za-z0-9_(.])");
final _numRe = RegExp(r'^(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?');
final _nameRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*');
final _errRe = RegExp(r'^#(?:REF!|DIV/0!|VALUE!|NAME\?|N/A|NUM!|NULL!)');

const _bigRow = 1048575;

List<_Token> _tokenize(String s) {
  final out = <_Token>[];
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      i++;
      continue;
    }
    final rest = s.substring(i);
    if (ch == '"') {
      final b = StringBuffer();
      var j = i + 1;
      var closed = false;
      while (j < s.length) {
        if (s[j] == '"') {
          if (j + 1 < s.length && s[j + 1] == '"') {
            b.write('"');
            j += 2;
            continue;
          }
          closed = true;
          j++;
          break;
        }
        b.write(s[j++]);
      }
      if (!closed) throw const FormulaError('#VALUE!');
      out.add(_Token('str', b.toString()));
      i = j;
      continue;
    }
    if (ch == '#') {
      final m = _errRe.firstMatch(rest);
      if (m == null) throw const FormulaError('#NAME?');
      out.add(_Token('err', m.group(0)!));
      i += m.end;
      continue;
    }
    var m = _refRe.firstMatch(rest);
    if (m != null) {
      final next = m.end < rest.length ? rest[m.end] : '';
      if (!RegExp(r'[A-Za-z0-9_(.]').hasMatch(next)) {
        final sheet = m.group(1)?.replaceAll("''", "'") ?? m.group(2);
        final c1 = CellRef.columnIndex(m.group(3)!), r1 = int.parse(m.group(4)!) - 1;
        final c2 = m.group(5) == null ? c1 : CellRef.columnIndex(m.group(5)!);
        final r2 = m.group(6) == null ? r1 : int.parse(m.group(6)!) - 1;
        if (c1 < 0 || c2 < 0) throw const FormulaError('#REF!');
        out.add(_Token('ref', m.group(0)!, _Ref(sheet, math.min(r1, r2), math.min(c1, c2), math.max(r1, r2), math.max(c1, c2))));
        i += m.end;
        continue;
      }
    }
    m = _colRangeRe.firstMatch(rest);
    if (m != null) {
      final c1 = CellRef.columnIndex(m.group(3)!), c2 = CellRef.columnIndex(m.group(4)!);
      if (c1 >= 0 && c2 >= 0) {
        out.add(_Token('ref', m.group(0)!, _Ref(m.group(1)?.replaceAll("''", "'") ?? m.group(2), 0, math.min(c1, c2), _bigRow, math.max(c1, c2))));
        i += m.end;
        continue;
      }
    }
    m = _rowRangeRe.firstMatch(rest);
    if (m != null) {
      final r1 = int.parse(m.group(3)!) - 1, r2 = int.parse(m.group(4)!) - 1;
      out.add(_Token('ref', m.group(0)!, _Ref(m.group(1)?.replaceAll("''", "'") ?? m.group(2), math.min(r1, r2), 0, math.max(r1, r2), CellRef.maxCols - 1)));
      i += m.end;
      continue;
    }
    m = _numRe.firstMatch(rest);
    if (m != null) {
      out.add(_Token('num', m.group(0)!));
      i += m.end;
      continue;
    }
    m = _nameRe.firstMatch(rest);
    if (m != null) {
      final name = m.group(0)!;
      final after = i + name.length;
      if (after < s.length && s[after] == '(') {
        out.add(_Token('func', name.toUpperCase()));
        i = after + 1; // the opening bracket is part of the token
        continue;
      }
      final up = name.toUpperCase();
      if (up == 'TRUE' || up == 'FALSE') {
        out.add(_Token('bool', up));
      } else {
        out.add(_Token('name', name));
      }
      i = after;
      continue;
    }
    if (rest.startsWith('<=') || rest.startsWith('>=') || rest.startsWith('<>')) {
      out.add(_Token('op', rest.substring(0, 2)));
      i += 2;
      continue;
    }
    if ('+-*/^&=<>%(),;'.contains(ch)) {
      out.add(_Token('op', ch));
      i++;
      continue;
    }
    throw UnsupportedFormula('character $ch');
  }
  out.add(const _Token('end', ''));
  return out;
}

class _Parser {
  _Parser(this.t);
  final List<_Token> t;
  var p = 0;

  _Token get cur => t[p];
  bool isOp(String o) => cur.kind == 'op' && cur.text == o;

  _Node parse() {
    final n = _compare();
    if (cur.kind != 'end') throw const FormulaError('#VALUE!');
    return n;
  }

  _Node _compare() {
    var a = _concat();
    while (cur.kind == 'op' && const ['=', '<>', '<', '>', '<=', '>='].contains(cur.text)) {
      final op = cur.text;
      p++;
      a = _Binary(op, a, _concat());
    }
    return a;
  }

  _Node _concat() {
    var a = _add();
    while (isOp('&')) {
      p++;
      a = _Binary('&', a, _add());
    }
    return a;
  }

  _Node _add() {
    var a = _mul();
    while (isOp('+') || isOp('-')) {
      final op = cur.text;
      p++;
      a = _Binary(op, a, _mul());
    }
    return a;
  }

  _Node _mul() {
    var a = _pow();
    while (isOp('*') || isOp('/')) {
      final op = cur.text;
      p++;
      a = _Binary(op, a, _pow());
    }
    return a;
  }

  _Node _pow() {
    var a = _unary();
    while (isOp('^')) {
      p++;
      a = _Binary('^', a, _unary());
    }
    return a;
  }

  _Node _unary() {
    if (isOp('-') || isOp('+')) {
      final op = cur.text;
      p++;
      return _Unary(op, _unary());
    }
    var a = _primary();
    while (isOp('%')) {
      p++;
      a = _Percent(a);
    }
    return a;
  }

  _Node _primary() {
    final tok = cur;
    switch (tok.kind) {
      case 'num':
        p++;
        return _Num(double.parse(tok.text));
      case 'str':
        p++;
        return _Str(tok.text);
      case 'bool':
        p++;
        return _Bool(tok.text == 'TRUE');
      case 'err':
        p++;
        return _Err(tok.text);
      case 'ref':
        p++;
        return tok.ref!;
      case 'name':
        throw UnsupportedFormula('name ${tok.text}');
      case 'func':
        p++;
        final args = <_Node>[];
        if (isOp(')')) {
          p++;
          return _Call(tok.text, args);
        }
        while (true) {
          // An omitted argument, as in IF(A1,,2), counts as empty.
          args.add(isOp(',') || isOp(';') ? const _Str('') : _compare());
          if (isOp(',') || isOp(';')) {
            p++;
            continue;
          }
          if (isOp(')')) {
            p++;
            break;
          }
          throw const FormulaError('#VALUE!');
        }
        return _Call(tok.text, args);
      case 'op' when tok.text == '(':
        p++;
        final n = _compare();
        if (!isOp(')')) throw const FormulaError('#VALUE!');
        p++;
        return n;
    }
    throw const FormulaError('#VALUE!');
  }
}

// ------------------------------------------------------------------ evaluator

/// A block of cells passed to a function.
class _Area {
  const _Area(this.sheet, this.r1, this.c1, this.r2, this.c2);
  final Sheet sheet;
  final int r1, c1, r2, c2;
}

/// Calculates the formulas of a [Workbook] in place. Functions that are not covered keep the value stored in the file.
class FormulaEngine {
  FormulaEngine(this.workbook, {DateTime? now}) : _now = now ?? DateTime.now();

  final Workbook workbook;
  final DateTime _now;

  static final Map<String, _Node?> _parsed = {};
  final Map<Sheet, int> _lastRow = {}, _lastCol = {};
  final Set<int> _busy = {};
  final Set<int> _done = {};

  int _id(Sheet s, int row, int col) => workbook.sheets.indexOf(s) * 0x100000000 + CellRef.key(row, col);

  /// Recalculates every formula of every sheet.
  void recalculateAll() {
    _lastRow.clear();
    _lastCol.clear();
    _done.clear();
    _busy.clear();
    for (final s in workbook.sheets) {
      for (final k in s.cells.keys.toList()) {
        if (s.cells[k]?.formula != null) _resolve(s, CellRef.rowOf(k), CellRef.colOf(k));
      }
    }
  }

  /// The result of [formula] typed into [sheet], or null when it cannot be calculated here.
  CellValue? evaluate(Sheet sheet, String formula) {
    _lastRow.clear();
    _lastCol.clear();
    try {
      return _toCell(_eval(_parseCached(formula), sheet));
    } on FormulaError catch (e) {
      return ErrorValue(e.code);
    } on UnsupportedFormula {
      return null;
    }
  }

  /// Whether every function of [formula] is one this engine calculates.
  static bool isSupported(String formula) {
    try {
      _check(_parseCached(formula));
      return true;
    } on UnsupportedFormula {
      return false;
    } on FormulaError {
      return true;
    }
  }

  static void _check(_Node n) {
    switch (n) {
      case _Call():
        if (!_functions.contains(n.name)) throw UnsupportedFormula(n.name);
        n.args.forEach(_check);
      case _Unary():
        _check(n.a);
      case _Percent():
        _check(n.a);
      case _Binary():
        _check(n.a);
        _check(n.b);
      default:
        break;
    }
  }

  static _Node _parseCached(String formula) {
    if (_parsed.containsKey(formula)) {
      final n = _parsed[formula];
      if (n == null) throw UnsupportedFormula(formula);
      return n;
    }
    try {
      final n = _Parser(_tokenize(formula)).parse();
      if (_parsed.length > 5000) _parsed.clear();
      _parsed[formula] = n;
      return n;
    } on UnsupportedFormula {
      _parsed[formula] = null;
      rethrow;
    }
  }

  CellValue _resolve(Sheet sheet, int row, int col) {
    final cell = sheet.cells[CellRef.key(row, col)];
    if (cell == null) return const EmptyValue();
    final f = cell.formula;
    if (f == null) return cell.value;
    final id = _id(sheet, row, col);
    if (_done.contains(id)) return cell.value;
    if (_busy.contains(id)) throw const FormulaError('#REF!'); // circular
    _busy.add(id);
    CellValue result;
    try {
      result = _toCell(_eval(_parseCached(f), sheet));
    } on FormulaError catch (e) {
      result = ErrorValue(e.code);
    } on UnsupportedFormula {
      result = cell.value;
    } finally {
      _busy.remove(id);
    }
    _done.add(id);
    if (!_same(result, cell.value)) {
      sheet.cells[CellRef.key(row, col)] = cell.copyWith(value: result);
      sheet.dirty = true;
    }
    return result;
  }

  static bool _same(CellValue a, CellValue b) => switch ((a, b)) {
    (EmptyValue(), EmptyValue()) => true,
    (TextValue(text: final x), TextValue(text: final y)) => x == y,
    (NumberValue(number: final x), NumberValue(number: final y)) => x == y || (x - y).abs() < 1e-12 * math.max(1, x.abs()),
    (BoolValue(flag: final x), BoolValue(flag: final y)) => x == y,
    (ErrorValue(code: final x), ErrorValue(code: final y)) => x == y,
    _ => false,
  };

  CellValue _toCell(Object? v) {
    if (v is _Area) v = _single(v);
    return switch (v) {
      null => const NumberValue(0),
      double d => d.isNaN || d.isInfinite ? throw const FormulaError('#NUM!') : NumberValue(d),
      String s => TextValue(s),
      bool b => BoolValue(b),
      _ => const ErrorValue('#VALUE!'),
    };
  }

  Object? _single(_Area a) {
    if (a.r1 == a.r2 && a.c1 == a.c2) return _read(a.sheet, a.r1, a.c1);
    throw const FormulaError('#VALUE!');
  }

  Object? _read(Sheet s, int row, int col) {
    final v = _resolve(s, row, col);
    return switch (v) {
      EmptyValue() => null,
      TextValue(:final text) => text,
      NumberValue(:final number) => number,
      BoolValue(:final flag) => flag,
      ErrorValue(:final code) => throw FormulaError(code),
    };
  }

  Sheet _sheetFor(String? name, Sheet context) {
    if (name == null) return context;
    final s = workbook.sheetNamed(name);
    if (s == null) throw const FormulaError('#REF!');
    return s;
  }

  int _clipRow(Sheet s, int r) => math.min(r, _lastRow[s] ??= s.lastRow);
  int _clipCol(Sheet s, int c) => math.min(c, _lastCol[s] ??= s.lastCol);

  Object? _eval(_Node n, Sheet ctx) {
    switch (n) {
      case _Num():
        return n.v;
      case _Str():
        return n.v;
      case _Bool():
        return n.v;
      case _Err():
        throw FormulaError(n.code);
      case _Ref():
        final sheet = _sheetFor(n.sheet, ctx);
        if (!n.isRange) return _read(sheet, n.r1, n.c1);
        return _Area(sheet, n.r1, n.c1, n.r2, n.c2);
      case _Unary():
        final v = _num(_eval(n.a, ctx));
        return n.op == '-' ? -v : v;
      case _Percent():
        return _num(_eval(n.a, ctx)) / 100;
      case _Binary():
        return _binary(n, ctx);
      case _Call():
        return _call(n, ctx);
    }
  }

  Object? _scalar(Object? v) => v is _Area ? _single(v) : v;

  Object? _binary(_Binary n, Sheet ctx) {
    final a = _scalar(_eval(n.a, ctx)), b = _scalar(_eval(n.b, ctx));
    switch (n.op) {
      case '+':
        return _num(a) + _num(b);
      case '-':
        return _num(a) - _num(b);
      case '*':
        return _num(a) * _num(b);
      case '/':
        final d = _num(b);
        if (d == 0) throw const FormulaError('#DIV/0!');
        return _num(a) / d;
      case '^':
        final x = _num(a), y = _num(b);
        if (x == 0 && y < 0) throw const FormulaError('#DIV/0!');
        final r = math.pow(x, y).toDouble();
        if (r.isNaN || r.isInfinite) throw const FormulaError('#NUM!');
        return r;
      case '&':
        return _text(a) + _text(b);
      default:
        final c = _compareValues(a, b);
        return switch (n.op) {
          '=' => c == 0,
          '<>' => c != 0,
          '<' => c < 0,
          '>' => c > 0,
          '<=' => c <= 0,
          _ => c >= 0,
        };
    }
  }

  /// Excel's ordering: numbers before text before booleans; text is compared ignoring case.
  static int _compareValues(Object? a, Object? b) {
    int rank(Object? v) => v is double ? 0 : (v is String ? 1 : (v is bool ? 2 : -1));
    if (a == null) a = b is String ? '' : (b is bool ? false : 0.0);
    if (b == null) b = a is String ? '' : (a is bool ? false : 0.0);
    final ra = rank(a), rb = rank(b);
    if (ra != rb) return ra.compareTo(rb);
    if (a is double) return a.compareTo(b as double);
    if (a is String) return a.toLowerCase().compareTo((b as String).toLowerCase());
    return ((a as bool) ? 1 : 0).compareTo((b as bool) ? 1 : 0);
  }

  double _num(Object? v) {
    if (v is _Area) v = _single(v);
    if (v == null) return 0;
    if (v is double) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is String) {
      final d = double.tryParse(v.trim());
      if (d != null) return d;
      throw const FormulaError('#VALUE!');
    }
    throw const FormulaError('#VALUE!');
  }

  String _text(Object? v) {
    if (v is _Area) v = _single(v);
    if (v == null) return '';
    if (v is double) return NumberFormatter.general(v);
    if (v is bool) return v ? 'TRUE' : 'FALSE';
    return v as String;
  }

  bool _bool(Object? v) {
    if (v is _Area) v = _single(v);
    if (v == null) return false;
    if (v is bool) return v;
    if (v is double) return v != 0;
    if (v is String) {
      if (v.toUpperCase() == 'TRUE') return true;
      if (v.toUpperCase() == 'FALSE') return false;
    }
    throw const FormulaError('#VALUE!');
  }

  /// Every value in the arguments, ranges flattened. Text and booleans inside ranges are skipped, as numeric functions do.
  List<double> _numbers(List<Object?> args) {
    final out = <double>[];
    for (final a in args) {
      if (a is _Area) {
        for (final v in _areaValues(a)) {
          if (v is double) out.add(v);
        }
      } else if (a != null) {
        out.add(_num(a));
      }
    }
    return out;
  }

  Iterable<Object?> _areaValues(_Area a, {bool includeEmpty = false}) sync* {
    final maxR = includeEmpty ? a.r2 : _clipRow(a.sheet, a.r2);
    final maxC = includeEmpty ? a.c2 : _clipCol(a.sheet, a.c2);
    for (var r = a.r1; r <= maxR; r++) {
      for (var c = a.c1; c <= maxC; c++) {
        final v = _read(a.sheet, r, c);
        if (v != null || includeEmpty) yield v;
      }
    }
  }

  List<List<Object?>> _grid(_Area a) {
    final rows = <List<Object?>>[];
    final maxR = _clipRow(a.sheet, a.r2), maxC = _clipCol(a.sheet, a.c2);
    for (var r = a.r1; r <= maxR; r++) {
      rows.add([for (var c = a.c1; c <= maxC; c++) _read(a.sheet, r, c)]);
    }
    return rows;
  }

  static const _functions = {
    'SUM',
    'AVERAGE',
    'MIN',
    'MAX',
    'COUNT',
    'COUNTA',
    'COUNTBLANK',
    'PRODUCT',
    'MEDIAN',
    'IF',
    'IFERROR',
    'IFNA',
    'AND',
    'OR',
    'NOT',
    'XOR',
    'TRUE',
    'FALSE', //
    'ROUND', 'ROUNDUP', 'ROUNDDOWN', 'INT', 'ABS', 'SQRT', 'POWER', 'MOD', 'SIGN', 'EXP', 'LN', 'LOG', 'LOG10', 'PI', 'CEILING', 'FLOOR', 'TRUNC', 'SUMPRODUCT',
    'CONCAT',
    'CONCATENATE',
    'LEN',
    'UPPER',
    'LOWER',
    'PROPER',
    'TRIM',
    'LEFT',
    'RIGHT',
    'MID',
    'SUBSTITUTE',
    'FIND',
    'SEARCH',
    'REPT',
    'TEXT',
    'VALUE',
    'EXACT',
    'SUMIF', 'COUNTIF', 'AVERAGEIF', 'VLOOKUP', 'HLOOKUP', 'INDEX', 'MATCH', 'ISBLANK', 'ISNUMBER', 'ISTEXT', 'ISERROR', 'ISERR', 'ISNA', 'ISLOGICAL', 'NA',
    'TODAY',
    'NOW',
    'DATE',
    'YEAR',
    'MONTH',
    'DAY',
    'WEEKDAY',
    'HOUR',
    'MINUTE',
    'SECOND',
    'ROW',
    'COLUMN',
    'ROWS',
    'COLUMNS',
    'LARGE',
    'SMALL',
    'RAND',
    'RANDBETWEEN',
    'CHOOSE', 'MAXA', 'MINA', 'AVERAGEA', 'IFS', 'SWITCH', 'SUMSQ', 'COUNTIFS', 'SUMIFS',
  };

  void _arity(_Call c, int min, [int? max]) {
    if (c.args.length < min || (max != null && c.args.length > max)) throw const FormulaError('#VALUE!');
  }

  Object? _call(_Call c, Sheet ctx) {
    final name = c.name;
    if (!_functions.contains(name)) throw UnsupportedFormula(name);

    // Functions that decide which arguments to calculate.
    switch (name) {
      case 'IF':
        _arity(c, 2, 3);
        if (_bool(_eval(c.args[0], ctx))) return _scalar(_eval(c.args[1], ctx));
        return c.args.length > 2 ? _scalar(_eval(c.args[2], ctx)) : false;
      case 'IFS':
        for (var i = 0; i + 1 < c.args.length; i += 2) {
          if (_bool(_eval(c.args[i], ctx))) return _scalar(_eval(c.args[i + 1], ctx));
        }
        throw const FormulaError('#N/A');
      case 'SWITCH':
        _arity(c, 3);
        final x = _scalar(_eval(c.args[0], ctx));
        var i = 1;
        for (; i + 1 < c.args.length; i += 2) {
          if (_compareValues(x, _scalar(_eval(c.args[i], ctx))) == 0) return _scalar(_eval(c.args[i + 1], ctx));
        }
        if (i < c.args.length) return _scalar(_eval(c.args[i], ctx));
        throw const FormulaError('#N/A');
      case 'IFERROR':
      case 'IFNA':
        _arity(c, 2, 2);
        try {
          return _scalar(_eval(c.args[0], ctx));
        } on FormulaError catch (e) {
          if (name == 'IFNA' && e.code != '#N/A') rethrow;
          return _scalar(_eval(c.args[1], ctx));
        }
      case 'ISERROR':
      case 'ISERR':
      case 'ISNA':
        _arity(c, 1, 1);
        try {
          _scalar(_eval(c.args[0], ctx));
          return false;
        } on FormulaError catch (e) {
          if (name == 'ISNA') return e.code == '#N/A';
          if (name == 'ISERR') return e.code != '#N/A';
          return true;
        }
      case 'CHOOSE':
        _arity(c, 2);
        final i = _num(_eval(c.args[0], ctx)).floor();
        if (i < 1 || i >= c.args.length) throw const FormulaError('#VALUE!');
        return _scalar(_eval(c.args[i], ctx));
      case 'ROW':
      case 'COLUMN':
        if (c.args.isEmpty) throw const UnsupportedFormula('ROW() without a cell');
        final a = c.args.first;
        if (a is! _Ref) throw const FormulaError('#VALUE!');
        return (name == 'ROW' ? a.r1 + 1 : a.c1 + 1).toDouble();
      case 'ROWS':
      case 'COLUMNS':
        _arity(c, 1, 1);
        final a = c.args.first;
        if (a is! _Ref) return 1.0;
        return (name == 'ROWS' ? a.r2 - a.r1 + 1 : a.c2 - a.c1 + 1).toDouble();
    }

    final args = [for (final a in c.args) _evalArg(a, ctx)];
    return _fixed(name, args, c);
  }

  /// A single cell given to a function stays a reference, so text in it is ignored by SUM, AVERAGE and the like, as Excel does.
  Object? _evalArg(_Node a, Sheet ctx) {
    if (a is _Ref && !a.isRange) return _Area(_sheetFor(a.sheet, ctx), a.r1, a.c1, a.r1, a.c1);
    return _eval(a, ctx);
  }

  double _round(double v, int digits, String mode) {
    final f = math.pow(10, digits).toDouble();
    final x = v * f;
    final r = switch (mode) {
      'ROUND' => x.sign * (x.abs() + 0.5 + 1e-9 * math.max(1, x.abs())).floorToDouble(),
      'ROUNDUP' => x.sign * x.abs().ceilToDouble(),
      _ => x.sign * x.abs().floorToDouble(),
    };
    return r / f;
  }

  Object? _fixed(String name, List<Object?> a, _Call c) {
    double n(int i) => _num(a[i]);
    String t(int i) => _text(a[i]);
    switch (name) {
      case 'SUM':
        return _numbers(a).fold<double>(0, (s, v) => s + v);
      case 'SUMSQ':
        return _numbers(a).fold<double>(0, (s, v) => s + v * v);
      case 'PRODUCT':
        final v = _numbers(a);
        return v.isEmpty ? 0.0 : v.fold<double>(1, (s, x) => s * x);
      case 'AVERAGE':
        final v = _numbers(a);
        if (v.isEmpty) throw const FormulaError('#DIV/0!');
        return v.fold<double>(0, (s, x) => s + x) / v.length;
      case 'AVERAGEA':
      case 'MAXA':
      case 'MINA':
        throw UnsupportedFormula(name);
      case 'MIN':
        final v = _numbers(a);
        return v.isEmpty ? 0.0 : v.reduce(math.min);
      case 'MAX':
        final v = _numbers(a);
        return v.isEmpty ? 0.0 : v.reduce(math.max);
      case 'MEDIAN':
        final v = _numbers(a)..sort();
        if (v.isEmpty) throw const FormulaError('#NUM!');
        return v.length.isOdd ? v[v.length ~/ 2] : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
      case 'LARGE':
      case 'SMALL':
        if (a.length != 2) throw const FormulaError('#VALUE!');
        final v = _numbers([a[0]])..sort();
        final k = n(1).ceil();
        if (k < 1 || k > v.length) throw const FormulaError('#NUM!');
        return name == 'SMALL' ? v[k - 1] : v[v.length - k];
      case 'COUNT':
        var count = 0;
        for (final x in a) {
          if (x is _Area) {
            count += _areaValues(x).whereType<double>().length;
          } else if (x is double || x is bool) {
            count++;
          } else if (x is String && double.tryParse(x.trim()) != null) {
            count++;
          }
        }
        return count.toDouble();
      case 'COUNTA':
        var count = 0;
        for (final x in a) {
          count += x is _Area ? _areaValues(x).length : 1;
        }
        return count.toDouble();
      case 'COUNTBLANK':
        if (a.length != 1 || a[0] is! _Area) throw const FormulaError('#VALUE!');
        final area = a[0] as _Area;
        final total = (area.r2 - area.r1 + 1) * (area.c2 - area.c1 + 1);
        return (total - _areaValues(area).where((v) => v != null && v != '').length).toDouble();
      case 'AND':
      case 'OR':
      case 'XOR':
        final flags = <bool>[];
        for (final x in a) {
          if (x is _Area) {
            for (final v in _areaValues(x)) {
              if (v is bool) flags.add(v);
              if (v is double) flags.add(v != 0);
            }
          } else {
            flags.add(_bool(x));
          }
        }
        if (flags.isEmpty) throw const FormulaError('#VALUE!');
        return name == 'AND' ? flags.every((x) => x) : (name == 'OR' ? flags.any((x) => x) : flags.where((x) => x).length.isOdd);
      case 'NOT':
        _arity(c, 1, 1);
        return !_bool(a[0]);
      case 'TRUE':
        return true;
      case 'FALSE':
        return false;
      case 'NA':
        throw const FormulaError('#N/A');
      case 'ROUND':
      case 'ROUNDUP':
      case 'ROUNDDOWN':
        _arity(c, 2, 2);
        return _round(n(0), n(1).truncate(), name);
      case 'TRUNC':
        _arity(c, 1, 2);
        return _round(n(0), a.length > 1 ? n(1).truncate() : 0, 'ROUNDDOWN');
      case 'INT':
        return n(0).floorToDouble();
      case 'ABS':
        return n(0).abs();
      case 'SIGN':
        return n(0).sign;
      case 'SQRT':
        if (n(0) < 0) throw const FormulaError('#NUM!');
        return math.sqrt(n(0));
      case 'POWER':
        _arity(c, 2, 2);
        final r = math.pow(n(0), n(1)).toDouble();
        if (r.isNaN || r.isInfinite) throw const FormulaError('#NUM!');
        return r;
      case 'MOD':
        _arity(c, 2, 2);
        if (n(1) == 0) throw const FormulaError('#DIV/0!');
        return n(0) - n(1) * (n(0) / n(1)).floorToDouble();
      case 'EXP':
        return math.exp(n(0));
      case 'LN':
        if (n(0) <= 0) throw const FormulaError('#NUM!');
        return math.log(n(0));
      case 'LOG10':
        if (n(0) <= 0) throw const FormulaError('#NUM!');
        return math.log(n(0)) / math.ln10;
      case 'LOG':
        if (n(0) <= 0) throw const FormulaError('#NUM!');
        final base = a.length > 1 ? n(1) : 10.0;
        if (base <= 0 || base == 1) throw const FormulaError('#NUM!');
        return math.log(n(0)) / math.log(base);
      case 'PI':
        return math.pi;
      case 'CEILING':
      case 'FLOOR':
        _arity(c, 1, 2);
        final step = a.length > 1 ? n(1) : 1.0;
        if (step == 0) return 0.0;
        return name == 'CEILING' ? (n(0) / step).ceilToDouble() * step : (n(0) / step).floorToDouble() * step;
      case 'SUMPRODUCT':
        final grids = [
          for (final x in a)
            if (x is _Area) _areaValues(x, includeEmpty: true).toList() else [x],
        ];
        if (grids.isEmpty) throw const FormulaError('#VALUE!');
        final len = grids.first.length;
        if (grids.any((g) => g.length != len)) throw const FormulaError('#VALUE!');
        var sum = 0.0;
        for (var i = 0; i < len; i++) {
          var p = 1.0;
          for (final g in grids) {
            final v = g[i];
            p *= v is double ? v : 0;
          }
          sum += p;
        }
        return sum;
      case 'CONCAT':
      case 'CONCATENATE':
        final b = StringBuffer();
        for (final x in a) {
          if (x is _Area) {
            for (final v in _areaValues(x)) {
              b.write(_text(v));
            }
          } else {
            b.write(_text(x));
          }
        }
        return b.toString();
      case 'LEN':
        return t(0).length.toDouble();
      case 'UPPER':
        return t(0).toUpperCase();
      case 'LOWER':
        return t(0).toLowerCase();
      case 'PROPER':
        return t(0).toLowerCase().replaceAllMapped(RegExp(r'(^|[^A-Za-z])([a-z])'), (m) => '${m[1]}${m[2]!.toUpperCase()}');
      case 'TRIM':
        return t(0).trim().replaceAll(RegExp(r' {2,}'), ' ');
      case 'LEFT':
      case 'RIGHT':
        _arity(c, 1, 2);
        final len = a.length > 1 ? n(1).truncate() : 1;
        if (len < 0) throw const FormulaError('#VALUE!');
        final s = t(0);
        return name == 'LEFT' ? s.substring(0, math.min(len, s.length)) : s.substring(math.max(0, s.length - len));
      case 'MID':
        _arity(c, 3, 3);
        final start = n(1).truncate(), len = n(2).truncate();
        if (start < 1 || len < 0) throw const FormulaError('#VALUE!');
        final s = t(0);
        if (start > s.length) return '';
        return s.substring(start - 1, math.min(s.length, start - 1 + len));
      case 'SUBSTITUTE':
        _arity(c, 3, 4);
        if (t(1).isEmpty) return t(0);
        if (a.length == 4) {
          final which = n(3).truncate();
          var count = 0;
          return t(0).replaceAllMapped(RegExp(RegExp.escape(t(1))), (m) => ++count == which ? t(2) : m[0]!);
        }
        return t(0).replaceAll(t(1), t(2));
      case 'FIND':
      case 'SEARCH':
        _arity(c, 2, 3);
        final from = a.length > 2 ? n(2).truncate() - 1 : 0;
        final hay = name == 'FIND' ? t(1) : t(1).toLowerCase();
        final needle = name == 'FIND' ? t(0) : t(0).toLowerCase();
        if (from < 0 || from > hay.length) throw const FormulaError('#VALUE!');
        final at = hay.indexOf(needle, from);
        if (at < 0) throw const FormulaError('#VALUE!');
        return at + 1.0;
      case 'REPT':
        final times = n(1).truncate();
        if (times < 0 || times * t(0).length > 32000) throw const FormulaError('#VALUE!');
        return t(0) * times;
      case 'EXACT':
        return t(0) == t(1);
      case 'TEXT':
        _arity(c, 2, 2);
        final v = _scalar(a[0]);
        if (v is double) return NumberFormatter.format(v, t(1), date1904: workbook.date1904);
        return _text(v);
      case 'VALUE':
        final v = _scalar(a[0]);
        if (v is double) return v;
        final d = double.tryParse(_text(v).trim().replaceAll(',', ''));
        if (d == null) throw const FormulaError('#VALUE!');
        return d;
      case 'ISBLANK':
        return _scalar(a[0]) == null;
      case 'ISNUMBER':
        return _scalar(a[0]) is double;
      case 'ISTEXT':
        return _scalar(a[0]) is String;
      case 'ISLOGICAL':
        return _scalar(a[0]) is bool;
      case 'TODAY':
        return NumberFormatter.dateToSerial(DateTime(_now.year, _now.month, _now.day), date1904: workbook.date1904).floorToDouble();
      case 'NOW':
        return NumberFormatter.dateToSerial(_now, date1904: workbook.date1904);
      case 'RAND':
      case 'RANDBETWEEN':
        throw UnsupportedFormula(name); // a stored random value must not change on its own
      case 'DATE':
        _arity(c, 3, 3);
        var y = n(0).truncate();
        if (y >= 0 && y < 1900) y += 1900;
        final d = DateTime(y, n(1).truncate(), n(2).truncate());
        return NumberFormatter.dateToSerial(d, date1904: workbook.date1904).floorToDouble();
      case 'YEAR':
      case 'MONTH':
      case 'DAY':
      case 'WEEKDAY':
      case 'HOUR':
      case 'MINUTE':
      case 'SECOND':
        final serial = n(0);
        if (serial < 0) throw const FormulaError('#NUM!');
        final d = NumberFormatter.serialToDate(serial, date1904: workbook.date1904);
        return switch (name) {
          'YEAR' => d.year.toDouble(),
          'MONTH' => d.month.toDouble(),
          'DAY' => d.day.toDouble(),
          'HOUR' => d.hour.toDouble(),
          'MINUTE' => d.minute.toDouble(),
          'SECOND' => d.second.toDouble(),
          _ => (d.weekday % 7 + 1).toDouble(),
        };
      case 'SUMIF':
      case 'COUNTIF':
      case 'AVERAGEIF':
        return _conditional(name, a);
      case 'SUMIFS':
      case 'COUNTIFS':
        return _multiConditional(name, a);
      case 'VLOOKUP':
      case 'HLOOKUP':
        return _lookup(name == 'HLOOKUP', a);
      case 'INDEX':
        return _index(a);
      case 'MATCH':
        return _match(a);
    }
    throw UnsupportedFormula(name);
  }

  Object? _conditional(String name, List<Object?> a) {
    if (a.length < 2 || a[0] is! _Area) throw const FormulaError('#VALUE!');
    final range = a[0] as _Area;
    final test = _Criteria.parse(_scalar(a[1]));
    final sumArea = name != 'COUNTIF' && a.length > 2 && a[2] is _Area ? a[2] as _Area : range;
    var total = 0.0, count = 0;
    final maxR = _clipRow(range.sheet, range.r2), maxC = _clipCol(range.sheet, range.c2);
    for (var r = range.r1; r <= maxR; r++) {
      for (var cc = range.c1; cc <= maxC; cc++) {
        if (!test.matches(_read(range.sheet, r, cc))) continue;
        count++;
        if (name != 'COUNTIF') {
          final v = _read(sumArea.sheet, sumArea.r1 + (r - range.r1), sumArea.c1 + (cc - range.c1));
          if (v is double) total += v;
        }
      }
    }
    if (name == 'COUNTIF') return count.toDouble();
    if (name == 'AVERAGEIF') {
      if (count == 0) throw const FormulaError('#DIV/0!');
      return total / count;
    }
    return total;
  }

  Object? _multiConditional(String name, List<Object?> a) {
    final sumArea = name == 'SUMIFS' ? a.first : null;
    final pairs = name == 'SUMIFS' ? a.sublist(1) : a;
    if (pairs.length < 2 || pairs.length.isOdd || (sumArea != null && sumArea is! _Area)) throw const FormulaError('#VALUE!');
    final areas = <_Area>[];
    final tests = <_Criteria>[];
    for (var i = 0; i < pairs.length; i += 2) {
      if (pairs[i] is! _Area) throw const FormulaError('#VALUE!');
      areas.add(pairs[i] as _Area);
      tests.add(_Criteria.parse(_scalar(pairs[i + 1])));
    }
    final first = areas.first;
    final maxR = _clipRow(first.sheet, first.r2), maxC = _clipCol(first.sheet, first.c2);
    var total = 0.0, count = 0;
    for (var r = first.r1; r <= maxR; r++) {
      for (var cc = first.c1; cc <= maxC; cc++) {
        var ok = true;
        for (var i = 0; i < areas.length && ok; i++) {
          final x = areas[i];
          ok = tests[i].matches(_read(x.sheet, x.r1 + (r - first.r1), x.c1 + (cc - first.c1)));
        }
        if (!ok) continue;
        count++;
        if (sumArea is _Area) {
          final v = _read(sumArea.sheet, sumArea.r1 + (r - first.r1), sumArea.c1 + (cc - first.c1));
          if (v is double) total += v;
        }
      }
    }
    return name == 'COUNTIFS' ? count.toDouble() : total;
  }

  Object? _lookup(bool horizontal, List<Object?> a) {
    if (a.length < 3 || a[1] is! _Area) throw const FormulaError('#VALUE!');
    final key = _scalar(a[0]);
    final grid = _grid(a[1] as _Area);
    if (grid.isEmpty) throw const FormulaError('#N/A');
    final idx = _num(a[2]).truncate();
    final approx = a.length > 3 ? _bool(a[3]) : true;
    final lines = horizontal ? List.generate(grid.first.length, (c) => [for (final row in grid) row[c]]) : grid;
    // lines[i] is the i-th row (or column for HLOOKUP); the key is searched in its first element.
    if (idx < 1 || (lines.isNotEmpty && idx > lines.first.length)) throw const FormulaError('#REF!');
    var found = -1;
    if (approx) {
      for (var i = 0; i < lines.length; i++) {
        final v = lines[i].first;
        if (v == null || (v.runtimeType != key.runtimeType && key != null)) continue;
        if (_compareValues(v, key) <= 0) {
          found = i;
        } else {
          break;
        }
      }
    } else {
      for (var i = 0; i < lines.length; i++) {
        final v = lines[i].first;
        if (v != null && _matchesLoose(v, key)) {
          found = i;
          break;
        }
      }
    }
    if (found < 0) throw const FormulaError('#N/A');
    return lines[found][idx - 1];
  }

  bool _matchesLoose(Object? v, Object? key) {
    if (v is String && key is String) return _Criteria.wildcard(key).hasMatch(v);
    return v.runtimeType == key.runtimeType && _compareValues(v, key) == 0;
  }

  Object? _index(List<Object?> a) {
    if (a.length < 2) throw const FormulaError('#VALUE!');
    if (a[0] is! _Area) {
      if (_num(a[1]) == 1) return a[0];
      throw const FormulaError('#REF!');
    }
    final area = a[0] as _Area;
    var row = _num(a[1]).truncate();
    var col = a.length > 2 ? _num(a[2]).truncate() : 0;
    final rows = area.r2 - area.r1 + 1, cols = area.c2 - area.c1 + 1;
    if (a.length == 2 && rows == 1) {
      col = row;
      row = 1;
    } else if (col == 0 && cols == 1) {
      col = 1;
    }
    if (row < 1 || col < 1 || row > rows || col > cols) throw const FormulaError('#REF!');
    return _read(area.sheet, area.r1 + row - 1, area.c1 + col - 1);
  }

  Object? _match(List<Object?> a) {
    if (a.length < 2 || a[1] is! _Area) throw const FormulaError('#VALUE!');
    final key = _scalar(a[0]);
    final area = a[1] as _Area;
    final type = a.length > 2 ? _num(a[2]).sign.toInt() : 1;
    final values = _areaValues(area, includeEmpty: true).toList();
    final used = math.min(
      values.length,
      (area.r2 - area.r1 + 1 == 1 ? _clipCol(area.sheet, area.c2) - area.c1 + 1 : _clipRow(area.sheet, area.r2) - area.r1 + 1),
    );
    final list = values.take(math.max(used, 0)).toList();
    var found = -1;
    if (type == 0) {
      for (var i = 0; i < list.length; i++) {
        if (list[i] != null && _matchesLoose(list[i], key)) {
          found = i;
          break;
        }
      }
    } else {
      for (var i = 0; i < list.length; i++) {
        final v = list[i];
        if (v == null || v.runtimeType != key.runtimeType) continue;
        final cmp = _compareValues(v, key);
        if (type > 0 ? cmp <= 0 : cmp >= 0) {
          found = i;
        } else {
          break;
        }
      }
    }
    if (found < 0) throw const FormulaError('#N/A');
    return found + 1.0;
  }
}

/// The condition of SUMIF, COUNTIF and similar functions: a value, a comparison such as ">=5", or text with * and ? wildcards.
class _Criteria {
  _Criteria(this.op, this.operand);

  final String op;
  final Object? operand;

  static _Criteria parse(Object? raw) {
    if (raw is _Area) throw const FormulaError('#VALUE!');
    if (raw is! String) return _Criteria('=', raw);
    final m = RegExp(r'^(<=|>=|<>|<|>|=)?(.*)$', dotAll: true).firstMatch(raw)!;
    final op = m.group(1) ?? '=';
    final rest = m.group(2)!;
    final number = double.tryParse(rest.trim());
    if (number != null) return _Criteria(op, number);
    final up = rest.toUpperCase();
    if (up == 'TRUE' || up == 'FALSE') return _Criteria(op, up == 'TRUE');
    return _Criteria(op, rest);
  }

  static RegExp wildcard(String pattern) {
    final b = StringBuffer('^');
    for (var i = 0; i < pattern.length; i++) {
      final ch = pattern[i];
      if (ch == '~' && i + 1 < pattern.length) {
        b.write(RegExp.escape(pattern[++i]));
      } else if (ch == '*') {
        b.write('.*');
      } else if (ch == '?') {
        b.write('.');
      } else {
        b.write(RegExp.escape(ch));
      }
    }
    b.write(r'$');
    return RegExp(b.toString(), caseSensitive: false, dotAll: true);
  }

  bool matches(Object? v) {
    final o = operand;
    if (o is String) {
      if (op == '=' || op == '<>') {
        final hit = v is String ? wildcard(o).hasMatch(v) : (o.isEmpty && v == null);
        return op == '=' ? hit : !hit;
      }
      if (v is! String) return false;
      return _cmp(v.toLowerCase().compareTo(o.toLowerCase()));
    }
    if (o is double) {
      if (v is! double) return op == '<>';
      return _cmp(v.compareTo(o));
    }
    if (o is bool) {
      if (v is! bool) return op == '<>';
      return _cmp((v ? 1 : 0).compareTo(o ? 1 : 0));
    }
    return op == '=' ? v == null : v != null;
  }

  bool _cmp(int c) => switch (op) {
    '=' => c == 0,
    '<>' => c != 0,
    '<' => c < 0,
    '>' => c > 0,
    '<=' => c <= 0,
    _ => c >= 0,
  };
}

/// Files made by some tools store formulas without their results. Calculates those so the values can be shown and exported.
void calculateMissingResults(Workbook wb) {
  if (wb.sheets.any((s) => s.cells.values.any((c) => c.formula != null && c.value is EmptyValue))) FormulaEngine(wb).recalculateAll();
}

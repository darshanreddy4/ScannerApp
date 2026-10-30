import 'dart:math' as math;

import '../../ocr/domain/ocr_models.dart';

/// How far apart two words must be to belong to different columns, in heights of a line of text.
enum TableSpacing {
  tight('Tight', 0.6),
  normal('Normal', 1.0),
  loose('Loose', 1.7);

  const TableSpacing(this.label, this.factor);
  final String label;
  final double factor;
}

/// The cells of a table as text, row by row. Every row has the same number of cells.
class RecognizedTable {
  const RecognizedTable(this.rows);
  final List<List<String>> rows;

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;
  bool get isEmpty => rows.isEmpty || columnCount == 0;
}

class _Seg {
  _Seg(this.text, this.left, this.top, this.right, this.bottom);
  String text;
  double left, top, right, bottom;
  double get cy => (top + bottom) / 2;
  double get cx => (left + right) / 2;
  double get h => bottom - top;
}

class _Row {
  _Row(_Seg first) : segs = [first], cy = first.cy;
  final List<_Seg> segs;
  double cy;
  void add(_Seg s) {
    segs.add(s);
    cy = segs.map((e) => e.cy).reduce((a, b) => a + b) / segs.length;
  }
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// The words of a page lined up into rows from top to bottom, after turning a slightly askew photo level; [h] is the usual height of a word.
({List<_Row> rows, double h}) _clusterRows(OcrPageResult page) {
  final segs = <_Seg>[];
  final angles = <double>[];
  for (final b in page.blocks) {
    for (final l in b.lines) {
      if (l.text.trim().isEmpty) continue;
      if (l.angle != 0 && l.text.trim().length >= 3) angles.add(l.angle);
      final words = [
        for (final w in l.words)
          if (w.text.trim().isNotEmpty) w,
      ];
      if (words.isEmpty) {
        segs.add(_Seg(l.text.trim(), l.left, l.top, l.right, l.bottom));
      } else {
        for (final w in words) {
          segs.add(_Seg(w.text.trim(), w.left, w.top, w.right, w.bottom));
        }
      }
    }
  }
  segs.removeWhere((s) => s.h <= 0 || s.right <= s.left);
  if (segs.isEmpty) return (rows: const <_Row>[], h: 0);

  // A photo taken a little askew: turn the positions back so that the lines run level.
  final tilt = _median(angles);
  if (tilt.abs() > 0.01 && tilt.abs() < 0.3) {
    final cx0 = page.width / 2, cy0 = page.height / 2;
    final cs = math.cos(tilt), sn = math.sin(tilt);
    for (final s in segs) {
      final w = s.right - s.left, h = s.h;
      final x = s.cx - cx0, y = s.cy - cy0;
      final nx = x * cs + y * sn + cx0, ny = -x * sn + y * cs + cy0;
      s
        ..left = nx - w / 2
        ..right = nx + w / 2
        ..top = ny - h / 2
        ..bottom = ny + h / 2;
    }
  }

  final h = _median([for (final s in segs) s.h]);
  segs.sort((a, b) => a.cy.compareTo(b.cy));
  final rows = <_Row>[];
  for (final s in segs) {
    if (rows.isNotEmpty && (s.cy - rows.last.cy).abs() <= 0.6 * h) {
      rows.last.add(s);
    } else {
      rows.add(_Row(s));
    }
  }
  return (rows: rows, h: h);
}

/// The text of each row of the page, words from left to right: a label and the amount at the other end of its line stay together.
List<String> readRows(OcrPageResult page) {
  final rows = _clusterRows(page).rows;
  return [for (final r in rows) (r.segs..sort((a, b) => a.left.compareTo(b.left))).map((e) => e.text).join(' ')];
}

/// Rebuilds a table from the words found on a page: lines up the words into rows, joins words that are close into cells, and finds
/// the columns from where the cells sit. Text that is not a table comes out as a single column.
RecognizedTable readTable(OcrPageResult page, {TableSpacing spacing = TableSpacing.normal}) {
  final clustered = _clusterRows(page);
  final rows = clustered.rows;
  final h = clustered.h;
  if (rows.isEmpty) return const RecognizedTable([]);

  // Words that are close together are one cell ("New York"); a wide gap starts the next cell.
  final limit = spacing.factor * h;
  final cellsOf = <List<_Seg>>[];
  for (final r in rows) {
    r.segs.sort((a, b) => a.left.compareTo(b.left));
    final cells = <_Seg>[];
    var cur = _Seg(r.segs.first.text, r.segs.first.left, r.segs.first.top, r.segs.first.right, r.segs.first.bottom);
    for (final s in r.segs.skip(1)) {
      if (s.left - cur.right <= limit) {
        cur
          ..text = '${cur.text} ${s.text}'
          ..right = math.max(cur.right, s.right)
          ..top = math.min(cur.top, s.top)
          ..bottom = math.max(cur.bottom, s.bottom);
      } else {
        cells.add(cur);
        cur = _Seg(s.text, s.left, s.top, s.right, s.bottom);
      }
    }
    cells.add(cur);
    cellsOf.add(cells);
  }

  // Columns are the stretches of the page that cells of the rows with several cells cover.
  final spans = [
    for (final cells in cellsOf)
      if (cells.length >= 2) ...cells,
  ]..sort((a, b) => a.left.compareTo(b.left));
  final bands = <List<double>>[];
  for (final c in spans) {
    if (bands.isNotEmpty && c.left <= bands.last[1] + 0.25 * h) {
      bands.last[1] = math.max(bands.last[1], c.right);
    } else {
      bands.add([c.left, c.right]);
    }
  }
  if (bands.isEmpty) bands.add([0, page.width]);

  int bandOf(_Seg c) {
    var best = 0;
    var bestOverlap = -1e18;
    for (var i = 0; i < bands.length; i++) {
      final overlap = math.min(c.right, bands[i][1]) - math.max(c.left, bands[i][0]);
      // With no overlap, the nearest band wins (the overlap is then minus the distance).
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = i;
      }
    }
    return best;
  }

  final grid = <List<String>>[];
  for (final cells in cellsOf) {
    final row = List<String>.filled(bands.length, '');
    for (final c in cells) {
      final i = bandOf(c);
      row[i] = row[i].isEmpty ? c.text : '${row[i]} ${c.text}';
    }
    grid.add(row);
  }
  _tidyNumbers(grid);
  return RecognizedTable(grid);
}

final _strictNumber = RegExp(r'^[-+]?\d[\d,]*(\.\d+)?%?$');
final _thousands = RegExp(r'^(-?)((?:\d{1,3}(?:,\d{3})+)|(?:\d{1,2}(?:,\d{2})+,\d{3}))(\.\d+)?$');

String _lookalikes(String s) => s.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp(r'[lI|]'), '1');

/// In a column that is mostly numbers, letters that look like digits are read as digits (an "O" for a zero); thousands commas are
/// taken out of numbers so that a spreadsheet reads them as numbers.
void _tidyNumbers(List<List<String>> grid) {
  if (grid.isEmpty) return;
  for (var c = 0; c < grid.first.length; c++) {
    // The first row is usually a heading, so it does not count when there are rows under it.
    final body = [
      for (final r in grid.skip(grid.length >= 3 ? 1 : 0))
        if (r[c].isNotEmpty) r[c],
    ];
    final strict = body.where((t) => _strictNumber.hasMatch(t)).length;
    final fixable = body
        .where((t) => !_strictNumber.hasMatch(t) && _strictNumber.hasMatch(_lookalikes(t)) && RegExp(r'\d').hasMatch(t.replaceAll(RegExp('[Oo]'), '')))
        .length;
    if (strict >= 2 && strict + fixable >= body.length * 0.6) {
      for (final r in grid) {
        final t = r[c];
        if (t.isEmpty || _strictNumber.hasMatch(t)) continue;
        final fixed = _lookalikes(t);
        if (_strictNumber.hasMatch(fixed) && RegExp(r'\d').hasMatch(t.replaceAll(RegExp('[Oo]'), ''))) r[c] = fixed;
      }
    }
  }
  for (final r in grid) {
    for (var c = 0; c < r.length; c++) {
      final m = _thousands.firstMatch(r[c]);
      if (m != null) r[c] = '${m[1]}${m[2]!.replaceAll(',', '')}${m[3] ?? ''}';
    }
  }
}

/// Tables of consecutive pages one after another. When a later page starts with the same heading row as the first, it is left out.
RecognizedTable joinTables(List<RecognizedTable> tables) {
  final used = [
    for (final t in tables)
      if (!t.isEmpty) t,
  ];
  if (used.isEmpty) return const RecognizedTable([]);
  final width = used.map((t) => t.columnCount).reduce(math.max);
  List<String> pad(List<String> r) => [...r, for (var i = r.length; i < width; i++) ''];
  final rows = [for (final r in used.first.rows) pad(r)];
  final head = rows.first.map((s) => s.toLowerCase()).join('\u0001');
  for (final t in used.skip(1)) {
    for (var i = 0; i < t.rows.length; i++) {
      final r = pad(t.rows[i]);
      if (i == 0 && t.rows.length > 1 && r.map((s) => s.toLowerCase()).join('\u0001') == head) continue;
      rows.add(r);
    }
  }
  return RecognizedTable(rows);
}

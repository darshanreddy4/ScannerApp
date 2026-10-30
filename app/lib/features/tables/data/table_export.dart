import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../office/sheets/data/csv.dart';
import '../../office/sheets/data/xlsx_writer.dart';
import '../../office/sheets/domain/sheet_model.dart';

final _number = RegExp(r'^[-+]?\d+(\.\d+)?%?$');

/// The first row is a heading when it has no numbers while the rows under it do.
bool _looksLikeHeader(List<List<String>> rows) {
  if (rows.length < 2) return false;
  if (rows.first.any((c) => _number.hasMatch(c.trim()))) return false;
  if (!rows.first.any((c) => c.trim().isNotEmpty)) return false;
  return rows.skip(1).any((r) => r.any((c) => _number.hasMatch(c.trim())));
}

/// An Excel file (.xlsx) with the table on one sheet: numbers are real numbers, the heading row is bold, and columns are as wide as their text.
Uint8List tableToXlsx(List<List<String>> rows, {String sheetName = 'Table'}) {
  final wb = workbookFromCsv(rows, sheetName: sheetName);
  final sheet = wb.sheets.first;
  final columns = rows.isEmpty ? 0 : rows.map((r) => r.length).reduce(math.max);
  for (var c = 0; c < columns; c++) {
    var longest = 0;
    for (final r in rows) {
      if (c < r.length) longest = math.max(longest, r[c].length);
    }
    sheet.colWidths[c] = (longest * 1.15 + 2).clamp(8, 60).toDouble();
  }
  sheet.colsDirty = true;
  if (_looksLikeHeader(rows)) {
    final bold = wb.styles.indexOf(const CellStyle(bold: true));
    for (var c = 0; c < columns; c++) {
      final key = CellRef.key(0, c);
      final cell = sheet.cells[key];
      if (cell != null) sheet.cells[key] = cell.copyWith(style: bold);
    }
  }
  sheet.dirty = true;
  return writeXlsx(wb);
}

String _quote(String f) => f.contains(',') || f.contains('"') || f.contains('\n') || f.contains('\r') ? '"${f.replaceAll('"', '""')}"' : f;

/// CSV text that Excel opens with accents and other scripts intact (it starts with a byte order mark).
Uint8List tableToCsv(List<List<String>> rows) {
  final b = StringBuffer();
  for (final r in rows) {
    b.write(r.map(_quote).join(','));
    b.write('\r\n');
  }
  return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
}

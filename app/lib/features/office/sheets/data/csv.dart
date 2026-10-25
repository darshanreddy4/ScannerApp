import 'dart:convert';
import 'dart:typed_data';

import '../domain/sheet_edit.dart';
import '../domain/sheet_model.dart';
import 'xlsx_writer.dart';

/// Decodes the bytes of a CSV file: UTF-8 (with or without a byte-order mark), else Windows-1252-like Latin-1.
String decodeCsvBytes(Uint8List bytes) {
  var data = bytes;
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) data = data.sublist(3);
  try {
    return utf8.decode(data);
  } on FormatException {
    return latin1.decode(data);
  }
}

/// The separator a CSV text most likely uses, judged from its first lines.
String detectDelimiter(String text) {
  final lines = text.split('\n').take(5).toList();
  var best = ',', bestCount = 0;
  for (final d in const [',', ';', '\t', '|']) {
    var inQuotes = false, count = 0;
    for (final line in lines) {
      for (var i = 0; i < line.length; i++) {
        if (line[i] == '"') inQuotes = !inQuotes;
        if (!inQuotes && line[i] == d) count++;
      }
    }
    if (count > bestCount) {
      best = d;
      bestCount = count;
    }
  }
  return best;
}

/// Splits CSV text into rows of fields, following RFC 4180 quoting.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  final d = delimiter ?? detectDelimiter(text);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false, any = false;
  void endField() {
    row.add(field.toString());
    field.clear();
    any = true;
  }

  void endRow() {
    if (any || field.isNotEmpty) {
      endField();
      rows.add(row);
    }
    row = <String>[];
    any = false;
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.isEmpty) {
      inQuotes = true;
      any = true;
    } else if (ch == d) {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  endRow();
  return rows;
}

String _quote(String f, String d) => f.contains(d) || f.contains('"') || f.contains('\n') || f.contains('\r') ? '"${f.replaceAll('"', '""')}"' : f;

/// The sheet's used range as CSV text, with values the way they are shown.
String sheetToCsv(Sheet sheet, StyleTable styles, {String delimiter = ',', bool date1904 = false}) {
  final lastRow = sheet.lastRow, lastCol = sheet.lastCol;
  if (lastRow < 0) return '';
  final b = StringBuffer();
  for (var r = 0; r <= lastRow; r++) {
    final fields = [for (var c = 0; c <= lastCol; c++) _quote(displayText(sheet.cells[CellRef.key(r, c)], styles.at, date1904: date1904), delimiter)];
    b.write(fields.join(delimiter));
    b.write('\r\n');
  }
  return b.toString();
}

/// Builds a new workbook from CSV rows. Numbers, dates and true/false become real values; text with leading zeros stays text.
Workbook workbookFromCsv(List<List<String>> rows, {String sheetName = 'Sheet1'}) {
  final wb = newWorkbook(sheetName: sheetName);
  final sheet = wb.sheets.first;
  for (var r = 0; r < rows.length && r < CellRef.maxRows; r++) {
    for (var c = 0; c < rows[r].length && c < CellRef.maxCols; c++) {
      final text = rows[r][c];
      if (text.isEmpty) continue;
      final looksLikeCode = RegExp(r'^[+-]?0\d').hasMatch(text.trim()) || text.trim().length > 15 && RegExp(r'^\d+$').hasMatch(text.trim());
      final parsed = looksLikeCode || text.startsWith('=') ? ParsedInput(TextValue(text)) : parseInput(text);
      var style = 0;
      if (parsed.numFmt != null) style = wb.styles.indexOf(CellStyle(numFmt: parsed.numFmt!));
      sheet.cells[CellRef.key(r, c)] = SheetCell(value: parsed.value, formula: parsed.formula, style: style);
    }
  }
  sheet.dirty = true;
  return wb;
}

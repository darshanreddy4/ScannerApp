import 'sheet_model.dart';

/// Finds cell references such as A1, $B$2 or Sheet1!C3 in a formula, leaving text in quotes alone.
final _refPattern = RegExp(r'(?<![A-Za-z0-9_.$])(\$?)([A-Za-z]{1,3})(\$?)(\d{1,7})(?![A-Za-z0-9_(.])');

/// Applies [change] to every part of [formula] that is not inside double quotes.
String mapFormulaOutsideText(String formula, String Function(String part) change) {
  final out = StringBuffer();
  var i = 0;
  while (i < formula.length) {
    if (formula[i] == '"') {
      var j = i + 1;
      while (j < formula.length) {
        if (formula[j] == '"') {
          if (j + 1 < formula.length && formula[j + 1] == '"') {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      out.write(formula.substring(i, j < formula.length ? j + 1 : formula.length));
      i = j + 1;
    } else {
      var j = i;
      while (j < formula.length && formula[j] != '"') {
        j++;
      }
      out.write(change(formula.substring(i, j)));
      i = j;
    }
  }
  return out.toString();
}

/// Moves the relative references of [formula] by [dRow] rows and [dCol] columns, as when a formula is copied or filled.
String shiftFormula(String formula, int dRow, int dCol) {
  if (dRow == 0 && dCol == 0) return formula;
  return mapFormulaOutsideText(formula, (part) {
    return part.replaceAllMapped(_refPattern, (m) {
      final colAbs = m.group(1)!.isNotEmpty, rowAbs = m.group(3)!.isNotEmpty;
      var col = CellRef.columnIndex(m.group(2)!);
      var row = int.parse(m.group(4)!) - 1;
      if (col < 0) return m.group(0)!;
      if (!colAbs) col += dCol;
      if (!rowAbs) row += dRow;
      if (col < 0 || col >= CellRef.maxCols || row < 0 || row >= CellRef.maxRows) return '#REF!';
      return '${colAbs ? r'$' : ''}${CellRef.columnName(col)}${rowAbs ? r'$' : ''}${row + 1}';
    });
  });
}

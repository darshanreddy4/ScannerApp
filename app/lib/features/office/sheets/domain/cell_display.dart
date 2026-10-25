import 'sheet_model.dart';
import 'number_format.dart';

/// What a cell shows and how its text is lined up.
({String text, HAlign align}) describeCell(SheetCell cell, CellStyle style, {bool date1904 = false}) {
  final v = cell.value;
  final String text;
  var align = style.align;
  switch (v) {
    case EmptyValue():
      text = '';
    case TextValue(:final text):
      return (text: text, align: align == HAlign.general ? HAlign.left : align);
    case NumberValue(:final number):
      text = NumberFormatter.format(number, style.numFmt, date1904: date1904);
      if (align == HAlign.general) align = HAlign.right;
    case BoolValue(:final flag):
      text = flag ? 'TRUE' : 'FALSE';
      if (align == HAlign.general) align = HAlign.center;
    case ErrorValue(:final code):
      text = code;
      if (align == HAlign.general) align = HAlign.center;
  }
  return (text: text, align: align);
}

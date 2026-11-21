import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/office/convert/office_converter.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_merge.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Uint8List fixture(String name) => File('test/fixtures/office/$name').readAsBytesSync();

/// The strings workbook with a thin border on its second cell format.
Uint8List withBorder() {
  final archive = ZipDecoder().decodeBytes(fixture('strings.xlsx'));
  final out = Archive();
  for (final f in archive.files) {
    if (f.name == 'xl/styles.xml') {
      var text = utf8.decode(f.readBytes()!);
      text = text.replaceFirst(
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>',
        '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FF123456"/></left><right/><top/><bottom/><diagonal/></border></borders>',
      );
      text = text.replaceFirst('<xf numFmtId="164" fontId="1" fillId="2" borderId="0"', '<xf numFmtId="164" fontId="1" fillId="2" borderId="1"');
      out.addFile(ArchiveFile.bytes(f.name, utf8.encode(text)));
    } else {
      out.addFile(f);
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

String show(CellValue v) => switch (v) {
  EmptyValue() => 'empty',
  TextValue(:final text) => 'text:$text',
  NumberValue(:final number) => 'number:$number',
  BoolValue(:final flag) => 'bool:$flag',
  ErrorValue(:final code) => 'error:$code',
};

void main() {
  test('keeps every sheet and renames the ones whose name is taken', () {
    final result = mergeXlsx([
      MergeInput('a.xlsx', fixture('basic.xlsx')),
      MergeInput('b.xlsx', fixture('basic.xlsx')),
      MergeInput('c.xlsx', fixture('strings.xlsx')),
    ]);
    final wb = readXlsx(result.bytes);
    expect(wb.sheets.map((s) => s.name), ['Sales', 'Hidden', 'Notes', 'Sales (2)', 'Hidden (2)', 'Notes (2)', 'Data', 'Empty']);
    expect(result.sheets, 8);
    expect(wb.sheets[3].cells.length, wb.sheets[0].cells.length);
    expect(wb.sheets[4].hidden, isTrue, reason: 'a hidden sheet stays hidden');
  });

  test('copied cells look the same as in their own file', () {
    final other = readXlsx(fixture('strings.xlsx'));
    final result = mergeXlsx([MergeInput('a.xlsx', fixture('basic.xlsx')), MergeInput('b.xlsx', fixture('strings.xlsx'))]);
    final wb = readXlsx(result.bytes);
    final copy = wb.sheetNamed('Data')!, original = other.sheetNamed('Data')!;
    expect(copy.cells.length, original.cells.length);
    for (final e in original.cells.entries) {
      final c = copy.cells[e.key]!;
      expect(show(c.value), show(e.value.value));
      expect(c.formula, e.value.formula);
      expect(wb.styles.styles[c.style].numFmt, other.styles.styles[e.value.style].numFmt);
      expect(wb.styles.styles[c.style].bold, other.styles.styles[e.value.style].bold);
      expect(wb.styles.styles[c.style].fill, other.styles.styles[e.value.style].fill);
    }
  });

  test('the first file keeps its own sheets and formats', () {
    final first = readXlsx(fixture('basic.xlsx'));
    final wb = readXlsx(mergeXlsx([MergeInput('a.xlsx', fixture('basic.xlsx')), MergeInput('b.xlsx', fixture('strings.xlsx'))]).bytes);
    final sales = wb.sheetNamed('Sales')!;
    for (final e in first.sheetNamed('Sales')!.cells.entries) {
      expect(show(sales.cells[e.key]!.value), show(e.value.value));
      expect(sales.cells[e.key]!.formula, e.value.formula);
      expect(sales.cells[e.key]!.style, e.value.style);
    }
  });

  test('borders of the other files are carried over', () {
    final result = mergeXlsx([MergeInput('a.xlsx', fixture('basic.xlsx')), MergeInput('b.xlsx', withBorder())]);
    final styles = XmlDocument.parse(utf8.decode(ZipDecoder().decodeBytes(result.bytes).findFile('xl/styles.xml')!.readBytes()!));
    final borders = styles.findAllElements('border').toList();
    expect(styles.findAllElements('borders').single.getAttribute('count'), '${borders.length}');
    expect(borders.any((b) => b.toXmlString().contains('style="thin"')), isTrue);
    final xfs = styles.findAllElements('cellXfs').single.childElements.toList();
    expect(styles.findAllElements('cellXfs').single.getAttribute('count'), '${xfs.length}');
    final bordered = xfs.where((x) => x.getAttribute('borderId') != '0' && x.getAttribute('borderId') != null).toList();
    expect(bordered, isNotEmpty);
    final id = int.parse(bordered.first.getAttribute('borderId')!);
    expect(borders[id].toXmlString(), contains('style="thin"'));
  });

  test('formulas that point to a renamed sheet follow the new name', () {
    // basic.xlsx has Sales and Notes; a second copy gets "Sales (2)", so its formulas must not read the first copy's cells.
    final wb = readXlsx(mergeXlsx([MergeInput('a.xlsx', fixture('basic.xlsx')), MergeInput('b.xlsx', fixture('basic.xlsx'))]).bytes);
    final withSheetRef = wb.sheetNamed('Sales')!.cells.values.where((c) => c.formula != null && c.formula!.contains('Notes!')).toList();
    if (withSheetRef.isEmpty) return;
    final copied = wb.sheetNamed('Sales (2)')!.cells.values.where((c) => c.formula != null && c.formula!.contains('Notes')).toList();
    expect(copied.every((c) => c.formula!.contains("'Notes (2)'!")), isTrue);
  });

  test('needs two readable files', () {
    expect(() => mergeXlsx([MergeInput('a.xlsx', fixture('basic.xlsx'))]), throwsA(isA<XlsxFormatException>()));
    expect(
      () => mergeXlsx([
        MergeInput('a.xlsx', fixture('basic.xlsx')),
        MergeInput('bad.xlsx', Uint8List.fromList([1, 2, 3])),
      ]),
      throwsA(isA<XlsxFormatException>().having((e) => e.message, 'message', contains('bad.xlsx'))),
    );
    expect(
      () => mergeXlsx([
        MergeInput('bad.xlsx', Uint8List.fromList([1, 2, 3])),
        MergeInput('a.xlsx', fixture('basic.xlsx')),
      ]),
      throwsA(isA<XlsxFormatException>().having((e) => e.message, 'message', contains('bad.xlsx'))),
    );
  });

  testWidgets('the converter writes one merged workbook and asks for two files', (tester) async {
    await tester.runAsync(() async {
      final work = Directory.systemTemp.createTempSync('merge_conv');
      addTearDown(() => work.deleteSync(recursive: true));
      final converter = OfficeConverter(workDir: () async => work);
      final a = File('test/fixtures/office/basic.xlsx').absolute.path, b = File('test/fixtures/office/strings.xlsx').absolute.path;
      final result = (await converter.convert(OfficeConversion.mergeXlsx, [a, b])).single;
      expect(result.name, 'basic_merged.xlsx');
      expect(result.openAs, 'sheet');
      expect(readXlsx(File(result.path).readAsBytesSync()).sheets.length, 5);
      await expectLater(converter.convert(OfficeConversion.mergeXlsx, [a]), throwsA(isA<ImportFailure>()));
    });
  });
}

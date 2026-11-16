import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_reader.dart';
import 'package:doculoom/features/office/sheets/data/xlsx_writer.dart';
import 'package:doculoom/features/office/sheets/domain/chart.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_edit.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:xml/xml.dart';

(Workbook, SheetEditor) book(List<List<String>> rows) {
  final wb = newWorkbook();
  final e = SheetEditor(wb);
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      if (rows[r][c].isNotEmpty) e.setInput(wb.sheets.first, r, c, rows[r][c]);
    }
  }
  return (wb, e);
}

const sales = [
  ['Month', 'North', 'South'],
  ['Jan', '10', '7'],
  ['Feb', '12', '9'],
  ['Mar', '9', '14'],
];

Archive zipOf(Uint8List b) => ZipDecoder().decodeBytes(b);
String textOf(Archive a, String name) => utf8.decode(a.findFile(name)!.readBytes()!);
bool has(Archive a, String name) => a.findFile(name) != null;

Workbook reopen(Workbook wb) => readXlsx(writeXlsx(wb));

void main() {
  group('making a chart from cells', () {
    test('a top row of words names the series, a first column of words names the points, each number column is a series', () {
      final (wb, _) = book(sales);
      final chart = chartFromSelection(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      expect(chart.categories!.formula, "'Sheet1'!\$A\$2:\$A\$4");
      expect(chart.series.map((s) => s.values.formula), ["'Sheet1'!\$B\$2:\$B\$4", "'Sheet1'!\$C\$2:\$C\$4"]);
      expect(chart.series.map((s) => s.nameRef!.formula), ["'Sheet1'!\$B\$1", "'Sheet1'!\$C\$1"]);
      final data = resolveChart(wb, chart);
      expect(data.categories, ['Jan', 'Feb', 'Mar']);
      expect(data.series.map((s) => s.name), ['North', 'South']);
      expect(data.series.first.values, [10, 12, 9]);
      expect(data.series.last.values, [7, 9, 14]);
    });

    test('one cell stands for the block around it, and the chart goes to the right of the data', () {
      final (wb, _) = book(sales);
      final chart = chartFromSelection(wb.sheets.first, const MergeRange(2, 1, 2, 1), ChartKind.line);
      expect(chart.series, hasLength(2));
      expect(chart.col, 4);
      expect(chart.row, 0);
    });

    test('numbers alone make one series with numbered points; a pie keeps only the first series', () {
      final (wb, _) = book([
        ['5'],
        ['8'],
        ['3'],
      ]);
      final chart = chartFromSelection(wb.sheets.first, const MergeRange(0, 0, 2, 0), ChartKind.column);
      expect(chart.categories, isNull);
      expect(chart.series.single.values.formula, "'Sheet1'!\$A\$1:\$A\$3");
      expect(resolveChart(wb, chart).categories, ['1', '2', '3']);
      expect(resolveChart(wb, chart).series.single.name, 'Series 1');

      final (wb2, _) = book(sales);
      expect(chartFromSelection(wb2.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.pie).series, hasLength(1));
    });

    test('numeric years in the first column are a series unless the corner above them is empty', () {
      final (wb, _) = book([
        ['', 'Sales'],
        ['2021', '5'],
        ['2022', '6'],
      ]);
      final chart = chartFromSelection(wb.sheets.first, const MergeRange(0, 0, 2, 1), ChartKind.column);
      expect(chart.categories, isNotNull, reason: 'an empty corner marks the first column as labels');
      expect(resolveChart(wb, chart).categories, ['2021', '2022']);
    });

    test('cells without numbers are refused with a clear message', () {
      final (wb, e) = book([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(() => e.addChart(wb.sheets.first, const MergeRange(0, 0, 1, 1), ChartKind.column), throwsA(isA<ChartSelectionException>()));
      expect(wb.sheets.first.charts, isEmpty);
    });

    test('references read back from the way a file writes them', () {
      expect(ChartRef.parse(r"Sheet1!$B$2:$B$6")!.range, const MergeRange(1, 1, 5, 1));
      expect(ChartRef.parse(r"'My ''best'' sheet'!$A$1")!.sheet, "My 'best' sheet");
      expect(ChartRef.parse(r"'x'!$A$1,'x'!$B$1"), isNull);
      expect(ChartRef.parse('Total'), isNull);
    });
  });

  group('in the file', () {
    test('a new chart is written as a chart part with its drawing, and reads back the same', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column, title: 'Sales by month');
      final bytes = writeXlsx(wb);
      final a = zipOf(bytes);

      expect(has(a, 'xl/charts/chart1.xml'), isTrue);
      expect(has(a, 'xl/drawings/drawing1.xml'), isTrue);
      expect(textOf(a, '[Content_Types].xml'), contains('/xl/charts/chart1.xml'));
      expect(textOf(a, '[Content_Types].xml'), contains('/xl/drawings/drawing1.xml'));
      expect(textOf(a, 'xl/worksheets/_rels/sheet1.xml.rels'), contains('../drawings/drawing1.xml'));
      expect(textOf(a, 'xl/drawings/_rels/drawing1.xml.rels'), contains('../charts/chart1.xml'));
      final sheetXml = XmlDocument.parse(textOf(a, 'xl/worksheets/sheet1.xml'));
      final names = sheetXml.rootElement.childElements.map((c) => c.name.local).toList();
      expect(names, containsAllInOrder(['sheetData', 'drawing']));
      final chartXml = textOf(a, 'xl/charts/chart1.xml');
      expect(chartXml, contains('<c:barDir val="col"/>'));
      expect(chartXml, contains('Sales by month'));
      expect(chartXml, contains(r"<c:f>'Sheet1'!$B$2:$B$4</c:f>"));
      expect(chartXml, contains('<c:v>Jan</c:v>'));
      expect(chartXml, contains('<c:v>14</c:v>'));
      XmlDocument.parse(chartXml);
      XmlDocument.parse(textOf(a, 'xl/drawings/drawing1.xml'));

      final back = reopen(wb);
      final chart = back.sheets.first.charts.single;
      expect(chart.kind, ChartKind.column);
      expect(chart.title, 'Sales by month');
      expect(chart.fromFile, isTrue);
      expect(chart.series, hasLength(2));
      expect(chart.categories!.formula, "'Sheet1'!\$A\$2:\$A\$4");
      expect([chart.col, chart.row, chart.cols, chart.rows], [4, 0, 8, 15]);
      expect(resolveChart(back, chart).series.first.values, [10, 12, 9]);
    });

    test('every kind is written and read back as the same kind', () {
      for (final kind in ChartKind.values) {
        final (wb, e) = book(sales);
        e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), kind);
        final back = reopen(wb);
        expect(back.sheets.first.charts.single.kind, kind, reason: '$kind');
        expect(back.sheets.first.charts.single.series.length, kind.isPie ? 1 : 2);
      }
    });

    test('stacked bars and a bar chart (sideways) keep their way of showing', () {
      final (wb, e) = book(sales);
      final c = e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.bar);
      e.updateChart(wb.sheets.first, c, stacked: true);
      final a = zipOf(writeXlsx(wb));
      final xml = textOf(a, 'xl/charts/chart1.xml');
      expect(xml, contains('<c:barDir val="bar"/>'));
      expect(xml, contains('<c:grouping val="stacked"/>'));
      expect(xml, contains('<c:overlap val="100"/>'));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.kind, ChartKind.bar);
      expect(back.stacked, isTrue);
    });

    test('a second save from the same book gives the same result, and a chart on a second sheet has its own drawing', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.line);
      final s2 = e.addSheet();
      e.setInput(s2, 0, 0, '4');
      e.setInput(s2, 1, 0, '5');
      e.addChart(s2, const MergeRange(0, 0, 1, 0), ChartKind.pie);
      final one = zipOf(writeXlsx(wb));
      final two = zipOf(writeXlsx(wb));
      expect(two.files.map((f) => f.name).toSet(), one.files.map((f) => f.name).toSet());
      expect(textOf(two, 'xl/charts/chart1.xml'), textOf(one, 'xl/charts/chart1.xml'));
      expect(has(two, 'xl/charts/chart2.xml'), isTrue);
      expect(has(two, 'xl/drawings/drawing2.xml'), isTrue);
      final back = reopen(wb);
      expect(back.sheets[0].charts.single.kind, ChartKind.line);
      expect(back.sheets[1].charts.single.kind, ChartKind.pie);
    });

    test('changing a chart that came from the file rewrites its part; removing it takes the parts out of the file', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column, title: 'Old');
      final opened = reopen(wb);
      // The reopened workbook builds on the saved bytes.
      final saved = writeXlsx(wb);
      final wb2 = readXlsx(saved);
      final e2 = SheetEditor(wb2);
      final chart = wb2.sheets.first.charts.single;
      e2.updateChart(wb2.sheets.first, chart, title: 'New', kind: ChartKind.line);
      final a = zipOf(writeXlsx(wb2));
      expect(textOf(a, 'xl/charts/chart1.xml'), contains('New'));
      expect(textOf(a, 'xl/charts/chart1.xml'), contains('<c:lineChart>'));
      expect(a.files.where((f) => f.name.startsWith('xl/charts/chart')).length, 1);
      expect(opened.sheets.first.charts, hasLength(1));

      final wb3 = readXlsx(saved);
      final e3 = SheetEditor(wb3);
      e3.removeChart(wb3.sheets.first, wb3.sheets.first.charts.single);
      final b = zipOf(writeXlsx(wb3));
      expect(has(b, 'xl/charts/chart1.xml'), isFalse);
      expect(textOf(b, '[Content_Types].xml'), isNot(contains('chart1.xml')));
      expect(has(b, 'xl/drawings/_rels/drawing1.xml.rels') ? textOf(b, 'xl/drawings/_rels/drawing1.xml.rels') : '', isNot(contains('chart1')));
      expect(XmlDocument.parse(textOf(b, 'xl/drawings/drawing1.xml')).rootElement.childElements, isEmpty);
      expect(readXlsx(writeXlsx(wb3)).sheets.first.charts, isEmpty);
    });

    test('a chart the app cannot draw is kept as it is when other things change, and can be removed', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      final a0 = zipOf(writeXlsx(wb));
      // Turn the saved chart into a bubble chart, as another program might have made it.
      final combined =
          '<?xml version="1.0"?><c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:bubbleChart/></c:plotArea></c:chart></c:chartSpace>';
      final patched = Archive();
      for (final f in a0.files) {
        patched.addFile(f.name == 'xl/charts/chart1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(combined)) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      final bytes = Uint8List.fromList(ZipEncoder().encode(patched));
      final wb2 = readXlsx(bytes);
      final chart = wb2.sheets.first.charts.single;
      expect(chart.editable, isFalse);
      expect(chart.unsupportedKind, contains('bubble'));
      expect(chart.label, contains('bubble'));
      final e2 = SheetEditor(wb2);
      e2.setInput(wb2.sheets.first, 8, 0, 'edited');
      final a = zipOf(writeXlsx(wb2));
      expect(textOf(a, 'xl/charts/chart1.xml'), combined, reason: 'the chart part is not touched');
      e2.updateChart(wb2.sheets.first, chart, title: 'x');
      expect(wb2.sheets.first.charts.single.title, '', reason: 'a chart that cannot be edited is not changed');
      e2.removeChart(wb2.sheets.first, chart);
      expect(has(zipOf(writeXlsx(wb2)), 'xl/charts/chart1.xml'), isFalse);
    });

    test('a drawing that already holds other things keeps them when a chart is added', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      final a0 = zipOf(writeXlsx(wb));
      // Add a picture anchor to the drawing, as a file with a logo has.
      final drawing = XmlDocument.parse(textOf(a0, 'xl/drawings/drawing1.xml'));
      drawing.rootElement.children.add(XmlDocument.parse('<xdr:oneCellAnchor xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"><xdr:pic/></xdr:oneCellAnchor>').rootElement.copy());
      final patched = Archive();
      for (final f in a0.files) {
        patched.addFile(f.name == 'xl/drawings/drawing1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(drawing.toXmlString())) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      final wb2 = readXlsx(Uint8List.fromList(ZipEncoder().encode(patched)));
      final e2 = SheetEditor(wb2);
      e2.addChart(wb2.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.area);
      final a = zipOf(writeXlsx(wb2));
      final out = XmlDocument.parse(textOf(a, 'xl/drawings/drawing1.xml'));
      expect(out.rootElement.childElements.map((c) => c.name.local), ['twoCellAnchor', 'oneCellAnchor', 'twoCellAnchor']);
      expect(has(a, 'xl/charts/chart2.xml'), isTrue);
      expect(has(a, 'xl/drawings/drawing2.xml'), isFalse, reason: 'the sheet keeps its single drawing');
    });
  });

  group('charts follow the cells', () {
    test('inserting and deleting rows and columns moves what a chart reads, and a chart that loses its data goes', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.insertRows(s, 0, 2);
      expect(s.charts.single.series.first.values.formula, "'Sheet1'!\$B\$4:\$B\$6");
      expect(s.charts.single.series.first.nameRef!.formula, "'Sheet1'!\$B\$3");
      e.insertCols(s, 0, 1);
      expect(s.charts.single.categories!.formula, "'Sheet1'!\$B\$4:\$B\$6");
      e.deleteRows(s, 4, 1);
      expect(s.charts.single.series.first.values.formula, "'Sheet1'!\$C\$4:\$C\$5");
      e.undo();
      expect(s.charts.single.series.first.values.formula, "'Sheet1'!\$C\$4:\$C\$6");
      e.deleteCols(s, 2, 2);
      expect(s.charts, isEmpty, reason: 'both series are gone');
    });

    test('renaming a sheet updates its charts, deleting the sheet takes charts that read it away, and a copy reads its own cells', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.line);
      final other = e.addSheet('Other');
      e.setInput(other, 0, 0, '1');
      e.setInput(other, 1, 0, '2');
      e.addChart(other, const MergeRange(0, 0, 1, 0), ChartKind.column);

      e.renameSheet(s, 'Sales');
      expect(s.charts.single.series.first.values.formula, "'Sales'!\$B\$2:\$B\$4");
      expect(resolveChart(wb, s.charts.single).series.first.values, [10, 12, 9]);

      final copy = e.duplicateSheet(s);
      final c = copy.charts.single;
      expect(c.series.first.values.sheet, copy.name);
      expect(c.partPath, isNull);
      expect(c.fromFile, isFalse);
      expect(s.charts.single.series.first.values.sheet, 'Sales');

      e.deleteSheet(other);
      expect(wb.sheets.contains(other), isFalse);
      e.undo();
      expect(wb.sheets.contains(other), isTrue);
      expect(other.charts, hasLength(1));
    });

    test('a chart whose data is on another sheet reads that sheet and goes when that sheet is deleted', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      final summary = e.addSheet('Summary');
      final chart = chartFromSelection(s, const MergeRange(0, 0, 3, 2), ChartKind.column);
      summary.charts.add(chart..col = 1);
      summary.chartsDirty = true;
      expect(resolveChart(wb, summary.charts.single).series, hasLength(2));
      e.deleteSheet(s);
      expect(summary.charts, isEmpty);
    });
  });

  group('moving and resizing', () {
    test('a new chart is written where it was put', () {
      final (wb, e) = book(sales);
      final c = e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.moveChart(wb.sheets.first, c, col: 6, row: 10, cols: 5, rows: 9);
      final a = zipOf(writeXlsx(wb));
      final d = textOf(a, 'xl/drawings/drawing1.xml');
      expect(d, contains('<xdr:col>6</xdr:col>'));
      expect(d, contains('<xdr:row>10</xdr:row>'));
      expect(d, contains('<xdr:col>11</xdr:col>'));
      expect(d, contains('<xdr:row>19</xdr:row>'));
      final back = reopen(wb).sheets.first.charts.single;
      expect([back.col, back.row, back.cols, back.rows], [6, 10, 5, 9]);
    });

    test('a chart from the file keeps its part and its shape id when moved, and only its place changes', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.line, title: 'Keep');
      final saved = writeXlsx(wb);
      final wb2 = readXlsx(saved);
      final e2 = SheetEditor(wb2);
      e2.moveChart(wb2.sheets.first, wb2.sheets.first.charts.single, col: 1, row: 20);
      final a = zipOf(writeXlsx(wb2));
      expect(textOf(a, 'xl/charts/chart1.xml'), textOf(zipOf(saved), 'xl/charts/chart1.xml'), reason: 'the chart itself is not rewritten');
      final d = XmlDocument.parse(textOf(a, 'xl/drawings/drawing1.xml'));
      expect(d.rootElement.childElements, hasLength(1));
      expect(textOf(a, 'xl/drawings/drawing1.xml'), contains('<xdr:row>20</xdr:row>'));
      final back = readXlsx(writeXlsx(wb2)).sheets.first.charts.single;
      expect([back.col, back.row, back.cols, back.rows], [1, 20, 8, 15]);
      expect(back.title, 'Keep');
    });

    test('sizes are kept sensible, nothing changes when the place is the same, and undo puts it back', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      final c = e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.moveChart(s, c, cols: 0, rows: 1);
      expect([s.charts.single.cols, s.charts.single.rows], [2, 3]);
      final same = s.charts.single;
      e.moveChart(s, same, col: same.col, row: same.row);
      e.undo();
      expect([s.charts.single.cols, s.charts.single.rows], [8, 15], reason: 'the no-change call added nothing to undo');
      expect(s.charts.single.moved, isFalse);
    });

    test('a chart the app cannot draw can be moved too', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      final a0 = zipOf(writeXlsx(wb));
      const combined =
          '<?xml version="1.0"?><c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:bubbleChart/></c:plotArea></c:chart></c:chartSpace>';
      final patched = Archive();
      for (final f in a0.files) {
        patched.addFile(f.name == 'xl/charts/chart1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(combined)) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      final wb2 = readXlsx(Uint8List.fromList(ZipEncoder().encode(patched)));
      final e2 = SheetEditor(wb2);
      e2.moveChart(wb2.sheets.first, wb2.sheets.first.charts.single, col: 9, row: 9);
      final a = zipOf(writeXlsx(wb2));
      expect(textOf(a, 'xl/charts/chart1.xml'), combined);
      expect(textOf(a, 'xl/drawings/drawing1.xml'), contains('<xdr:col>9</xdr:col>'));
    });
  });

  group('more kinds of chart', () {
    test('a scatter chart takes the numbers of the first column along the bottom, and is written and read back', () {
      final (wb, e) = book([
        ['Age', 'Height', 'Weight'],
        ['10', '140', '35'],
        ['12', '150', '42'],
        ['15', '165', '55'],
      ]);
      final c = e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.scatter, title: 'Growth');
      expect(c.categories!.formula, "'Sheet1'!\$A\$2:\$A\$4");
      final data = resolveChart(wb, c);
      expect(data.xs, [10, 12, 15]);
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      expect(xml, contains('<c:scatterChart>'));
      expect(xml, contains(r"<c:xVal><c:numRef><c:f>'Sheet1'!$A$2:$A$4</c:f>"));
      expect(xml, contains(r"<c:yVal><c:numRef><c:f>'Sheet1'!$B$2:$B$4</c:f>"));
      XmlDocument.parse(xml);
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.kind, ChartKind.scatter);
      expect(back.editable, isTrue);
      expect(back.series, hasLength(2));
      expect(back.categories!.formula, "'Sheet1'!\$A\$2:\$A\$4");
      expect(back.title, 'Growth');
    });

    test('text in the first column gives scatter points along 1, 2, 3', () {
      final (wb, e) = book(sales);
      final c = e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.scatter);
      expect(resolveChart(wb, c).xs, [1, 2, 3]);
    });

    test('percent stacked bars are read as editable, and written as shares of 100%', () {
      final (wb, e) = book(sales);
      final c = e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.updateChart(wb.sheets.first, c, stacked: true, percent: true);
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      expect(xml, contains('<c:grouping val="percentStacked"/>'));
      expect(xml, contains('formatCode="0%"'));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.stacked, isTrue);
      expect(back.percent, isTrue);
      expect(back.editable, isTrue);
      final e2 = SheetEditor(reopen(wb));
      // Turning the stacking off also turns the shares off.
      final wb2 = readXlsx(writeXlsx(wb));
      final e3 = SheetEditor(wb2);
      e3.updateChart(wb2.sheets.first, wb2.sheets.first.charts.single, stacked: false);
      expect(wb2.sheets.first.charts.single.percent, isFalse);
      expect(e2.canUndo, isFalse);
    });

    test('3-D charts from other programs are read as their flat kinds, so they can be changed', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column, title: 'Flat');
      final a0 = zipOf(writeXlsx(wb));
      final threeD = textOf(a0, 'xl/charts/chart1.xml').replaceAll('c:barChart', 'c:bar3DChart');
      final patched = Archive();
      for (final f in a0.files) {
        patched.addFile(f.name == 'xl/charts/chart1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(threeD)) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      final back = readXlsx(Uint8List.fromList(ZipEncoder().encode(patched))).sheets.first.charts.single;
      expect(back.editable, isTrue);
      expect(back.kind, ChartKind.column);
      expect(back.title, 'Flat');
    });
  });

  group('trend lines', () {
    List<double> xs(int n) => [for (var i = 1; i <= n; i++) i.toDouble()];

    test('a straight line fits numbers that grow evenly, ends at the first and last point, and skips missing numbers', () {
      final pts = trendPoints(TrendKind.linear, xs(5), [3, 5, null, 9, 11]);
      expect(pts, hasLength(2));
      expect(pts.first.x, 1);
      expect(pts.last.x, 5);
      expect(pts.first.y, closeTo(3, 1e-9));
      expect(pts.last.y, closeTo(11, 1e-9));
    });

    test('an exponential trend follows numbers that double, and ignores numbers that are not above zero', () {
      final pts = trendPoints(TrendKind.exponential, xs(5), [2, 4, 8, 16, 32]);
      expect(pts.length, greaterThan(5));
      expect(pts.first.y, closeTo(2, 1e-6));
      expect(pts.last.y, closeTo(32, 1e-6));
      expect(trendPoints(TrendKind.exponential, xs(3), [0, -1, 5]), isEmpty, reason: 'only one number is above zero');
    });

    test('a curved trend recovers a parabola, even when the x values are far from zero', () {
      final x = <double>[100, 101, 102, 103, 104];
      final y = <double?>[for (final v in x) 0.5 * v * v - 3 * v + 7];
      final pts = trendPoints(TrendKind.polynomial, x, y);
      for (final p in pts) {
        expect(p.y, closeTo(0.5 * p.x * p.x - 3 * p.x + 7, 1e-3));
      }
      expect(pts.first.x, 100);
      expect(pts.last.x, 104);
      expect(trendPoints(TrendKind.polynomial, [1.0, 2], [1, 3]), hasLength(2), reason: 'two numbers give a straight line');
    });

    test('a moving average starts when there are three numbers to average', () {
      final pts = trendPoints(TrendKind.movingAverage, xs(5), [3, 6, 9, 12, 15]);
      expect(pts.map((p) => p.x), [3, 4, 5]);
      expect(pts.map((p) => p.y), [6, 9, 12]);
      expect(trendPoints(TrendKind.movingAverage, xs(2), [1, 2]), isEmpty);
    });

    test('no numbers, one number, equal x values or no trend give nothing', () {
      expect(trendPoints(TrendKind.linear, xs(3), [null, 4, null]), isEmpty);
      expect(trendPoints(TrendKind.linear, [2.0, 2, 2], [1, 2, 3]), isEmpty);
      expect(trendPoints(TrendKind.none, xs(3), [1, 2, 3]), isEmpty);
    });
  });

  group('colours, mixed charts and trend lines in the file', () {
    (Workbook, SheetEditor, SheetChart) mixed() {
      final (wb, e) = book(sales);
      final c = e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column, title: 'Mixed');
      e.updateSeries(wb.sheets.first, wb.sheets.first.charts.single, 0, (s) => s.copyWith(color: 0xFF112233, trend: TrendKind.linear));
      e.updateSeries(wb.sheets.first, wb.sheets.first.charts.single, 1, (s) => s.copyWith(kind: ChartKind.line, secondary: true, color: 0xFFAA5500, trend: TrendKind.polynomial));
      return (wb, e, c);
    }

    test('a column series and a line on the second scale are written as two chart elements with their own axes, colours and trend lines', () {
      final (wb, _, _) = mixed();
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      XmlDocument.parse(xml);
      expect(xml, contains('<c:barChart>'));
      expect(xml, contains('<c:lineChart>'));
      expect(RegExp('<c:catAx>').allMatches(xml), hasLength(2));
      expect(RegExp('<c:valAx>').allMatches(xml), hasLength(2));
      expect(xml, contains('<c:crosses val="max"/>'));
      expect(xml, contains('<a:srgbClr val="112233"/>'));
      expect(xml, contains('<a:srgbClr val="AA5500"/>'));
      expect(xml, contains('<c:trendlineType val="linear"/>'));
      expect(xml, contains('<c:trendlineType val="poly"/><c:order val="2"/>'));
      expect(xml.indexOf('<c:barChart>'), lessThan(xml.indexOf('<c:lineChart>')));
      // Each element is tied to its own pair of axes.
      final bar = xml.substring(xml.indexOf('<c:barChart>'), xml.indexOf('</c:barChart>'));
      final line = xml.substring(xml.indexOf('<c:lineChart>'), xml.indexOf('</c:lineChart>'));
      expect(bar, contains('510001'));
      expect(line, contains('510003'));
    });

    test('all of it reads back from the file: kinds, second scale, colours and trends, in the order of the series', () {
      final (wb, _, _) = mixed();
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.editable, isTrue);
      expect(back.kind, ChartKind.column);
      expect(back.series, hasLength(2));
      expect(back.series[0].kind, isNull);
      expect(back.series[0].color, 0xFF112233);
      expect(back.series[0].trend, TrendKind.linear);
      expect(back.series[0].secondary, isFalse);
      expect(back.series[1].kind, ChartKind.line);
      expect(back.series[1].secondary, isTrue);
      expect(back.series[1].color, 0xFFAA5500);
      expect(back.series[1].trend, TrendKind.polynomial);
      expect(back.isCombined, isTrue);
      expect(back.title, 'Mixed');
    });

    test('a file with columns and a line on the same scale (as other programs write it) is editable', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.updateSeries(wb.sheets.first, wb.sheets.first.charts.single, 1, (s) => s.copyWith(kind: ChartKind.line));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.editable, isTrue);
      expect(back.series[1].kind, ChartKind.line);
      expect(back.series[1].secondary, isFalse);
      expect(RegExp('<c:catAx>').allMatches(textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml')), hasLength(1), reason: 'one set of axes when nothing uses the second scale');
    });

    test('series settings follow the cells when rows are inserted and survive a copy of the sheet', () {
      final (wb, e, _) = mixed();
      final s = wb.sheets.first;
      e.insertRows(s, 0, 1);
      expect(s.charts.single.series[1].kind, ChartKind.line);
      expect(s.charts.single.series[1].color, 0xFFAA5500);
      expect(s.charts.single.series[0].trend, TrendKind.linear);
      final copy = e.duplicateSheet(s);
      expect(copy.charts.single.series[1].secondary, isTrue);
    });

    test('a series cannot be drawn differently in a pie or a sideways bar chart, and turning a chart into one clears the mixing', () {
      final (wb, e, _) = mixed();
      final s = wb.sheets.first;
      e.updateChart(s, s.charts.single, kind: ChartKind.bar);
      expect(s.charts.single.series[1].kind, isNull);
      expect(s.charts.single.series[1].secondary, isFalse);
      expect(s.charts.single.series[1].color, 0xFFAA5500, reason: 'colours stay');
      expect(s.charts.single.series[1].trend, TrendKind.polynomial, reason: 'trend stays');
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(kind: ChartKind.line, secondary: true));
      expect(s.charts.single.series[0].kind, isNull, reason: 'ignored for a bar chart');
      e.updateChart(s, s.charts.single, kind: ChartKind.pie);
      expect(s.charts.single.series, hasLength(1));
      expect(s.charts.single.series.single.trend, TrendKind.none);
    });

    test('choosing the chart kind for a series, or changing nothing, is not a change; undo takes one step back', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(kind: ChartKind.column));
      expect(s.charts.single.series[0].kind, isNull);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(color: 0xFF010203));
      expect(s.charts.single.series[0].color, 0xFF010203);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(color: null));
      expect(s.charts.single.series[0].color, isNull);
      e.undo();
      expect(s.charts.single.series[0].color, 0xFF010203);
      e.undo();
      expect(s.charts.single.series[0].color, isNull);
      e.undo();
      expect(s.charts, isEmpty, reason: 'the first undo steps were the colour changes, not the no-op');
    });

    test('a scatter chart keeps colours and trend lines', () {
      final (wb, e) = book([
        ['x', 'y'],
        ['1', '2'],
        ['2', '4'],
        ['3', '7'],
      ]);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 1), ChartKind.scatter);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(color: 0xFF336699, trend: TrendKind.linear));
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      expect(xml.indexOf('<c:trendline>'), lessThan(xml.indexOf('<c:xVal>')));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.series.single.color, 0xFF336699);
      expect(back.series.single.trend, TrendKind.linear);
    });
  });

  group('what a trend line says', () {
    List<double> xs(int n) => [for (var i = 1; i <= n; i++) i.toDouble()];

    test('a straight line is written as y = bx + a, with R squared 1 for numbers on a line', () {
      final t = trendSummary(TrendKind.linear, xs(4), [3, 5, 7, 9])!;
      expect(t.equation, 'y = 2x + 1');
      expect(t.r2, closeTo(1, 1e-9));
      expect(trendSummary(TrendKind.linear, xs(3), [9, 6, 3])!.equation, 'y = -3x + 12');
    });

    test('R squared falls when the numbers scatter around the line', () {
      final t = trendSummary(TrendKind.linear, xs(6), [2, 9, 3, 10, 4, 12])!;
      expect(t.r2, lessThan(0.9));
      expect(t.r2, greaterThan(0));
      expect(trendSummary(TrendKind.linear, xs(3), [5, 5, 5])!.r2, 1, reason: 'a flat line fits flat numbers');
    });

    test('exponential and curved trends give their own equations', () {
      final e = trendSummary(TrendKind.exponential, xs(5), [2, 4, 8, 16, 32])!;
      expect(e.equation, startsWith('y = 1'));
      expect(e.equation, contains('e^0.6931x'));
      expect(e.r2, closeTo(1, 1e-9));
      final c = trendSummary(TrendKind.polynomial, xs(5), [for (final x in xs(5)) 2 * x * x - 3 * x + 4])!;
      expect(c.equation, 'y = 2x² - 3x + 4');
      expect(c.r2, closeTo(1, 1e-9));
    });

    test('a moving average, no trend, or too few numbers have nothing to say', () {
      expect(trendSummary(TrendKind.movingAverage, xs(5), [1, 2, 3, 4, 5]), isNull);
      expect(trendSummary(TrendKind.none, xs(5), [1, 2, 3, 4, 5]), isNull);
      expect(trendSummary(TrendKind.linear, xs(3), [null, 4, null]), isNull);
    });
  });

  group('equations, labels, point colours and doughnuts in the file', () {
    test('the equation and R squared switches are written and read back, and only for a trend line that can have them', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.line);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(trend: TrendKind.linear, showEquation: true, showR2: true));
      e.updateSeries(s, s.charts.single, 1, (x) => x.copyWith(trend: TrendKind.movingAverage, showEquation: true));
      expect(s.charts.single.series[1].showEquation, isFalse, reason: 'a moving average has no equation');
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      expect(xml, contains('<c:dispRSqr val="1"/><c:dispEq val="1"/>'));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.series[0].showEquation, isTrue);
      expect(back.series[0].showR2, isTrue);
      expect(back.series[1].showEquation, isFalse);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(trend: TrendKind.none));
      expect(s.charts.single.series[0].showEquation, isFalse, reason: 'switching the trend off clears the switches');
    });

    test('value labels on bars and lines are written as data labels and read back; a series without them has none', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(labels: LabelKind.value));
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      expect(RegExp('<c:dLbls>').allMatches(xml), hasLength(1));
      expect(xml, contains('<c:showVal val="1"/>'));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.series[0].labels, LabelKind.value);
      expect(back.series[1].labels, isNull);
      expect(back.labelsOf(1), LabelKind.none);
    });

    test('a pie shows percentages unless told otherwise; its choice is kept either way', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.pie);
      expect(s.charts.single.labelsOf(0), LabelKind.percent);
      expect(textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml'), contains('<c:showPercent val="1"/>'));
      expect(reopen(wb).sheets.first.charts.single.series.single.labels, isNull, reason: 'the usual is not stored');
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(labels: LabelKind.none));
      expect(textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml'), contains('<c:showPercent val="0"/>'));
      expect(reopen(wb).sheets.first.charts.single.labelsOf(0), LabelKind.none);
      e.updateSeries(s, s.charts.single, 0, (x) => x.copyWith(labels: LabelKind.value));
      expect(reopen(wb).sheets.first.charts.single.labelsOf(0), LabelKind.value);
    });

    test('single slices of a pie and single bars can have their own colour, and it survives saving', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.pie);
      e.updateSeries(s, s.charts.single, 0, (x) => x.withPointColor(1, 0xFF123456));
      var xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      expect(xml, contains('<a:srgbClr val="123456"/>'));
      expect(RegExp('<c:dPt>').allMatches(xml), hasLength(3), reason: 'every slice has its colour written');
      var back = reopen(wb).sheets.first.charts.single.series.single;
      expect(back.pointColor(1), 0xFF123456);
      expect(back.pointColor(0), 0xFF4472C4, reason: 'the standard colour of slice 1 was written, so it reads back as that colour');

      final (wb2, e2) = book(sales);
      final s2 = wb2.sheets.first;
      e2.addChart(s2, const MergeRange(0, 0, 3, 2), ChartKind.column);
      e2.updateSeries(s2, s2.charts.single, 0, (x) => x.withPointColor(2, 0xFFAA0000));
      xml = textOf(zipOf(writeXlsx(wb2)), 'xl/charts/chart1.xml');
      expect(RegExp('<c:dPt>').allMatches(xml), hasLength(1), reason: 'only the changed bar is written');
      back = reopen(wb2).sheets.first.charts.single.series.first;
      expect(back.pointColors, [null, null, 0xFFAA0000]);
      expect(back.withPointColor(2, null).pointColors, isEmpty, reason: 'back to the series colour drops the entry');
    });

    test('a doughnut is a pie with a hole: written as its own element, read back as editable, one series', () {
      final (wb, e) = book(sales);
      final s = wb.sheets.first;
      final c = e.addChart(s, const MergeRange(0, 0, 3, 2), ChartKind.doughnut, title: 'Ring');
      expect(c.series, hasLength(1));
      final xml = textOf(zipOf(writeXlsx(wb)), 'xl/charts/chart1.xml');
      XmlDocument.parse(xml);
      expect(xml, contains('<c:doughnutChart>'));
      expect(xml, contains('<c:holeSize val="50"/>'));
      expect(xml, isNot(contains('<c:catAx>')));
      final back = reopen(wb).sheets.first.charts.single;
      expect(back.kind, ChartKind.doughnut);
      expect(back.editable, isTrue);
      expect(back.title, 'Ring');
      expect(back.labelsOf(0), LabelKind.percent);
      // To and from a pie.
      e.updateChart(s, s.charts.single, kind: ChartKind.column);
      expect(s.charts.single.kind, ChartKind.column);
      e.updateChart(s, s.charts.single, kind: ChartKind.doughnut);
      expect(s.charts.single.series, hasLength(1), reason: 'one series, as for a pie');
    });

    test('3-D pies from other programs open as pies', () {
      final (wb, e) = book(sales);
      e.addChart(wb.sheets.first, const MergeRange(0, 0, 3, 2), ChartKind.doughnut);
      final a0 = zipOf(writeXlsx(wb));
      final xml = textOf(a0, 'xl/charts/chart1.xml').replaceAll('c:doughnutChart', 'c:pie3DChart');
      final patched = Archive();
      for (final f in a0.files) {
        patched.addFile(f.name == 'xl/charts/chart1.xml' ? ArchiveFile.bytes(f.name, utf8.encode(xml)) : ArchiveFile.bytes(f.name, f.readBytes()!));
      }
      expect(readXlsx(Uint8List.fromList(ZipEncoder().encode(patched))).sheets.first.charts.single.kind, ChartKind.pie);
    });
  });
}

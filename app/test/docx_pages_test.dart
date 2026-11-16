import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/features/export/data/document_builders.dart';
import 'package:doculoom/features/export/domain/entities/export_options.dart';
import 'package:doculoom/features/reader/data/docx_pages.dart';

const _w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

String _docx(Directory dir, String body, {String name = 'doc.docx', String? sect}) {
  final xml = '<?xml version="1.0" encoding="UTF-8"?><w:document $_w><w:body>$body${sect ?? ''}</w:body></w:document>';
  final archive = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  final f = File('${dir.path}/$name')..writeAsBytesSync(ZipEncoder().encode(archive));
  return f.path;
}

String _para(String text) => '<w:p><w:r><w:t>$text</w:t></w:r></w:p>';

Future<img.Image> _decode(String path) async => img.decodePng(File(path).readAsBytesSync())!;

int _rgb(img.Pixel p) => (p.r.toInt() << 16) | (p.g.toInt() << 8) | p.b.toInt();

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('doculoom_docx_pages'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<DocxRendered?> render(WidgetTester t, String path) async =>
      (await t.runAsync<DocxRendered?>(() => renderDocxPages(path: path, outDir: '${tmp.path}/out', prefix: 'p')));

  testWidgets('a table cell\'s fill is drawn, with its text on top and the right side left white', (tester) async {
    final r = await render(tester, 'test/fixtures/sidebar_resume.docx');
    expect(r, isNotNull);
    expect(r!.pages, hasLength(1));
    expect(r.plainText, contains('MULLASAAB'));
    expect(r.plainText, contains('Amazon, Bangalore'));

    final page = await tester.runAsync(() => _decode(r.pages.single.path));
    final image = page!;
    expect(image.width, 1240);
    // The sidebar is the dark blue of the file, from the top of the page to the bottom.
    expect(_rgb(image.getPixel((image.width * 0.1).round(), (image.height * 0.5).round())), 0x1E3A5A);
    expect(_rgb(image.getPixel((image.width * 0.1).round(), 5)), 0x1E3A5A);
    // The part to the right of it has no fill.
    expect(_rgb(image.getPixel((image.width * 0.8).round(), (image.height * 0.5).round())), 0xFFFFFF);
    r.dispose();
  });

  testWidgets('searching finds words in the drawn page and marks them where they are', (tester) async {
    final r = (await render(tester, 'test/fixtures/sidebar_resume.docx'))!;
    final hits = r.search('amazon');
    expect(hits, hasLength(1));
    expect(hits.single.page, 0);
    final box = hits.single.rects.single;
    expect(box.left, greaterThan(0.35), reason: 'the word is in the right column, not the sidebar');
    expect(box.top, inInclusiveRange(0.0, 0.3));
    expect(r.search('contact'), hasLength(1), reason: 'case does not matter, and the word is drawn in capitals');
    r.dispose();
  });

  testWidgets('a plain file with no styles or page settings flows over several A4 pages', (tester) async {
    final body = [for (var i = 0; i < 160; i++) _para('Paragraph number $i has a few words in it so that it takes a line.')].join();
    final r = (await render(tester, _docx(tmp, body)))!;
    expect(r.pages.length, greaterThan(2));
    expect(r.pages.first.aspect, closeTo(595.3 / 841.9, 0.001));
    final late = r.search('number 150');
    expect(late, hasLength(1));
    expect(late.single.page, greaterThan(1), reason: 'a late paragraph is on a late page');
    expect(r.plainText, contains('Paragraph number 159'));
    r.dispose();
  });

  testWidgets('a table with shaded cells and borders draws both', (tester) async {
    const table =
        '<w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="8" w:color="000000"/><w:left w:val="single" w:sz="8" w:color="000000"/>'
        '<w:bottom w:val="single" w:sz="8" w:color="000000"/><w:right w:val="single" w:sz="8" w:color="000000"/>'
        '<w:insideH w:val="single" w:sz="8" w:color="000000"/><w:insideV w:val="single" w:sz="8" w:color="000000"/></w:tblBorders></w:tblPr>'
        '<w:tblGrid><w:gridCol w:w="4000"/><w:gridCol w:w="4000"/></w:tblGrid>'
        '<w:tr><w:tc><w:tcPr><w:tcW w:w="4000" w:type="dxa"/><w:shd w:val="clear" w:color="auto" w:fill="FF0000"/></w:tcPr>${'<w:p><w:r><w:t>Red</w:t></w:r></w:p>'}</w:tc>'
        '<w:tc><w:tcPr><w:tcW w:w="4000" w:type="dxa"/></w:tcPr><w:p><w:r><w:t>Plain</w:t></w:r></w:p></w:tc></w:tr></w:tbl>';
    final r = (await render(
      tester,
      _docx(tmp, table, sect: '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0"/></w:sectPr>'),
    ))!;
    final image = (await tester.runAsync(() => _decode(r.pages.single.path)))!;
    // Zero margins: the first cell starts at the left edge and is red in its lower right part, clear of the text.
    expect(_rgb(image.getPixel(300, 10)), 0xFF0000);
    expect(_rgb(image.getPixel(600, 10)), 0xFFFFFF);
    r.dispose();
  });

  testWidgets('a file of pictures only is left to the picture path, and so is a file that is not a Word file', (tester) async {
    final pages = <PageSource>[];
    final image = img.Image(width: 60, height: 80)..clear(img.ColorRgb8(10, 20, 30));
    final jpg = File('${tmp.path}/a.jpg')..writeAsBytesSync(img.encodeJpg(image));
    pages.add(PageSource(path: jpg.path, width: 60, height: 80));
    buildDocx(pages, ExportQuality.high, '${tmp.path}/scan.docx');
    expect(await render(tester, '${tmp.path}/scan.docx'), isNull);

    final bad = File('${tmp.path}/bad.docx')..writeAsStringSync('not a zip');
    expect(await render(tester, bad.path), isNull);
    expect(await render(tester, _docx(tmp, '', name: 'empty.docx')), isNull);
  });

  testWidgets('bullets, numbers, tab stops and bold text in a styled file are drawn without trouble', (tester) async {
    const styles =
        '<w:styles $_w><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val="22"/></w:rPr></w:rPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
        '<w:style w:type="paragraph" w:styleId="Item"><w:name w:val="Item"/><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr></w:style></w:styles>';
    const numbering =
        '<w:numbering $_w><w:abstractNum w:abstractNumId="0"><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/>'
        '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num></w:numbering>';
    final body =
        '${'<w:p><w:pPr><w:pStyle w:val="Item"/></w:pPr><w:r><w:t>First item</w:t></w:r></w:p>' * 2}'
        '<w:p><w:pPr><w:tabs><w:tab w:val="right" w:pos="9000"/></w:tabs></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Left side</w:t></w:r><w:r><w:tab/></w:r><w:r><w:t>Right side</w:t></w:r></w:p>';
    final xml = '<?xml version="1.0" encoding="UTF-8"?><w:document $_w><w:body>$body</w:body></w:document>';
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)))
      ..addFile(ArchiveFile.bytes('word/styles.xml', utf8.encode(styles)))
      ..addFile(ArchiveFile.bytes('word/numbering.xml', utf8.encode(numbering)));
    final f = File('${tmp.path}/styled.docx')..writeAsBytesSync(ZipEncoder().encode(archive));
    final r = (await render(tester, f.path))!;
    expect(r.pages, hasLength(1));
    expect(r.plainText, contains('Left side'));
    expect(r.search('right side'), hasLength(1));
    r.dispose();
  });
}

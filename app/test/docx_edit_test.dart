import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/features/text_edit/docx/docx_document.dart';

Uint8List png(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)));

String part(Uint8List docx, String name) => String.fromCharCodes(ZipDecoder().decodeBytes(docx).findFile(name)!.readBytes()!);
bool hasPart(Uint8List docx, String name) => ZipDecoder().decodeBytes(docx).findFile(name) != null;

DocxDocument openSample() => DocxDocument.open(File('test/fixtures/text_edit/sample.docx').readAsBytesSync());

List<ParaBlock> paragraphs(DocxDocument d) {
  final out = <ParaBlock>[];
  void walk(List<DocBlock> blocks) {
    for (final b in blocks) {
      switch (b) {
        case ParaBlock():
          out.add(b);
        case TableBlock():
          for (final row in b.rows) {
            for (final cell in row) {
              walk(cell);
            }
          }
      }
    }
  }

  walk(d.view());
  return out;
}

ParaBlock para(DocxDocument d, String startsWith) => paragraphs(d).firstWhere((p) => p.text.startsWith(startsWith));

void main() {
  test('shows headings, looks, lists, alignment, tables and pictures', () {
    final d = openSample();
    final all = paragraphs(d);
    expect(all.map((p) => p.index), List.generate(all.length, (i) => i), reason: 'paragraphs are numbered in reading order');
    expect(para(d, 'Quarterly').headingLevel, 1);

    final mixed = para(d, 'The quick');
    expect(mixed.text, 'The quick brown fox jumps over the lazy dog.');
    final brown = mixed.spans.firstWhere((s) => s.text == 'brown');
    expect(brown.bold, isTrue);
    final jumps = mixed.spans.firstWhere((s) => s.text == 'jumps');
    expect(jumps.italic, isTrue);
    expect(jumps.color, 0xFFC00000);
    expect(mixed.spans.firstWhere((s) => s.text == ' fox ').bold, isFalse);

    expect(para(d, 'First bullet').listLabel, '\u2022');
    expect(para(d, 'Step one').listLabel, '1.');
    expect(para(d, 'Step two').listLabel, '2.');
    expect(para(d, 'Centered').align, 'center');

    final table = d.view().whereType<TableBlock>().single;
    expect(table.rows.length, 2);
    expect(table.rows[1].map((c) => (c.single as ParaBlock).text), ['Fox Ltd', '1,250']);

    final picture = all.firstWhere((p) => p.images.isNotEmpty);
    expect(d.imageBytes(picture.images.single), isNotNull);
  });

  test('changing a word keeps the look of the words around it', () {
    final d = openSample();
    final p = para(d, 'The quick');
    d.setParagraphText(p.index, 'The quick brown cat jumps over the lazy dog.');
    final after = para(d, 'The quick');
    expect(after.text, 'The quick brown cat jumps over the lazy dog.');
    expect(after.spans.firstWhere((s) => s.text == 'brown').bold, isTrue);
    expect(after.spans.firstWhere((s) => s.text == 'jumps').italic, isTrue);
    expect(after.spans.firstWhere((s) => s.text == ' cat ').bold, isFalse);
  });

  test('editing the bold word itself keeps it bold, and typing at the start or end works', () {
    final d = openSample();
    final i = para(d, 'The quick').index;
    d.setParagraphText(i, 'The quick black fox jumps over the lazy dog.');
    expect(para(d, 'The quick').spans.firstWhere((s) => s.text == 'black').bold, isTrue);
    d.setParagraphText(i, 'Oh. The quick black fox jumps over the lazy dog. Really!');
    final text = para(d, 'Oh.');
    expect(text.text, 'Oh. The quick black fox jumps over the lazy dog. Really!');
    expect(text.spans.first.text, startsWith('Oh. The quick'));
  });

  test('deleting across looks and clearing a paragraph', () {
    final d = openSample();
    final i = para(d, 'The quick').index;
    d.setParagraphText(i, 'The quick jumps over the lazy dog.');
    expect(para(d, 'The quick').text, 'The quick jumps over the lazy dog.');
    d.setParagraphText(i, '');
    expect(paragraphs(d).firstWhere((p) => p.index == i).text, '');
    d.setParagraphText(i, 'Brand new');
    expect(paragraphs(d).firstWhere((p) => p.index == i).text, 'Brand new');
  });

  test('tabs and line breaks survive', () {
    final d = openSample();
    final i = para(d, 'Last paragraph').index;
    d.setParagraphText(i, 'one\ttwo\nthree');
    expect(para(d, 'one').text, 'one\ttwo\nthree');
  });

  test('bold, italic, underline, size and colour apply to the selection only', () {
    final d = openSample();
    final i = para(d, 'The quick').index;
    final text = para(d, 'The quick').text;
    final start = text.indexOf('lazy');
    d.formatRange(i, start, start + 4, const FormatChange(bold: true, underline: true, sizePt: 20, color: 0x0000FF));
    final spans = para(d, 'The quick').spans;
    final lazy = spans.firstWhere((s) => s.text == 'lazy');
    expect(lazy.bold, isTrue);
    expect(lazy.underline, isTrue);
    expect(lazy.sizePt, 20);
    expect(lazy.color, 0xFF0000FF);
    expect(spans.firstWhere((s) => s.text.contains('over the')).bold, isFalse);
    expect(para(d, 'The quick').text, text);

    expect(d.formatOf(i, start, start + 4).bold, isTrue);
    expect(d.formatOf(i, 0, text.length).bold, isNull, reason: 'a mixed selection has no single setting');

    d.formatRange(i, start, start + 4, const FormatChange(bold: false, clearColor: true));
    expect(para(d, 'The quick').spans.firstWhere((s) => s.text == 'lazy').bold, isFalse);
  });

  test('the font of a selection can be read and changed, and survives saving', () {
    final d = openSample();
    final i = para(d, 'The quick').index;
    final text = para(d, 'The quick').text;
    final start = text.indexOf('lazy');
    d.formatRange(i, start, start + 4, const FormatChange(font: 'Georgia'));
    expect(para(d, 'The quick').spans.firstWhere((s) => s.text == 'lazy').font, 'Georgia');
    expect(d.formatOf(i, start, start + 4).font, 'Georgia');
    expect(d.formatOf(i, 0, text.length).font, isNull, reason: 'a mixed selection has no single font');
    d.formatRange(i, 0, 0, const FormatChange(font: 'Courier New'));
    final again = DocxDocument.open(d.save());
    expect(para(again, 'The quick').spans.every((s) => s.font == 'Courier New'), isTrue);
    expect(para(again, 'The quick').text, text);
  });

  test('a whole paragraph is formatted when nothing is selected, and alignment changes', () {
    final d = openSample();
    final i = para(d, 'Last paragraph').index;
    d.formatRange(i, 0, 0, const FormatChange(italic: true));
    expect(para(d, 'Last paragraph').spans.every((s) => s.italic), isTrue);
    d.setAlign(i, 'right');
    expect(para(d, 'Last paragraph').align, 'right');
    d.setAlign(i, 'both');
    expect(para(d, 'Last paragraph').align, 'both');
  });

  test('paragraphs can be added after another, and removed; a table cell keeps one', () {
    final d = openSample();
    final before = paragraphs(d).length;
    final first = para(d, 'First bullet').index;
    final created = d.insertParagraphAfter(first, text: 'Third bullet');
    expect(paragraphs(d).length, before + 1);
    expect(paragraphs(d).firstWhere((p) => p.index == created).text, 'Third bullet');
    expect(paragraphs(d).firstWhere((p) => p.index == created).listLabel, '\u2022', reason: 'a new list item stays in the list');

    d.deleteParagraph(created);
    expect(paragraphs(d).length, before);

    final cell = para(d, 'Fox Ltd').index;
    d.deleteParagraph(cell);
    expect(paragraphs(d).length, before, reason: 'the cell still has its paragraph');
    expect(paragraphs(d).firstWhere((p) => p.index == cell).text, '');
  });

  test('editing a paragraph with a picture keeps the picture', () {
    final d = openSample();
    final withPicture = paragraphs(d).firstWhere((p) => p.images.isNotEmpty);
    d.setParagraphText(withPicture.index, 'A caption');
    final after = paragraphs(d).firstWhere((p) => p.index == withPicture.index);
    expect(after.text, 'A caption');
    expect(after.images, withPicture.images);
  });

  test('find and replace over the whole document, with and without case', () {
    final d = openSample();
    expect(d.findAll('fox').length, 4);
    expect(d.findAll('fox', matchCase: true).length, 2);
    expect(d.findAll('zebra'), isEmpty);
    expect(d.replaceAll('fox', 'wolf'), 4);
    expect(para(d, 'The quick').text, 'The quick brown wolf jumps over the lazy dog.');
    expect(para(d, 'Centered').text, 'Centered line about the wolf');
    expect(para(d, 'wolf Ltd').text, 'wolf Ltd', reason: 'table text changed too');
    expect(para(d, 'The quick').spans.firstWhere((s) => s.text == 'jumps').italic, isTrue);
  });

  test('undo and redo walk back through the changes', () {
    final d = openSample();
    final i = para(d, 'The quick').index;
    expect(d.canUndo, isFalse);
    d.setParagraphText(i, 'one');
    d.setParagraphText(i, 'two');
    expect(d.canUndo, isTrue);
    d.undo();
    expect(para(d, 'one').text, 'one');
    d.undo();
    expect(para(d, 'The quick').text, 'The quick brown fox jumps over the lazy dog.');
    expect(d.canUndo, isFalse);
    d.redo();
    d.redo();
    expect(para(d, 'two').text, 'two');
    expect(d.canRedo, isFalse);
    d.setParagraphText(i, 'three');
    expect(d.canRedo, isFalse, reason: 'a new change ends the redo history');
  });

  test('the saved file opens again with the changes, and everything else in it is untouched', () {
    final d = openSample();
    d.setParagraphText(para(d, 'The quick').index, 'The quick brown cat jumps over the lazy dog.');
    d.replaceAll('Fox', 'Cat');
    d.formatRange(para(d, 'Last paragraph').index, 0, 0, const FormatChange(bold: true, color: 0xFF0000));
    final bytes = d.save();
    File('/tmp/edited_sample.docx').writeAsBytesSync(bytes);
    final again = DocxDocument.open(bytes);
    expect(para(again, 'The quick').text, 'The quick brown cat jumps over the lazy dog.');
    expect(para(again, 'Centered').text, 'Centered line about the Cat');
    expect(para(again, 'Last paragraph').spans.single.bold, isTrue);
    final original = openSample();
    expect(again.view().whereType<TableBlock>().single.rows.length, 2);
    expect(
      again.imageBytes(paragraphs(again).firstWhere((p) => p.images.isNotEmpty).images.single),
      original.imageBytes(paragraphs(original).firstWhere((p) => p.images.isNotEmpty).images.single),
    );
  });

  test('a picture goes in its own paragraph, is shown, survives saving and can be undone', () {
    final d = openSample();
    final before = paragraphs(d).length;
    final at = para(d, 'Last paragraph').index;
    final created = d.insertPictureAfter(at, png(40, 20), extension: '.PNG', pixelWidth: 40, pixelHeight: 20);
    expect(created, at + 1);
    expect(paragraphs(d).length, before + 1);
    final shown = paragraphs(d)[created];
    expect(shown.text, isEmpty);
    expect(shown.align, 'center');
    expect(d.imageBytes(shown.images.single), isNotNull, reason: 'shown at once, before saving');

    final bytes = d.save();
    expect(hasPart(bytes, 'word/media/dlpic1.png'), isTrue);
    expect(part(bytes, '[Content_Types].xml'), contains('Extension="png"'));
    expect(part(bytes, 'word/_rels/document.xml.rels'), contains('Target="media/dlpic1.png"'));
    final doc = part(bytes, 'word/document.xml');
    expect(doc, contains('r:embed="rIdDlPic1"'));
    expect(doc, contains('cx="381000" cy="190500"'), reason: '40 x 20 pixels is 30 x 15 points');

    final again = DocxDocument.open(bytes);
    final picture = paragraphs(again).where((p) => p.images.any((i) => i.endsWith('dlpic1.png')));
    expect(picture, hasLength(1));
    expect(again.imageBytes(picture.single.images.single), png(40, 20));
    expect(paragraphs(again).where((p) => p.images.isNotEmpty), hasLength(2), reason: 'the original picture is still there');

    d.undo();
    expect(paragraphs(d).length, before);
  });

  test('a wide picture is made to fit the page and keeps its shape; only PNG and JPEG are taken', () {
    final d = openSample();
    final created = d.insertPictureAfter(0, png(2000, 1000), extension: 'jpeg', pixelWidth: 2000, pixelHeight: 1000);
    expect(created, 1);
    final xml = part(d.save(), 'word/document.xml');
    expect(xml, contains('cx="5080000" cy="2540000"'), reason: '400 x 200 points');
    expect(() => d.insertPictureAfter(0, png(2, 2), extension: 'gif', pixelWidth: 2, pixelHeight: 2), throwsArgumentError);
    expect(() => d.insertPictureAfter(0, png(2, 2), extension: 'png', pixelWidth: 0, pixelHeight: 2), throwsArgumentError);
  });

  test('two pictures get their own parts, and the other pictures are untouched', () {
    final d = openSample();
    d.insertPictureAfter(0, png(10, 10), extension: 'png', pixelWidth: 10, pixelHeight: 10);
    d.insertPictureAfter(0, png(20, 20), extension: 'png', pixelWidth: 20, pixelHeight: 20);
    final bytes = d.save();
    expect(hasPart(bytes, 'word/media/dlpic1.png') && hasPart(bytes, 'word/media/dlpic2.png'), isTrue);
    final ids = RegExp(r'<wp:docPr id="(\d+)"').allMatches(part(bytes, 'word/document.xml')).map((m) => m.group(1)).toList();
    expect(ids.toSet().length, ids.length, reason: 'every picture has its own id');
  });

  test('the header and footer are read, set, saved and changed again without adding parts twice', () {
    final d = openSample();
    final start = d.headerFooter();
    expect((start.header, start.footer, start.pageNumbers), ('', '', false));

    d.setHeaderFooter(header: 'ACME Ltd', footer: 'Confidential\nDo not copy', pageNumbers: true);
    var now = d.headerFooter();
    expect((now.header, now.footer, now.pageNumbers), ('ACME Ltd', 'Confidential\nDo not copy', true));

    final bytes = d.save();
    expect(part(bytes, 'word/header1.xml'), contains('ACME Ltd'));
    final footer = part(bytes, 'word/footer1.xml');
    expect(footer, contains('Confidential'));
    expect(footer, contains('PAGE'));
    expect(footer, contains('NUMPAGES'));
    expect(part(bytes, '[Content_Types].xml'), allOf(contains('/word/header1.xml'), contains('/word/footer1.xml')));
    expect(part(bytes, 'word/_rels/document.xml.rels'), allOf(contains('Target="header1.xml"'), contains('Target="footer1.xml"')));
    final body = part(bytes, 'word/document.xml');
    expect(body, contains('w:headerReference'));
    expect(body, contains('w:footerReference'));

    final again = DocxDocument.open(bytes);
    now = again.headerFooter();
    expect((now.header, now.footer, now.pageNumbers), ('ACME Ltd', 'Confidential\nDo not copy', true));

    again.setHeaderFooter(header: 'New name', footer: '', pageNumbers: false);
    final changed = again.save();
    expect(part(changed, 'word/header1.xml'), contains('New name'));
    expect(part(changed, 'word/header1.xml'), isNot(contains('ACME')));
    expect(hasPart(changed, 'word/header2.xml'), isFalse, reason: 'the same part is changed, not a second one added');
    expect(RegExp('headerReference').allMatches(part(changed, 'word/document.xml')), hasLength(1));
    now = DocxDocument.open(changed).headerFooter();
    expect((now.header, now.footer, now.pageNumbers), ('New name', '', false));
  });

  test('text with markup characters stays text in the header', () {
    final d = openSample();
    d.setHeaderFooter(header: 'Q&A <draft> "v2"', footer: '', pageNumbers: false);
    expect(DocxDocument.open(d.save()).headerFooter().header, 'Q&A <draft> "v2"');
  });

  test('an empty header and footer on a document that has none add nothing', () {
    final d = openSample();
    d.setHeaderFooter(header: '', footer: '', pageNumbers: false);
    final bytes = d.save();
    expect(hasPart(bytes, 'word/header1.xml') || hasPart(bytes, 'word/footer1.xml'), isFalse);
  });

  test('files that are not Word documents are refused', () {
    expect(() => DocxDocument.open(File('test/fixtures/office/basic.xlsx').readAsBytesSync()), throwsA(isA<DocxFormatException>()));
    expect(() => DocxDocument.open(File('test/fixtures/office/search_text.pdf').readAsBytesSync()), throwsA(isA<DocxFormatException>()));
  });
}

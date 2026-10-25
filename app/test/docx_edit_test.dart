import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/text_edit/docx/docx_document.dart';

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

  test('files that are not Word documents are refused', () {
    expect(() => DocxDocument.open(File('test/fixtures/office/basic.xlsx').readAsBytesSync()), throwsA(isA<DocxFormatException>()));
    expect(() => DocxDocument.open(File('test/fixtures/office/search_text.pdf').readAsBytesSync()), throwsA(isA<DocxFormatException>()));
  });
}

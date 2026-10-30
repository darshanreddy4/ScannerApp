import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/slides/data/pptx_package.dart';
import 'package:doculoom/features/office/slides/data/slide_reader.dart';
import 'package:doculoom/features/office/slides/domain/slide_model.dart';

Future<PptxDeck> open(String name) async => PptxDeck.open(File('test/fixtures/office/$name').readAsBytesSync());

void main() {
  test('reads size, slides and inherited placeholders', () async {
    final deck = await open('deck.pptx');
    expect(deck.slides, hasLength(3));
    expect(deck.width, closeTo(12191695, 5000));
    final reader = SlideReader(deck);
    final s1 = reader.read(deck.slides[0]);
    final title = s1.shapes.firstWhere((s) => s.placeholder && s.plainText == 'Quarterly Review');
    expect(title.frame.w, greaterThan(0), reason: 'the title takes its position from the layout');
    expect(title.paragraphs.first.runs.first.sizePt, greaterThan(30), reason: 'and its size from the master title style');
    expect(title.paragraphs.first.align, 'ctr');
    final sub = s1.shapes.firstWhere((s) => s.plainText.startsWith('Sales'));
    expect(sub.plainText, 'Sales & <Marketing> 2024');
    expect(s1.background.kind, FillKind.solid);
    expect(s1.background.color, 0xFFFFFFFF);
  });

  test('bullets and levels come from the master body style', () async {
    final deck = await open('deck.pptx');
    final s2 = SlideReader(deck).read(deck.slides[1]);
    final body = s2.shapes.firstWhere((s) => s.plainText.contains('Revenue'));
    expect(body.paragraphs.map((p) => p.text), ['Revenue up 12%', 'New markets', 'Third point']);
    expect(body.paragraphs.every((p) => p.bullet != null), isTrue);
    expect(body.paragraphs[1].level, 1);
    expect(body.paragraphs[1].marL, greaterThan(body.paragraphs[0].marL));
    expect(body.paragraphs[1].runs.first.sizePt, lessThan(body.paragraphs[0].runs.first.sizePt));
  });

  test('reads styled text, fills, pictures, tables, groups and the slide background', () async {
    final deck = await open('deck.pptx');
    final s3 = SlideReader(deck).read(deck.slides[2]);
    expect(s3.background.color, 0xFFF1F5F9);
    final styled = s3.shapes.firstWhere((s) => s.plainText == 'Styled text');
    final run = styled.paragraphs.first.runs.first;
    expect(run.sizePt, 32);
    expect(run.bold, isTrue);
    expect(run.color, 0xFF1D4ED8);
    expect(styled.paragraphs.first.align, 'ctr');
    final box = s3.shapes.firstWhere((s) => s.plainText == 'Box');
    expect(box.geometry, 'roundRect');
    expect(box.fill.color, 0xFFFFC107);
    expect(box.paragraphs.first.runs.first.color, 0xFFFFFFFF, reason: 'shape text takes the colour of its style reference');
    final oval = s3.shapes.firstWhere((s) => s.geometry == 'ellipse');
    expect(oval.fill.color, 0xFF43A047);
    final pic = s3.shapes.firstWhere((s) => s.kind == ShapeKind.picture);
    expect(pic.media, 'ppt/media/image1.png');
    expect(deck.files.containsKey(pic.media), isTrue);
    final table = s3.shapes.firstWhere((s) => s.kind == ShapeKind.table).table!;
    expect(table.rows, hasLength(3));
    expect(table.rows[1][2].paragraphs.first.text, 'R1C2');
    expect(table.colWidths, hasLength(3));
    final grouped = s3.shapes.where((s) => !s.editable).toList();
    expect(grouped, hasLength(1));
    expect(grouped.single.fill.color, 0xFF8E24AA);
  });

  test('rejects files that are not presentations', () async {
    expect(() => PptxDeck.open(File('test/fixtures/office/basic.xlsx').readAsBytesSync()), throwsA(isA<PptxFormatException>()));
    expect(() => PptxDeck.open(File('pubspec.yaml').readAsBytesSync()), throwsA(isA<PptxFormatException>()));
  });
}

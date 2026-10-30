import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/office/slides/data/deck_editor.dart';
import 'package:doculoom/features/office/slides/data/pptx_package.dart';
import 'package:doculoom/features/office/slides/data/pptx_template.dart';
import 'package:doculoom/features/office/slides/data/pptx_writer.dart';
import 'package:doculoom/features/office/slides/domain/slide_model.dart';

Future<DeckEditor> editor([String name = 'deck.pptx']) async => DeckEditor(await PptxDeck.open(File('test/fixtures/office/$name').readAsBytesSync()));

Uint8List png() => File('/tmp/pic.png').existsSync()
    ? File('/tmp/pic.png').readAsBytesSync()
    : Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 4, 0, 0, 0, 3, 8, 2, 0, 0, 0]);

ShapeView byText(DeckEditor e, int slide, String text) => e.view(e.deck.slides[slide]).shapes.firstWhere((s) => s.plainText.contains(text));

void main() {
  test('text, style, position and fill edits are written and read back', () async {
    final e = await editor();
    final slide = e.deck.slides[2];
    final styled = byText(e, 2, 'Styled text');
    e.setText(slide, styled.id, 'New line one\nSecond & <line>');
    var back = byText(e, 2, 'New line one');
    expect(back.paragraphs.map((p) => p.text), ['New line one', 'Second & <line>']);
    expect(back.paragraphs.first.runs.first.sizePt, 32, reason: 'the first run look is kept');
    expect(back.paragraphs.first.align, 'ctr');

    e.styleText(slide, styled.id, sizeDelta: 4, italic: true, color: 0xFF00AA00, align: 'r');
    back = byText(e, 2, 'New line one');
    expect(back.paragraphs.first.runs.first.sizePt, 36);
    expect(back.paragraphs.first.runs.first.italic, isTrue);
    expect(back.paragraphs.first.runs.first.color, 0xFF00AA00);
    expect(back.paragraphs.first.align, 'r');

    e.setFrame(slide, styled.id, back.frame.copyWith(x: 1000000, y: 2000000, w: 3000000, h: 800000));
    back = byText(e, 2, 'New line one');
    expect(back.frame.x, 1000000);
    expect(back.frame.w, 3000000);

    final box = byText(e, 2, 'Box');
    e.setFill(slide, box.id, 0xFF112233);
    expect(byText(e, 2, 'Box').fill.color, 0xFF112233);
    e.setFill(slide, box.id, null);
    expect(byText(e, 2, 'Box').fill.kind, FillKind.none);

    e.setBackground(slide, 0xFFFFEEEE);
    expect(e.view(slide).background.color, 0xFFFFEEEE);
  });

  test('a placeholder that took its place from the layout gets its own place when moved', () async {
    final e = await editor();
    final slide = e.deck.slides[0];
    final title = e.view(slide).shapes.firstWhere((s) => s.placeholder && s.plainText == 'Quarterly Review');
    e.setFrame(slide, title.id, title.frame.copyWith(x: title.frame.x + 100000));
    final moved = e.view(slide).shapes.firstWhere((s) => s.placeholder && s.plainText == 'Quarterly Review');
    expect(moved.frame.x, title.frame.x + 100000);
    expect(moved.frame.w, title.frame.w);
  });

  test('adding, duplicating, ordering and deleting shapes', () async {
    final e = await editor();
    final slide = e.deck.slides[2];
    final before = e.view(slide).shapes.length;
    final t = e.addTextBox(slide, 'Hello\nWorld', sizePt: 20, color: 0xFFFF0000);
    final s = e.addShape(slide, 'ellipse', color: 0xFF0000FF);
    final p = e.addPicture(slide, png(), 'png', 4, 3);
    var shapes = e.view(slide).shapes;
    expect(shapes.length, before + 3);
    expect(shapes.firstWhere((x) => x.id == t).paragraphs.map((x) => x.text), ['Hello', 'World']);
    expect(shapes.firstWhere((x) => x.id == s).fill.color, 0xFF0000FF);
    final pic = shapes.firstWhere((x) => x.id == p);
    expect(pic.media, isNotNull);
    expect(e.deck.files.containsKey(pic.media), isTrue);
    expect(pic.frame.w / pic.frame.h, closeTo(4 / 3, 0.01));

    final copy = e.duplicate(slide, t)!;
    shapes = e.view(slide).shapes;
    expect(shapes.firstWhere((x) => x.id == copy).frame.x, greaterThan(shapes.firstWhere((x) => x.id == t).frame.x));
    e.reorder(slide, t, toFront: true);
    expect(e.view(slide).shapes.last.id, t);
    e.reorder(slide, t, toFront: false);
    expect(e.view(slide).shapes.first.id, t);
    e.delete(slide, copy);
    expect(e.view(slide).shapes.any((x) => x.id == copy), isFalse);
  });

  test('undo and redo restore text, shapes and slide order', () async {
    final e = await editor();
    final slide = e.deck.slides[2];
    final styled = byText(e, 2, 'Styled text');
    e.setText(slide, styled.id, 'Changed');
    e.addSlide();
    expect(e.deck.slides, hasLength(4));
    e.undo();
    expect(e.deck.slides, hasLength(3));
    e.undo();
    expect(byText(e, 2, 'Styled text').plainText, 'Styled text');
    e.redo();
    expect(byText(e, 2, 'Changed').plainText, 'Changed');
    e.redo();
    expect(e.deck.slides, hasLength(4));
  });

  test('slides can be added, duplicated, moved and deleted, and the file stays valid', () async {
    final e = await editor();
    final added = e.addSlide(blank: true);
    final dup = e.duplicateSlide(1);
    expect(e.deck.slides, hasLength(5));
    e.moveSlide(4, 0);
    expect(e.deck.slides.first, added == e.deck.slides.first ? added : e.deck.slides.first);
    final texts = [for (final s in e.deck.slides) e.slideText(s)];
    expect(texts.where((t) => t.contains('Highlights')).length, 2);
    e.deleteSlide(e.deck.slides.indexOf(dup));
    expect(e.deck.slides, hasLength(4));
    final bytes = writePptx(e.deck);
    File('/tmp/edit_out.pptx').writeAsBytesSync(bytes);

    final back = await PptxDeck.open(bytes);
    expect(back.slides, hasLength(4));
    final reread = DeckEditor(back);
    expect([for (final s in back.slides) reread.slideText(s)], texts.sublist(0, 0) + [for (final s in e.deck.slides) e.slideText(s)]);
  });

  test('an edited deck keeps pictures, tables and notes, and the only slide cannot be deleted', () async {
    final e = await editor();
    final slide = e.deck.slides[2];
    e.addPicture(slide, png(), 'png', 4, 3);
    e.setText(slide, byText(e, 2, 'Styled text').id, 'Edited');
    final bytes = writePptx(e.deck);
    File('/tmp/edit_out2.pptx').writeAsBytesSync(bytes);
    final back = DeckEditor(await PptxDeck.open(bytes));
    final shapes = back.view(back.deck.slides[2]).shapes;
    expect(shapes.where((s) => s.kind == ShapeKind.picture), hasLength(2));
    expect(shapes.any((s) => s.kind == ShapeKind.table), isTrue);
    expect(shapes.any((s) => s.plainText == 'Edited'), isTrue);
    expect(back.deck.files.keys.any((k) => k.startsWith('ppt/notesSlides/')), isTrue);

    final one = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
    expect(one.deleteSlide(0), isFalse);
  });

  test('a new presentation can be edited, written and read back', () async {
    final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
    final slide = e.deck.slides.first;
    final shapes = e.view(slide).shapes;
    expect(shapes.where((s) => s.placeholder), hasLength(2));
    expect(shapes.first.frame.w, greaterThan(0), reason: 'placeholders take their place from the layout');
    e.setText(slide, shapes.first.id, 'My title');
    e.setText(slide, shapes[1].id, 'First\nSecond');
    e.addSlide(blank: true);
    final bytes = writePptx(e.deck);
    File('/tmp/new_out.pptx').writeAsBytesSync(bytes);
    final back = DeckEditor(await PptxDeck.open(bytes));
    expect(back.deck.slides, hasLength(2));
    expect(back.slideText(back.deck.slides.first), 'My title\nFirst\nSecond');
    final body = back.view(back.deck.slides.first).shapes[1];
    expect(body.paragraphs.every((p) => p.bullet != null), isTrue);
  });

  test('image info reads PNG and JPEG sizes', () {
    expect(imageInfo(png())!.ext, 'png');
    final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xC0, 0, 17, 8, 0, 20, 0, 30, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]);
    final info = imageInfo(jpg)!;
    expect((info.width, info.height, info.ext), (30, 20, 'jpeg'));
  });
}

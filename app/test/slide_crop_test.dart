import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';
import 'package:doculoom/features/office/slides/data/deck_editor.dart';
import 'package:doculoom/features/office/slides/data/pptx_package.dart';
import 'package:doculoom/features/office/slides/data/pptx_template.dart';
import 'package:doculoom/features/office/slides/data/pptx_writer.dart';

(DeckEditor, String) deckWithPicture() {
  final e = DeckEditor(PptxDeck.fromFiles(newPresentationFiles()));
  final png = img.encodePng(img.Image(width: 400, height: 200));
  final id = e.addPicture(e.deck.slides.first, png, 'png', 400, 200, areaW: 4000000, areaH: 4000000);
  return (e, id);
}

void main() {
  test('cropping writes the cut edges, shrinks the frame and keeps the picture at the same scale', () {
    final (e, id) = deckWithPicture();
    final s = e.deck.slides.first;
    final before = e.shapeOf(s, id)!.frame;
    e.setPictureCrop(s, id, [0.25, 0, 0.25, 0.5]);
    final after = e.shapeOf(s, id)!;
    expect(after.crop, [0.25, 0.0, 0.25, 0.5]);
    expect(after.frame.w, closeTo(before.w * 0.5, 1));
    expect(after.frame.h, closeTo(before.h * 0.5, 1));
    expect(after.frame.x, closeTo(before.x + before.w * 0.25, 1));
    expect(after.frame.y, closeTo(before.y, 1));
    expect(s.doc.toXmlString(), contains('<a:srcRect l="25000" r="25000" b="50000"/>'));
  });

  test('a second crop changes from the first one, and a reset gives back the original frame', () {
    final (e, id) = deckWithPicture();
    final s = e.deck.slides.first;
    final original = e.shapeOf(s, id)!.frame;
    e.setPictureCrop(s, id, [0.1, 0.1, 0.1, 0.1]);
    e.setPictureCrop(s, id, [0.2, 0.1, 0, 0.3]);
    final f = e.shapeOf(s, id)!.frame;
    expect(f.w, closeTo(original.w * 0.8, 1));
    expect(f.h, closeTo(original.h * 0.6, 1));
    e.setPictureCrop(s, id, [0, 0, 0, 0]);
    final back = e.shapeOf(s, id)!;
    expect(back.crop, isNull);
    expect(back.frame.w, closeTo(original.w, 1));
    expect(back.frame.h, closeTo(original.h, 1));
    expect(back.frame.x, closeTo(original.x, 1));
    expect(back.frame.y, closeTo(original.y, 1));
    expect(s.doc.toXmlString(), isNot(contains('srcRect')));
  });

  test('the crop goes right after the picture and before the stretch, and cannot cut away the whole picture', () {
    final (e, id) = deckWithPicture();
    final s = e.deck.slides.first;
    e.setPictureCrop(s, id, [0.8, 0.9, 0.8, 0.9]);
    final names = s.doc.rootElement.descendantElements.firstWhere((x) => x.name.local == 'blipFill').childElements.map((c) => c.name.local).toList();
    expect(names, ['blip', 'srcRect', 'stretch']);
    final c = e.shapeOf(s, id)!.crop!;
    expect(c[0] + c[2], lessThanOrEqualTo(0.95 + 1e-9));
    expect(c[1] + c[3], lessThanOrEqualTo(0.95 + 1e-9));
    expect(e.shapeOf(s, id)!.frame.w, greaterThan(0));
  });

  test('a picture can be cut to an oval or rounded shape, and undo restores it all', () {
    final (e, id) = deckWithPicture();
    final s = e.deck.slides.first;
    final before = e.shapeOf(s, id)!.frame;
    e.setPictureCrop(s, id, [0.1, 0.1, 0.1, 0.1], geometry: 'ellipse');
    expect(e.shapeOf(s, id)!.geometry, 'ellipse');
    e.setPictureCrop(s, id, [0.1, 0.1, 0.1, 0.1], geometry: 'star5');
    expect(e.shapeOf(s, id)!.geometry, 'ellipse', reason: 'only the offered shapes are accepted');
    e.undo();
    e.undo();
    final back = e.shapeOf(s, id)!;
    expect(back.geometry, 'rect');
    expect(back.crop, isNull);
    expect(back.frame.w, closeTo(before.w, 1));
  });

  test('the crop survives saving and opening again', () async {
    final (e, id) = deckWithPicture();
    final s = e.deck.slides.first;
    e.setPictureCrop(s, id, [0.2, 0, 0, 0]);
    final bytes = writePptx(e.deck);
    final xml = utf8.decode(ZipDecoder().decodeBytes(bytes).findFile('ppt/slides/slide1.xml')!.readBytes()!);
    expect(xml, contains('<a:srcRect l="20000"/>'));
    final again = DeckEditor(await PptxDeck.open(bytes));
    final shape = again.view(again.deck.slides.first).shapes.firstWhere((x) => x.media != null);
    expect(shape.crop, [0.2, 0.0, 0.0, 0.0]);
  });
}

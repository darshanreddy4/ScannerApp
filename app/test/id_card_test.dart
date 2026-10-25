import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/features/id_card/data/id_card_processor.dart';
import 'package:scanvault/features/id_card/domain/id_card.dart';

void main() {
  group('card sizes', () {
    test('the standard card is 85.6 x 54 mm', () {
      expect(CardSize.idCard.widthMm, 85.6);
      expect(CardSize.idCard.heightMm, 54);
      expect(CardSize.idCard.sizeLabel, '85.6 x 54 mm');
      expect(CardSize.idCard.aspect, closeTo(1.585, 0.001));
    });

    test('custom sizes are limited to something that can be printed', () {
      expect(CardSize.custom(100, 60)!.label, 'Custom');
      expect(CardSize.custom(10, 60), isNull);
      expect(CardSize.custom(100, 400), isNull);
      expect(CardSize.custom(100, 60), CardSize.custom(100, 60));
      expect(CardSize.custom(100, 60), isNot(CardSize.custom(100, 61)));
    });
  });

  group('layout', () {
    test('two cards at real size are centred one above the other', () {
      final l = CardLayout.place(paper: CardPaper.a4, size: CardSize.idCard, count: 2, scale: CardScale.actual);
      expect(l.scale, 1);
      expect(l.shrunk, isFalse);
      expect(l.slots.length, 2);
      expect(l.slots[0].widthMm, 85.6);
      expect(l.slots[0].xMm, closeTo((210 - 85.6) / 2, 0.001));
      expect(l.slots[1].yMm - (l.slots[0].yMm + 54), CardLayout.gapMm);
      final top = l.slots[0].yMm, bottom = 297 - (l.slots[1].yMm + 54);
      expect(top, closeTo(bottom, 0.001), reason: 'block centred vertically');
    });

    test('one card is centred', () {
      final l = CardLayout.place(paper: CardPaper.a4, size: CardSize.idCard, count: 1, scale: CardScale.actual);
      expect(l.slots.single.yMm, closeTo((297 - 54) / 2, 0.001));
    });

    test('fill makes the cards as big as the page allows, never off the paper', () {
      final l = CardLayout.place(paper: CardPaper.a4, size: CardSize.idCard, count: 2, scale: CardScale.fill);
      expect(l.scale, greaterThan(2));
      for (final s in l.slots) {
        expect(s.xMm, greaterThanOrEqualTo(CardLayout.marginMm - 0.001));
        expect(s.xMm + s.widthMm, lessThanOrEqualTo(210 - CardLayout.marginMm + 0.001));
        expect(s.yMm, greaterThanOrEqualTo(CardLayout.marginMm - 0.001));
        expect(s.yMm + s.heightMm, lessThanOrEqualTo(297 - CardLayout.marginMm + 0.001));
      }
    });

    test('a card too big for the paper is made smaller and flagged', () {
      final l = CardLayout.place(paper: CardPaper.a4, size: CardSize.custom(250, 150)!, count: 2, scale: CardScale.actual);
      expect(l.shrunk, isTrue);
      expect(l.scale, lessThan(1));
      expect(l.slots.last.yMm + l.slots.last.heightMm, lessThanOrEqualTo(297 - CardLayout.marginMm + 0.001));
    });

    test('a passport page and an A6 card fit twice at real size on A4', () {
      for (final size in [CardSize.passportPage, CardSize.a6]) {
        final l = CardLayout.place(paper: CardPaper.a4, size: size, count: 2, scale: CardScale.actual);
        expect(l.shrunk, isFalse, reason: size.label);
        expect(l.scale, 1);
      }
    });

    test('letter paper is a different size', () {
      final l = CardLayout.place(paper: CardPaper.letter, size: CardSize.idCard, count: 1, scale: CardScale.actual);
      expect(l.paperWidthMm, 215.9);
      expect(l.paperHeightMm, 279.4);
    });

    test('options compare by value', () {
      expect(const IdCardOptions(), const IdCardOptions());
      expect(const IdCardOptions().copyWith(blackAndWhite: true), isNot(const IdCardOptions()));
    });
  });

  group('sheet', () {
    late Directory dir;
    late String front, back;
    const maker = IdCardProcessor();

    setUp(() {
      dir = Directory.systemTemp.createTempSync('sv_card');
      String make(String name, img.ColorRgb8 color) {
        final image = img.Image(width: 1600, height: 1000, numChannels: 3);
        img.fill(image, color: color);
        final path = p.join(dir.path, name);
        File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
        return path;
      }

      front = make('front.jpg', img.ColorRgb8(220, 40, 40));
      back = make('back.jpg', img.ColorRgb8(40, 60, 220));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    CardCrop crop(String path) => CardCrop(path: path, left: 0, top: 0, width: 1600, height: 1000);

    test('puts both sides on an A4 page at 300 dpi', () async {
      final r = (await maker.sheet(sides: [crop(front), crop(back)], options: const IdCardOptions(), outputBase: p.join(dir.path, 'sheet'))).valueOrNull!;
      expect(r.cards, 2);
      expect(r.scale, 1);
      final page = img.decodeJpg(File(r.jpgPath).readAsBytesSync())!;
      expect((page.width, page.height), (2480, 3508));
      final layout = CardLayout.place(paper: CardPaper.a4, size: CardSize.idCard, count: 2, scale: CardScale.actual);
      int px(double mm) => (mm / 25.4 * 300).round();
      final a = page.getPixel(px(layout.slots[0].xMm) + 200, px(layout.slots[0].yMm) + 200);
      final b = page.getPixel(px(layout.slots[1].xMm) + 200, px(layout.slots[1].yMm) + 200);
      expect(a.r, greaterThan(180), reason: 'front is red');
      expect(a.b, lessThan(90));
      expect(b.b, greaterThan(180), reason: 'back is blue');
      expect(page.getPixel(100, 100).r, greaterThan(250), reason: 'paper is white');
    });

    test('the card is printed at its real size', () async {
      final r = (await maker.sheet(sides: [crop(front)], options: const IdCardOptions(border: false), outputBase: p.join(dir.path, 'one'))).valueOrNull!;
      final page = img.decodeJpg(File(r.jpgPath).readAsBytesSync())!;
      // Count the coloured columns along the middle row: 85.6 mm at 300 dpi is about 1011 px.
      final y = page.height ~/ 2;
      var coloured = 0;
      for (var x = 0; x < page.width; x++) {
        final px = page.getPixel(x, y);
        if (px.g < 200) coloured++;
      }
      expect(coloured, closeTo(1011, 8));
    });

    test('the PDF page is exactly the paper size', () async {
      final r = (await maker.sheet(
        sides: [crop(front), crop(back)],
        options: const IdCardOptions(paper: CardPaper.letter),
        outputBase: p.join(dir.path, 'letter'),
      )).valueOrNull!;
      final text = String.fromCharCodes(File(r.pdfPath).readAsBytesSync());
      final box = RegExp(r'/MediaBox\s*\[([^\]]*)\]').firstMatch(text)!.group(1)!.trim().split(RegExp(r'\s+')).map(double.parse).toList();
      expect(box[2], closeTo(215.9 / 25.4 * 72, 0.1));
      expect(box[3], closeTo(279.4 / 25.4 * 72, 0.1));
    });

    test('black and white removes colour', () async {
      final r = (await maker.sheet(
        sides: [crop(front)],
        options: const IdCardOptions(blackAndWhite: true, border: false),
        outputBase: p.join(dir.path, 'bw'),
      )).valueOrNull!;
      final page = img.decodeJpg(File(r.jpgPath).readAsBytesSync())!;
      final px = page.getPixel(page.width ~/ 2, page.height ~/ 2);
      expect((px.r - px.b).abs(), lessThan(8));
      expect(px.r, lessThan(200));
    });

    test('the border draws a line around each card', () async {
      final withBorder = (await maker.sheet(sides: [crop(front)], options: const IdCardOptions(), outputBase: p.join(dir.path, 'b1'))).valueOrNull!;
      final without = (await maker.sheet(sides: [crop(front)], options: const IdCardOptions(border: false), outputBase: p.join(dir.path, 'b2'))).valueOrNull!;
      final a = img.decodeJpg(File(withBorder.jpgPath).readAsBytesSync())!;
      final b = img.decodeJpg(File(without.jpgPath).readAsBytesSync())!;
      final layout = CardLayout.place(paper: CardPaper.a4, size: CardSize.idCard, count: 1, scale: CardScale.actual);
      final x = (layout.slots.first.xMm / 25.4 * 300).round();
      final y = a.height ~/ 2;
      // Just outside the card edge: grey with a border, white without.
      expect(a.getPixel(x - 1, y).r, lessThan(220));
      expect(b.getPixel(x - 1, y).r, greaterThan(245));
    });

    test('only the chosen part of the photo is used', () async {
      final image = img.Image(width: 1600, height: 1000, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(image, x1: 800, y1: 0, x2: 1600, y2: 1000, color: img.ColorRgb8(0, 0, 0));
      final path = p.join(dir.path, 'half.jpg');
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 98));
      final right = CardCrop(path: path, left: 800, top: 0, width: 800, height: 504);
      final r = (await maker.sheet(sides: [right], options: const IdCardOptions(border: false), outputBase: p.join(dir.path, 'crop'))).valueOrNull!;
      final page = img.decodeJpg(File(r.jpgPath).readAsBytesSync())!;
      final px = page.getPixel(page.width ~/ 2, page.height ~/ 2);
      expect(px.r, lessThan(30));
    });

    test('a damaged photo or no photo gives a clear failure', () async {
      final bad = File(p.join(dir.path, 'bad.jpg'))..writeAsBytesSync([1, 2, 3]);
      final r = await maker.sheet(sides: [crop(bad.path)], options: const IdCardOptions(), outputBase: p.join(dir.path, 'x'));
      expect(r.failureOrNull!.message, contains('damaged'));
      final none = await maker.sheet(sides: const [], options: const IdCardOptions(), outputBase: p.join(dir.path, 'y'));
      expect(none.failureOrNull!.message, contains('front'));
    });

    test('preparing a photo applies its rotation and limits its size', () async {
      final big = img.Image(width: 4000, height: 2000, numChannels: 3);
      img.fill(big, color: img.ColorRgb8(10, 10, 10));
      final src = p.join(dir.path, 'big.jpg');
      File(src).writeAsBytesSync(img.encodeJpg(big, quality: 80));
      final w = (await maker.prepare(sourcePath: src, outputPath: p.join(dir.path, 'w.jpg'))).valueOrNull!;
      expect(w.width, 3000);
      final turned = (await maker.prepare(sourcePath: src, outputPath: p.join(dir.path, 'w2.jpg'), rotateRight: true)).valueOrNull!;
      expect(turned.height, 3000);
      expect(turned.width, 1500);
    });
  });
}

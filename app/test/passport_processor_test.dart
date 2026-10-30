import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/photo_tools/data/background_cleaner.dart';
import 'package:doculoom/features/photo_tools/data/passport_processor.dart';
import 'package:doculoom/features/photo_tools/domain/passport_maker.dart';
import 'package:doculoom/features/photo_tools/domain/photo_compressor.dart';
import 'package:doculoom/features/photo_tools/domain/photo_specs.dart';

/// A head-and-shoulders stand-in: a grey wall with a dark head and shoulders in the middle.
img.Image _portrait(int w, int h, {int wall = 150, bool gradient = false}) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  for (final px in image) {
    final shade = gradient ? wall - (px.x * 25 ~/ w) : wall;
    px
      ..r = shade
      ..g = shade
      ..b = shade;
  }
  // Head.
  img.fillCircle(image, x: w ~/ 2, y: (h * 0.4).round(), radius: (w * 0.22).round(), color: img.ColorRgb8(60, 40, 30));
  // Shoulders reaching the bottom edge.
  img.fillRect(image, x1: (w * 0.15).round(), y1: (h * 0.7).round(), x2: (w * 0.85).round(), y2: h, color: img.ColorRgb8(30, 30, 60));
  return image;
}

void main() {
  late Directory dir;
  const maker = PassportProcessor();

  setUp(() => dir = Directory.systemTemp.createTempSync('sv_passport'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) => (File(p.join(dir.path, name))..writeAsBytesSync(bytes)).path;
  String out(String name) => p.join(dir.path, name);

  group('prepare', () {
    test('applies the camera rotation flag so the picture is upright', () async {
      final photo = img.Image(width: 300, height: 200)..exif.imageIfd.orientation = 6;
      final r = (await maker.prepare(sourcePath: write('a.jpg', img.encodeJpg(photo)), outputPath: out('w.jpg'))).valueOrNull!;
      expect((r.width, r.height), (200, 300));
      final saved = img.decodeJpg(File(r.path).readAsBytesSync())!;
      expect((saved.width, saved.height), (200, 300));
    });

    test('rotates a quarter turn on request', () async {
      final r = (await maker.prepare(
        sourcePath: write('a.png', img.encodePng(img.Image(width: 300, height: 200))),
        outputPath: out('w.jpg'),
        rotateRight: true,
      )).valueOrNull!;
      expect((r.width, r.height), (200, 300));
    });

    test('big photos are limited so editing stays fast, and transparency becomes white', () async {
      final big = img.Image(width: 4500, height: 2000, numChannels: 4);
      img.fill(big, color: img.ColorRgba8(0, 0, 0, 0));
      final r = (await maker.prepare(sourcePath: write('b.png', img.encodePng(big)), outputPath: out('w.jpg'))).valueOrNull!;
      expect(r.width, 3000);
      expect(r.height, 1333);
      final px = img.decodeJpg(File(r.path).readAsBytesSync())!.getPixel(10, 10);
      expect(px.r, greaterThan(240));
    });

    test('a file that is not a picture gives a readable failure', () async {
      final result = await maker.prepare(sourcePath: write('c.jpg', List.filled(50, 3)), outputPath: out('w.jpg'));
      expect(result.failureOrNull, isA<ExportFailure>());
    });
  });

  group('render', () {
    String quadrants() {
      final image = img.Image(width: 400, height: 400, numChannels: 3);
      for (final px in image) {
        final left = px.x < 200, top = px.y < 200;
        final c = left && top ? [255, 0, 0] : (!left && top ? [0, 255, 0] : (left ? [0, 0, 255] : [255, 255, 0]));
        px
          ..r = c[0]
          ..g = c[1]
          ..b = c[2];
      }
      return write('q.png', img.encodePng(image));
    }

    test('keeps exactly the chosen part and gives the exact pixel size', () async {
      final r = (await maker.render(
        RenderRequest(sourcePath: quadrants(), left: 0, top: 0, width: 200, height: 200, outWidth: 413, outHeight: 531, outputPath: out('o.jpg')),
      )).valueOrNull!;
      expect((r.width, r.height), (413, 531));
      expect(File(r.path).lengthSync(), r.bytes);
      final result = img.decodeJpg(File(r.path).readAsBytesSync())!;
      final centre = result.getPixel(200, 260);
      expect(centre.r, greaterThan(220));
      expect(centre.g, lessThan(40), reason: 'only the red quadrant is inside the crop');
      expect(centre.b, lessThan(40));
    });

    test('a crop that touches the edge of the photo is allowed', () async {
      final r = (await maker.render(
        RenderRequest(sourcePath: quadrants(), left: 200, top: 200, width: 200.4, height: 200.4, outWidth: 100, outHeight: 100, outputPath: out('e.jpg')),
      )).valueOrNull!;
      final px = img.decodeJpg(File(r.path).readAsBytesSync())!.getPixel(50, 50);
      expect(px.r, greaterThan(220));
      expect(px.g, greaterThan(220));
      expect(px.b, lessThan(60), reason: 'yellow quadrant');
    });

    test('PNG output when asked', () async {
      final r = (await maker.render(
        RenderRequest(
          sourcePath: quadrants(),
          left: 0,
          top: 0,
          width: 400,
          height: 400,
          outWidth: 120,
          outHeight: 120,
          outputPath: out('o.png'),
          format: PhotoFormat.png,
        ),
      )).valueOrNull!;
      expect(img.decodePng(File(r.path).readAsBytesSync()), isNotNull);
    });

    test('replaces the wall with the chosen colour and keeps the person', () async {
      final source = write('p.jpg', img.encodeJpg(_portrait(400, 520), quality: 98));
      final r = (await maker.render(
        RenderRequest(
          sourcePath: source,
          left: 0,
          top: 0,
          width: 400,
          height: 520,
          outWidth: 400,
          outHeight: 520,
          outputPath: out('white.jpg'),
          backgroundArgb: PhotoBackground.white.argb,
        ),
      )).valueOrNull!;
      final result = img.decodeJpg(File(r.path).readAsBytesSync())!;
      for (final (x, y) in [(5, 5), (394, 5), (5, 300), (394, 300), (200, 3)]) {
        final px = result.getPixel(x, y);
        expect(px.r, greaterThan(240), reason: 'wall at $x,$y');
        expect(px.g, greaterThan(240));
        expect(px.b, greaterThan(240));
      }
      final head = result.getPixel(200, 208);
      expect(head.r, lessThan(90), reason: 'the head is not touched');
      final shoulder = result.getPixel(200, 500);
      expect(shoulder.b, lessThan(110), reason: 'shoulders reaching the bottom edge are kept');
    });
  });

  group('background cleaner', () {
    int luma(img.Pixel px) => ((px.r + px.g + px.b) / 3).round();

    test('also cleans a wall that gets darker across the picture', () {
      final cleaned = cleanBackground(_portrait(400, 520, gradient: true), backgroundArgb: PhotoBackground.lightBlue.argb, strength: 60);
      for (final x in [4, 395]) {
        final px = cleaned.getPixel(x, 10);
        expect((px.r.toInt(), px.g.toInt(), px.b.toInt()), (0xB9, 0xD9, 0xEB));
      }
    });

    test('edges are soft, not jagged', () {
      final cleaned = cleanBackground(_portrait(400, 520), backgroundArgb: 0xFFFFFFFF);
      // Walk along a row across the head edge: the brightness steps through in-between values.
      final row = [for (var x = 100; x < 125; x++) luma(cleaned.getPixel(x, 208))];
      expect(row.toSet().length, greaterThan(3));
    });

    test('a busy background is not wiped, and the person stays', () {
      final image = _portrait(400, 520);
      for (var y = 0; y < 520; y += 8) {
        for (var x = 0; x < 400; x += 8) {
          if (((x + y) ~/ 8) % 2 == 0) img.fillRect(image, x1: x, y1: y, x2: x + 4, y2: y + 4, color: img.ColorRgb8(40, 180, 40));
        }
      }
      final cleaned = cleanBackground(image, backgroundArgb: 0xFFFFFFFF, strength: 20);
      expect(luma(cleaned.getPixel(200, 208)), lessThan(90));
    });

    test('a person who does not touch the edges is not erased even if the colours are alike', () {
      final image = img.Image(width: 200, height: 200, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(150, 150, 150));
      // A ring separates a same-grey core from the wall.
      img.fillCircle(image, x: 100, y: 100, radius: 60, color: img.ColorRgb8(20, 20, 20));
      img.fillCircle(image, x: 100, y: 100, radius: 30, color: img.ColorRgb8(150, 150, 150));
      final cleaned = cleanBackground(image, backgroundArgb: 0xFFFFFFFF);
      expect(luma(cleaned.getPixel(100, 100)), lessThan(200), reason: 'the grey core is enclosed by the dark ring');
      expect(luma(cleaned.getPixel(3, 3)), greaterThan(240));
    });
  });

  group('print sheet', () {
    String photo() => write('photo.jpg', img.encodeJpg(_portrait(413, 531)));

    test('makes a 300 dpi JPG and an exact-size PDF with the copies that fit', () async {
      const spec = PhotoSpec(id: 'p', name: 'Passport', widthMm: 35, heightMm: 45);
      final r = (await maker.sheet(photoPath: photo(), spec: spec, paper: SheetPaper.photo4x6, outputBase: out('sheet'))).valueOrNull!;
      expect(r.copies, 6);
      expect((r.columns, r.rows), (2, 3));
      final jpg = img.decodeJpg(File(r.jpgPath).readAsBytesSync())!;
      expect((jpg.width, jpg.height), (1200, 1800), reason: '4 x 6 in at 300 dpi');
      final pdf = File(r.pdfPath).readAsBytesSync();
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      // 101.6 x 152.4 mm is 288 x 432 points.
      final text = String.fromCharCodes(pdf);
      expect(text, contains('288'));
      expect(text, contains('432'));
    });

    test('fewer copies and a photo shows on the paper in the right place', () async {
      const spec = PhotoSpec(id: 'p', name: 'Passport', widthMm: 35, heightMm: 45);
      final r = (await maker.sheet(photoPath: photo(), spec: spec, paper: SheetPaper.a4, copies: 4, outputBase: out('a4'))).valueOrNull!;
      expect(r.copies, 4);
      final jpg = img.decodeJpg(File(r.jpgPath).readAsBytesSync())!;
      expect((jpg.width, jpg.height), (2480, 3508));
      // Paper corners are white, the middle holds a photo (not all white).
      expect(jpg.getPixel(10, 10).r, greaterThan(250));
      var dark = 0;
      for (var y = 1200; y < 2300; y += 20) {
        for (var x = 800; x < 1700; x += 20) {
          if (jpg.getPixel(x, y).r < 100) dark++;
        }
      }
      expect(dark, greaterThan(20));
    });

    test('a photo bigger than the paper is reported, not crashed', () async {
      const spec = PhotoSpec(id: 'p', name: 'Big', widthMm: 300, heightMm: 400);
      final result = await maker.sheet(photoPath: photo(), spec: spec, paper: SheetPaper.a4, outputBase: out('big'));
      expect(result.failureOrNull, isA<ExportFailure>());
    });
  });
}

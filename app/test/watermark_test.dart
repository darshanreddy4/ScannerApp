import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/features/photo_tools/data/watermark_compositor.dart';
import 'package:scanvault/features/photo_tools/data/watermark_processor.dart';
import 'package:scanvault/features/photo_tools/data/watermark_stamp.dart';
import 'package:scanvault/features/photo_tools/domain/photo_compressor.dart';
import 'package:scanvault/features/photo_tools/domain/watermark.dart';

Uint8List _solid(int w, int h, List<int> rgba) {
  final bytes = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    bytes.setRange(i * 4, i * 4 + 4, rgba);
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('sv_wm'));
  tearDown(() => dir.deleteSync(recursive: true));

  String white(String name, int w, int h, {bool png = false}) {
    final image = img.Image(width: w, height: h, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    return (File(p.join(dir.path, name))..writeAsBytesSync(png ? img.encodePng(image) : img.encodeJpg(image, quality: 100))).path;
  }

  group('placement', () {
    List<WatermarkSpot> single(WatermarkPosition pos, {int w = 1000, int h = 800, int sw = 200, int sh = 100}) =>
        WatermarkPlacement.spots(imageWidth: w, imageHeight: h, stampWidth: sw, stampHeight: sh, layout: WatermarkLayout.single, position: pos);

    test('one mark goes to the chosen place, inside a margin', () {
      final margin = (800 * 0.03).round();
      expect(single(WatermarkPosition.topLeft).single.x, margin);
      expect(single(WatermarkPosition.topLeft).single.y, margin);
      final br = single(WatermarkPosition.bottomRight).single;
      expect(br.x + 200, 1000 - margin);
      expect(br.y + 100, 800 - margin);
      final c = single(WatermarkPosition.center).single;
      expect(c.x + 100, closeTo(500, 1));
      expect(c.y + 50, closeTo(400, 1));
    });

    test('all nine places stay inside the picture and are different', () {
      final seen = <String>{};
      for (final pos in WatermarkPosition.values) {
        final s = single(pos).single;
        expect(s.x, greaterThanOrEqualTo(0));
        expect(s.y, greaterThanOrEqualTo(0));
        expect(s.x + 200, lessThanOrEqualTo(1000));
        expect(s.y + 100, lessThanOrEqualTo(800));
        seen.add('${s.x},${s.y}');
      }
      expect(seen, hasLength(9));
    });

    test('a mark bigger than the picture is centred', () {
      final s = single(WatermarkPosition.topLeft, w: 100, h: 100, sw: 300, sh: 200).single;
      expect(s.x, -100);
      expect(s.y, -50);
    });

    test('repeated marks reach every edge, so cropping cannot remove them', () {
      final spots = WatermarkPlacement.spots(
        imageWidth: 1000,
        imageHeight: 800,
        stampWidth: 200,
        stampHeight: 80,
        layout: WatermarkLayout.tiled,
        position: WatermarkPosition.center,
      );
      expect(spots.length, greaterThan(10));
      expect(spots.map((s) => s.x).reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(0));
      expect(spots.map((s) => s.y).reduce((a, b) => a < b ? a : b), lessThanOrEqualTo(0));
      expect(spots.map((s) => s.x + 200).reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(1000));
      // The last row starts inside the picture; the gap below it is less than one row step.
      expect(spots.map((s) => s.y + 80).reduce((a, b) => a > b ? a : b), greaterThan(800 - 176));
    });

    test('rows are staggered and no mark is completely outside', () {
      final spots = WatermarkPlacement.spots(
        imageWidth: 1000,
        imageHeight: 800,
        stampWidth: 200,
        stampHeight: 80,
        layout: WatermarkLayout.tiled,
        position: WatermarkPosition.center,
      );
      final rows = <int, List<int>>{};
      for (final s in spots) {
        rows.putIfAbsent(s.y, () => []).add(s.x);
        expect(s.x + 200, greaterThan(0));
        expect(s.y + 80, greaterThan(0));
        expect(s.x, lessThan(1000));
        expect(s.y, lessThan(800));
      }
      final ys = rows.keys.toList()..sort();
      expect(ys.length, greaterThan(2));
      final first = (rows[ys[0]]!..sort()).first, second = (rows[ys[1]]!..sort()).first;
      expect((first - second) % 300, isNot(0), reason: 'neighbouring rows do not line up');
    });

    test('an empty stamp gives no spots', () {
      expect(
        WatermarkPlacement.spots(
          imageWidth: 100,
          imageHeight: 100,
          stampWidth: 0,
          stampHeight: 10,
          layout: WatermarkLayout.tiled,
          position: WatermarkPosition.center,
        ),
        isEmpty,
      );
    });
  });

  group('wording and profile', () {
    test('placeholders are filled and dangling dashes removed', () {
      final date = DateTime(2026, 3, 7);
      expect(WatermarkPresets.fill('{name} - {date}', name: 'Asha Traders', date: date), 'Asha Traders - 07/03/2026');
      expect(WatermarkPresets.fill('{name} - {date}', date: date), '07/03/2026');
      expect(WatermarkPresets.fill('CONFIDENTIAL', date: date), 'CONFIDENTIAL');
      expect(WatermarkPresets.fill('Only for {purpose}', date: date), 'Only for {purpose}', reason: 'unknown placeholders are left for the person to edit');
    });

    test('style limits are enforced', () {
      const s = WatermarkStyle();
      expect(s.copyWith(opacity: 5).opacity, 1);
      expect(s.copyWith(opacity: 0).opacity, WatermarkStyle.minOpacity);
      expect(s.copyWith(size: 5).size, WatermarkStyle.maxSize);
      expect(s.copyWith(rotation: 200).rotation, 90);
      expect(s.copyWith(text: 'x'), isNot(s));
      expect(s.copyWith(), s);
      expect(const WatermarkStyle(text: '  ').isEmpty, isTrue);
      expect(const WatermarkStyle(text: '', logoPath: '/x.png').isEmpty, isFalse);
      expect(s.copyWith(logoPath: '/a.png').copyWith(logoPath: null).logoPath, isNull);
    });

    test('a business profile becomes lines of text and survives saving', () {
      const profile = BusinessProfile(name: ' Asha Traders ', details: 'GST 27ABCDE1234F1Z5 | 98765 43210', logoPath: '/l.png');
      expect(profile.text, 'Asha Traders\nGST 27ABCDE1234F1Z5 | 98765 43210');
      final again = BusinessProfile.fromJson(profile.toJson());
      expect((again.name, again.details, again.logoPath), (profile.name, profile.details, profile.logoPath));
      expect(const BusinessProfile().isEmpty, isTrue);
      expect(const BusinessProfile(name: 'A').text, 'A');
    });
  });

  group('stamp', () {
    const renderer = WatermarkStampRenderer();

    int maxAlpha(Stamp s) {
      var m = 0;
      for (var i = 3; i < s.rgba.length; i += 4) {
        if (s.rgba[i] > m) m = s.rgba[i];
      }
      return m;
    }

    test('draws the words as transparent pixels with the chosen opacity and colour', () async {
      final stamp = (await renderer.render(
        style: const WatermarkStyle(opacity: 0.5, rotation: 0, color: WatermarkColor.red, bold: false),
        text: 'COPY',
        shortSide: 800,
      ))!;
      expect(stamp.width, greaterThan(20));
      expect(stamp.rgba.length, stamp.width * stamp.height * 4);
      // Where two letters touch, anti-aliasing can add a little, so allow some room above half.
      expect(maxAlpha(stamp), inInclusiveRange(120, 200), reason: 'about half opaque');
      final solid = (await renderer.render(style: const WatermarkStyle(opacity: 1, rotation: 0, bold: false), text: 'COPY', shortSide: 800))!;
      final faint = (await renderer.render(style: const WatermarkStyle(opacity: 0.2, rotation: 0, bold: false), text: 'COPY', shortSide: 800))!;
      expect(maxAlpha(solid), 255);
      expect(maxAlpha(faint), lessThan(maxAlpha(stamp)));
      // The painted pixels are the chosen red.
      for (var i = 0; i < stamp.rgba.length; i += 4) {
        if (stamp.rgba[i + 3] > 200 || stamp.rgba[i + 3] < 100) continue;
        expect(stamp.rgba[i], greaterThan(150));
        expect(stamp.rgba[i + 1], lessThan(80));
        break;
      }
    });

    test('a bigger picture gives a bigger stamp, and rotation makes the box taller', () async {
      const style = WatermarkStyle(rotation: 0);
      final small = (await renderer.render(style: style, text: 'COPY', shortSide: 400))!;
      final big = (await renderer.render(style: style, text: 'COPY', shortSide: 1600))!;
      expect(big.width, greaterThan(small.width * 3));
      final turned = (await renderer.render(style: style.copyWith(rotation: -45), text: 'COPY', shortSide: 1600))!;
      expect(turned.height, greaterThan(big.height * 1.5));
    });

    test('several lines are all drawn', () async {
      const style = WatermarkStyle(rotation: 0);
      final one = (await renderer.render(style: style, text: 'Asha Traders', shortSide: 1000))!;
      final two = (await renderer.render(style: style, text: 'Asha Traders\nGST 27ABCDE', shortSide: 1000))!;
      expect(two.height, greaterThan(one.height * 1.7));
    });

    test('nothing to draw gives no stamp', () async {
      expect(await renderer.render(style: const WatermarkStyle(), text: '   ', shortSide: 800), isNull);
    });

    test('a logo is drawn above the words', () async {
      final logo = img.Image(width: 40, height: 40, numChannels: 4);
      img.fill(logo, color: img.ColorRgba8(0, 200, 0, 255));
      final path = (File(p.join(dir.path, 'logo.png'))..writeAsBytesSync(img.encodePng(logo))).path;
      const style = WatermarkStyle(rotation: 0, opacity: 1);
      final plain = (await renderer.render(style: style, text: 'Shop', shortSide: 1000))!;
      final withLogo = (await renderer.render(
        style: style.copyWith(logoPath: path),
        text: 'Shop',
        shortSide: 1000,
      ))!;
      expect(withLogo.height, greaterThan(plain.height * 1.8));
      var green = 0;
      for (var i = 0; i < withLogo.rgba.length; i += 4) {
        if (withLogo.rgba[i + 1] > 150 && withLogo.rgba[i] < 60 && withLogo.rgba[i + 3] > 200) green++;
      }
      expect(green, greaterThan(500));
      final logoOnly = (await renderer.render(
        style: style.copyWith(logoPath: path),
        text: '',
        shortSide: 1000,
      ))!;
      expect(logoOnly.height, greaterThan(0));
    });
  });

  group('compositor', () {
    test('blends the stamp over the picture by its transparency and leaves the rest alone', () {
      final source = white('a.jpg', 200, 200);
      final out = p.join(dir.path, 'o.png');
      // A 20 x 20 black stamp, half transparent, centred.
      applyStamp(
        sourcePath: source,
        outputPath: out,
        stampRgba: _solid(20, 20, [0, 0, 0, 128]),
        stampWidth: 20,
        stampHeight: 20,
        layout: WatermarkLayout.single,
        position: WatermarkPosition.center,
        format: PhotoFormat.png,
      );
      final result = img.decodePng(File(out).readAsBytesSync())!;
      final inside = result.getPixel(100, 100);
      expect(inside.r, inInclusiveRange(120, 135));
      expect(result.getPixel(5, 5).r, 255);
      expect(result.getPixel(150, 150).r, 255);
    });

    test('a fully opaque stamp replaces the pixels', () {
      final source = white('b.jpg', 100, 100);
      final out = p.join(dir.path, 'o.png');
      applyStamp(
        sourcePath: source,
        outputPath: out,
        stampRgba: _solid(10, 10, [200, 0, 0, 255]),
        stampWidth: 10,
        stampHeight: 10,
        layout: WatermarkLayout.single,
        position: WatermarkPosition.topLeft,
        format: PhotoFormat.png,
      );
      final px = img.decodePng(File(out).readAsBytesSync())!.getPixel(5, 5);
      expect((px.r, px.g, px.b), (200, 0, 0));
    });

    test('repeated marks cover the whole picture including the corners without errors', () {
      final source = white('c.jpg', 300, 200);
      final out = p.join(dir.path, 'o.png');
      applyStamp(
        sourcePath: source,
        outputPath: out,
        stampRgba: _solid(60, 30, [0, 0, 0, 255]),
        stampWidth: 60,
        stampHeight: 30,
        layout: WatermarkLayout.tiled,
        position: WatermarkPosition.center,
        format: PhotoFormat.png,
      );
      final result = img.decodePng(File(out).readAsBytesSync())!;
      var dark = 0;
      for (final (x, y) in [(2, 2), (297, 2), (2, 197), (297, 197), (150, 100)]) {
        if (result.getPixel(x, y).r < 128) dark++;
      }
      expect(dark, greaterThanOrEqualTo(1));
      var darkPixels = 0;
      for (var y = 0; y < 200; y += 4) {
        for (var x = 0; x < 300; x += 4) {
          if (result.getPixel(x, y).r < 128) darkPixels++;
        }
      }
      expect(darkPixels, greaterThan(300), reason: 'many marks, not a single one');
    });

    test('a stamp partly outside the picture is clipped, not an error', () {
      final source = white('d.jpg', 50, 50);
      expect(
        () => applyStamp(
          sourcePath: source,
          outputPath: p.join(dir.path, 'o.jpg'),
          stampRgba: _solid(200, 200, [0, 0, 0, 255]),
          stampWidth: 200,
          stampHeight: 200,
          layout: WatermarkLayout.single,
          position: WatermarkPosition.center,
        ),
        returnsNormally,
      );
    });

    test('keeps the size and the upright view of a camera photo', () {
      final photo = img.Image(width: 300, height: 200, numChannels: 3)..exif.imageIfd.orientation = 6;
      img.fill(photo, color: img.ColorRgb8(255, 255, 255));
      final source = (File(p.join(dir.path, 'e.jpg'))..writeAsBytesSync(img.encodeJpg(photo))).path;
      expect(readPictureSize(source), (width: 200, height: 300));
      final done = applyStamp(
        sourcePath: source,
        outputPath: p.join(dir.path, 'o.jpg'),
        stampRgba: _solid(10, 10, [0, 0, 0, 255]),
        stampWidth: 10,
        stampHeight: 10,
        layout: WatermarkLayout.single,
        position: WatermarkPosition.center,
      );
      expect((done.width, done.height), (200, 300));
    });

    test('a transparent PNG is put on white before marking', () {
      final png = img.Image(width: 40, height: 40, numChannels: 4);
      img.fill(png, color: img.ColorRgba8(0, 0, 0, 0));
      final source = (File(p.join(dir.path, 'f.png'))..writeAsBytesSync(img.encodePng(png))).path;
      final out = p.join(dir.path, 'o.png');
      applyStamp(
        sourcePath: source,
        outputPath: out,
        stampRgba: _solid(2, 2, [0, 0, 0, 255]),
        stampWidth: 2,
        stampHeight: 2,
        layout: WatermarkLayout.single,
        position: WatermarkPosition.topLeft,
        format: PhotoFormat.png,
      );
      expect(img.decodePng(File(out).readAsBytesSync())!.getPixel(30, 30).r, 255);
    });
  });

  group('processor', () {
    WatermarkProcessor processor({List<String> Function()? pages}) =>
        WatermarkProcessor(pdfToImages: (path) async => pages?.call() ?? const [], now: () => DateTime(2026, 3, 7, 10));

    test('marks a photo and names the file after it', () async {
      final source = white('Receipt.jpg', 600, 400);
      final r = await processor().apply(
        inputPath: source,
        style: const WatermarkStyle(text: 'COPY', layout: WatermarkLayout.single, opacity: 1, color: WatermarkColor.black),
        outputDir: p.join(dir.path, 'out'),
      );
      final output = r.valueOrNull!;
      expect(output.mimeType, 'image/jpeg');
      expect(output.name, 'Receipt watermarked.jpg');
      final result = img.decodeJpg(File(output.path).readAsBytesSync())!;
      expect((result.width, result.height), (600, 400));
      var dark = 0;
      for (var y = 0; y < 400; y += 2) {
        for (var x = 0; x < 600; x += 2) {
          if (result.getPixel(x, y).r < 100) dark++;
        }
      }
      expect(dark, greaterThan(100), reason: 'the words are on the picture');
    });

    test('keeps PNG as PNG', () async {
      final r = await processor().apply(
        inputPath: white('a.png', 300, 200, png: true),
        style: const WatermarkStyle(text: 'COPY'),
        outputDir: p.join(dir.path, 'out'),
      );
      expect(r.valueOrNull!.mimeType, 'image/png');
      expect(img.decodePng(File(r.valueOrNull!.path).readAsBytesSync()), isNotNull);
    });

    test('the name and date are filled in', () async {
      final base = white('b.jpg', 600, 400);
      final r1 = await processor().apply(
        inputPath: base,
        style: const WatermarkStyle(text: '{name} - {date}', layout: WatermarkLayout.single),
        outputDir: p.join(dir.path, 'out'),
        businessName: 'Asha Traders',
      );
      expect(r1.isOk, isTrue);
    });

    test('a PDF is marked page by page and rebuilt as one PDF', () async {
      final pages = [white('p0.jpg', 500, 700), white('p1.jpg', 500, 700), white('p2.jpg', 700, 500)];
      final progress = <(int, int)>[];
      final r = await processor(pages: () => pages).apply(
        inputPath: p.join(dir.path, 'file.pdf')..let((f) => File(f).writeAsBytesSync([1])),
        style: const WatermarkStyle(text: 'CONFIDENTIAL'),
        outputDir: p.join(dir.path, 'out'),
        onProgress: (d, t) => progress.add((d, t)),
      );
      final output = r.valueOrNull!;
      expect(output.isPdf, isTrue);
      expect(output.pages, 3);
      expect(output.name, 'file watermarked.pdf');
      expect(progress, [(1, 3), (2, 3), (3, 3)]);
      final bytes = File(output.path).readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(RegExp(r'/Type\s*/Page(?!s)').allMatches(String.fromCharCodes(bytes)).length, 3);
      // The temporary page pictures are removed.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(Directory(p.join(dir.path, 'out')).listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')), isEmpty);
    });

    test('an empty watermark, a missing file and a PDF with no pages give readable failures', () async {
      final source = white('c.jpg', 100, 100);
      final out = p.join(dir.path, 'out');
      final empty = await processor().apply(
        inputPath: source,
        style: const WatermarkStyle(text: ' '),
        outputDir: out,
      );
      expect(empty.failureOrNull!.message, contains('Type the words'));
      final missing = await processor().apply(inputPath: p.join(dir.path, 'nope.jpg'), style: const WatermarkStyle(), outputDir: out);
      expect(missing.failureOrNull, isA<ExportFailure>());
      final pdf = (File(p.join(dir.path, 'e.pdf'))..writeAsBytesSync([1])).path;
      final none = await processor().apply(inputPath: pdf, style: const WatermarkStyle(), outputDir: out);
      expect(none.failureOrNull!.message, contains('Nothing could be read'));
      final broken = (File(p.join(dir.path, 'bad.jpg'))..writeAsBytesSync(List.filled(30, 1))).path;
      final bad = await processor().apply(inputPath: broken, style: const WatermarkStyle(), outputDir: out);
      expect(bad.failureOrNull!.message, contains('could not be added'));
    });
  });
}

extension on String {
  void let(void Function(String) f) => f(this);
}

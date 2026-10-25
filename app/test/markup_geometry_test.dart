import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/features/markup/data/markup_renderer_impl.dart';
import 'package:scanvault/features/markup/domain/markup.dart';
import 'package:scanvault/features/scanner/domain/entities/filter_settings.dart';
import 'package:scanvault/features/scanner/domain/entities/prepared_image.dart';
import 'package:scanvault/features/scanner/domain/repositories/scanner_repository.dart';

const page = Size(1000, 1400);

MarkupStroke stroke(List<Offset> pts, {PenKind kind = PenKind.pen, int color = 0xFFFF0000, double width = 0.01, int id = 1}) =>
    MarkupStroke(id: id, kind: kind, points: pts, color: color, width: width);

class _Scanner implements ScannerRepository {
  var filtered = 0;
  late String Function(String) filterTo;

  @override
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) async {
    filtered++;
    final out = filterTo(imagePath);
    return Ok(ImageFileInfo(path: out, width: 400, height: 300));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  group('hit testing', () {
    test('a stroke is hit near its line and not far from it', () {
      final s = stroke([const Offset(0.1, 0.5), const Offset(0.9, 0.5)]);
      expect(MarkupGeometry.hit(s, const Offset(0.5, 0.5), page), isTrue);
      expect(MarkupGeometry.hit(s, const Offset(0.5, 0.51), page), isTrue, reason: 'within the finger tolerance');
      expect(MarkupGeometry.hit(s, const Offset(0.5, 0.6), page), isFalse);
      expect(MarkupGeometry.hit(s, const Offset(0.95, 0.5), page), isFalse);
    });

    test('a dot is hit around its centre', () {
      final s = stroke([const Offset(0.5, 0.5)]);
      expect(MarkupGeometry.hit(s, const Offset(0.5, 0.5), page), isTrue);
      expect(MarkupGeometry.hit(s, const Offset(0.7, 0.5), page), isFalse);
    });

    test('a rectangle is hit on its edge, and inside only when filled', () {
      const a = Offset(0.2, 0.2), b = Offset(0.8, 0.6);
      const empty = MarkupShape(id: 1, kind: ShapeKind.rectangle, from: a, to: b, color: 0xFF000000, width: 0.005);
      expect(MarkupGeometry.hit(empty, const Offset(0.2, 0.4), page), isTrue);
      expect(MarkupGeometry.hit(empty, const Offset(0.5, 0.4), page), isFalse);
      expect(MarkupGeometry.hit(empty.copyWith(filled: true), const Offset(0.5, 0.4), page), isTrue);
      expect(MarkupGeometry.hit(empty, const Offset(0.95, 0.9), page), isFalse);
    });

    test('a circle is hit on its outline only', () {
      const c = MarkupShape(id: 1, kind: ShapeKind.ellipse, from: Offset(0.2, 0.2), to: Offset(0.8, 0.5), color: 0xFF000000, width: 0.005);
      expect(MarkupGeometry.hit(c, const Offset(0.8, 0.35), page), isTrue);
      expect(MarkupGeometry.hit(c, const Offset(0.5, 0.2), page), isTrue);
      expect(MarkupGeometry.hit(c, const Offset(0.5, 0.35), page), isFalse);
      expect(MarkupGeometry.hit(c.copyWith(filled: true), const Offset(0.5, 0.35), page), isTrue);
    });

    test('an arrow is hit along its shaft', () {
      const a = MarkupShape(id: 1, kind: ShapeKind.arrow, from: Offset(0.1, 0.1), to: Offset(0.9, 0.9), color: 0xFF000000, width: 0.005);
      expect(MarkupGeometry.hit(a, const Offset(0.5, 0.5), page), isTrue);
      expect(MarkupGeometry.hit(a, const Offset(0.9, 0.1), page), isFalse);
    });

    test('a sticker is hit inside its square, also when turned', () {
      const s = MarkupSticker(id: 1, text: 'A', center: Offset(0.5, 0.5), size: 0.1);
      expect(MarkupGeometry.hit(s, const Offset(0.52, 0.5), page), isTrue);
      expect(MarkupGeometry.hit(s, const Offset(0.7, 0.5), page), isFalse);
      final turned = s.copyWith(rotation: 3.14159 / 4);
      expect(MarkupGeometry.hit(turned, const Offset(0.5, 0.5), page), isTrue);
    });
  });

  group('bounds and transforms', () {
    test('bounds cover the whole item including its thickness', () {
      final s = stroke([const Offset(0.2, 0.3), const Offset(0.6, 0.4)], width: 0.02);
      final b = MarkupGeometry.bounds(s, page);
      expect(b.left, closeTo(200 - 10, 0.01));
      expect(b.right, closeTo(600 + 10, 0.01));
      expect(b.top, closeTo(420 - 10, 0.01));
    });

    test('moving shifts every point', () {
      final s = stroke([const Offset(0.2, 0.2), const Offset(0.4, 0.3)]);
      final m = MarkupGeometry.transform(s, page, delta: const Offset(0.1, -0.05)) as MarkupStroke;
      expect(m.points.first.dx, closeTo(0.3, 1e-9));
      expect(m.points.first.dy, closeTo(0.15, 1e-9));
      expect(m.points.last.dx, closeTo(0.5, 1e-9));
    });

    test('scaling grows the item around its middle and thickens the line', () {
      final s = stroke([const Offset(0.4, 0.5), const Offset(0.6, 0.5)], width: 0.01);
      final before = MarkupGeometry.center(s, page);
      final m = MarkupGeometry.transform(s, page, scale: 2) as MarkupStroke;
      expect(MarkupGeometry.center(m, page).dx, closeTo(before.dx, 1e-9));
      expect(m.points.last.dx - m.points.first.dx, closeTo(0.4, 1e-9));
      expect(m.width, closeTo(0.02, 1e-9));
    });

    test('stickers move, resize within limits and turn', () {
      const s = MarkupSticker(id: 1, text: 'X', center: Offset(0.5, 0.5), size: 0.1);
      final m = MarkupGeometry.transform(s, page, delta: const Offset(0.1, 0.1), scale: 1.5, rotation: 0.5) as MarkupSticker;
      expect(m.center, const Offset(0.6, 0.6));
      expect(m.size, closeTo(0.15, 1e-9));
      expect(m.rotation, 0.5);
      expect((MarkupGeometry.transform(s, page, scale: 100) as MarkupSticker).size, MarkupSticker.maxSize);
      expect((MarkupGeometry.transform(s, page, scale: 0.001) as MarkupSticker).size, MarkupSticker.minSize);
    });

    test('shapes scale about their middle', () {
      const r = MarkupShape(id: 1, kind: ShapeKind.rectangle, from: Offset(0.4, 0.4), to: Offset(0.6, 0.6), color: 0xFF000000, width: 0.005);
      final m = MarkupGeometry.transform(r, page, scale: 2) as MarkupShape;
      expect(m.to.dx - m.from.dx, closeTo(0.4, 1e-9));
    });

    test('tools describe themselves', () {
      expect(MarkupTool.pen.penKind, PenKind.pen);
      expect(MarkupTool.ellipse.shapeKind, ShapeKind.ellipse);
      expect(MarkupTool.eraser.hasInk, isFalse);
      expect(MarkupTool.arrow.hasInk, isTrue);
      expect(MarkupTool.rectangle.label, 'Square');
    });
  });

  group('saving marks into the page picture', () {
    late Directory dir;
    late _Scanner scanner;
    late MarkupRendererImpl renderer;
    late String base;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('sv_mark');
      scanner = _Scanner();
      renderer = MarkupRendererImpl(scanner: scanner, workDir: () async => dir);
      final image = img.Image(width: 400, height: 300, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      // A blue block to show how the highlighter lets it through.
      img.fillRect(image, x1: 100, y1: 200, x2: 300, y2: 260, color: img.ColorRgb8(0, 0, 160));
      base = p.join(dir.path, 'base.jpg');
      File(base).writeAsBytesSync(img.encodeJpg(image, quality: 98));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    img.Image load(String path) => img.decodeJpg(File(path).readAsBytesSync())!;

    test('keeps the page size and draws the strokes where they were drawn', () async {
      final r = (await renderer.render(
        imagePath: base,
        settings: const FilterSettings(),
        items: [
          stroke([const Offset(0.1, 0.25), const Offset(0.9, 0.25)], width: 0.03),
        ],
      )).valueOrNull!;
      expect((r.width, r.height), (400, 300));
      final out = load(r.path);
      expect((out.width, out.height), (400, 300));
      final onLine = out.getPixel(200, 75);
      expect(onLine.r, greaterThan(200));
      expect(onLine.g, lessThan(60));
      final off = out.getPixel(200, 150);
      expect(off.g, greaterThan(240), reason: 'the rest of the page is untouched');
      expect(scanner.filtered, 0, reason: 'no colour filter was asked for');
    });

    test('a highlighter keeps the blue underneath visible, and tints white paper', () async {
      final r = (await renderer.render(
        imagePath: base,
        settings: const FilterSettings(),
        items: [
          stroke([const Offset(0.1, 0.77), const Offset(0.9, 0.77)], kind: PenKind.highlighter, color: 0x66FFEB3B, width: 0.12),
        ],
      )).valueOrNull!;
      final out = load(r.path);
      final over = out.getPixel(200, 231);
      expect(over.b, lessThan(200), reason: 'still dark blue under the yellow');
      final white = out.getPixel(30, 231);
      expect(white.r, greaterThan(240));
      expect(white.b, lessThan(215), reason: 'yellow tint on white paper');
    });

    test('shapes and stickers are drawn', () async {
      final r = (await renderer.render(
        imagePath: base,
        settings: const FilterSettings(),
        items: [
          const MarkupShape(id: 1, kind: ShapeKind.rectangle, from: Offset(0.1, 0.1), to: Offset(0.4, 0.3), color: 0xFF00AA00, width: 0.02),
          const MarkupShape(id: 2, kind: ShapeKind.ellipse, from: Offset(0.55, 0.1), to: Offset(0.9, 0.4), color: 0xFF0000FF, width: 0.02, filled: true),
          const MarkupSticker(id: 3, text: 'A', center: Offset(0.2, 0.55), size: 0.2),
        ],
      )).valueOrNull!;
      final out = load(r.path);
      expect(out.getPixel(40, 60).g, greaterThan(120));
      expect(out.getPixel(40, 60).r, lessThan(80), reason: 'left edge of the square is green');
      expect(out.getPixel(70, 60).r, greaterThan(240), reason: 'inside an empty square the page shows');
      expect(out.getPixel(290, 63).r, lessThan(235), reason: 'a filled circle tints its inside');
      var ink = 0;
      for (var y = 120; y < 200; y++) {
        for (var x = 40; x < 120; x++) {
          if (out.getPixel(x, y).r < 200) ink++;
        }
      }
      expect(ink, greaterThan(100), reason: 'the sticker draws something');
    });

    test('the colour filter is applied first, and the marks stay in their own colour', () async {
      final grey = img.Image(width: 400, height: 300, numChannels: 3);
      img.fill(grey, color: img.ColorRgb8(120, 120, 120));
      final filtered = p.join(dir.path, 'filtered.jpg');
      File(filtered).writeAsBytesSync(img.encodeJpg(grey, quality: 98));
      scanner.filterTo = (_) => filtered;
      final r = (await renderer.render(
        imagePath: base,
        settings: const FilterSettings(filter: ScanFilter.grayscale),
        items: [
          stroke([const Offset(0.1, 0.5), const Offset(0.9, 0.5)], width: 0.03),
        ],
      )).valueOrNull!;
      expect(scanner.filtered, 1);
      final out = load(r.path);
      expect(out.getPixel(200, 40).r, closeTo(120, 6), reason: 'the page comes from the filtered picture');
      expect(out.getPixel(200, 150).r, greaterThan(200));
      expect(out.getPixel(200, 150).g, lessThan(60), reason: 'the red stroke is not turned grey');
    });

    test('each save writes a new file and leaves the original alone', () async {
      final before = File(base).readAsBytesSync();
      final a = (await renderer.render(imagePath: base, settings: const FilterSettings(), items: const [])).valueOrNull!;
      final b = (await renderer.render(imagePath: base, settings: const FilterSettings(), items: const [])).valueOrNull!;
      expect(a.path, isNot(b.path));
      expect(File(base).readAsBytesSync(), before);
    });

    test('a missing or damaged picture is reported', () async {
      final r = await renderer.render(imagePath: p.join(dir.path, 'none.jpg'), settings: const FilterSettings(), items: const []);
      expect(r.failureOrNull, isNotNull);
      final bad = File(p.join(dir.path, 'bad.jpg'))..writeAsBytesSync([1, 2, 3]);
      expect((await renderer.render(imagePath: bad.path, settings: const FilterSettings(), items: const [])).failureOrNull, isNotNull);
    });
  });
}

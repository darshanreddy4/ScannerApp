import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/features/scanner/data/datasources/image_filters.dart';
import 'package:doculoom/features/scanner/data/datasources/image_processing_service.dart';
import 'package:doculoom/features/scanner/data/datasources/rgb_buffer.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';

typedef _Px = (int, int, int);

RgbBuffer _make(int w, int h, _Px Function(int x, int y) f) {
  final buf = RgbBuffer.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (r, g, b) = f(x, y);
      final i = (y * w + x) * 3;
      buf.data[i] = r.clamp(0, 255);
      buf.data[i + 1] = g.clamp(0, 255);
      buf.data[i + 2] = b.clamp(0, 255);
    }
  }
  return buf;
}

_Px _at(RgbBuffer b, int x, int y) {
  final i = (y * b.width + x) * 3;
  return (b.data[i], b.data[i + 1], b.data[i + 2]);
}

int _lum(_Px p) => (p.$1 * 77 + p.$2 * 150 + p.$3 * 29) >> 8;

double _mean(RgbBuffer b, int channel) {
  var s = 0;
  for (var i = channel; i < b.data.length; i += 3) {
    s += b.data[i];
  }
  return s / (b.data.length / 3);
}

double _meanLum(RgbBuffer b) => (_mean(b, 0) * 77 + _mean(b, 1) * 150 + _mean(b, 2) * 29) / 256;

double _std(RgbBuffer b) {
  final m = _meanLum(b);
  var s = 0.0;
  for (var i = 0; i < b.data.length; i += 3) {
    final l = (b.data[i] * 77 + b.data[i + 1] * 150 + b.data[i + 2] * 29) / 256;
    s += (l - m) * (l - m);
  }
  return math.sqrt(s / (b.data.length / 3));
}

int _spread(_Px p) => math.max(p.$1, math.max(p.$2, p.$3)) - math.min(p.$1, math.min(p.$2, p.$3));

RgbBuffer _apply(RgbBuffer src, ScanFilter f, {double brightness = 0, double contrast = 0}) =>
    ImageFilters.apply(src, FilterSettings(filter: f, brightness: brightness, contrast: contrast));

/// Printed page under uneven light: paper 240 fading to about 150 on the right, with dark lines of text.
RgbBuffer _page({int w = 400, int h = 300}) => _make(w, h, (x, y) {
  final light = 0.62 + 0.38 * (1 - x / (w - 1));
  final text = (y % 40 >= 18 && y % 40 < 21 && x > w ~/ 10 && x < w * 9 ~/ 10) || (x % 60 >= 28 && x % 60 < 31 && y > h ~/ 10 && y < h * 9 ~/ 10);
  final base = text ? 30 : 240;
  final v = (base * light).round();
  return (v, v, v);
});

void main() {
  group('every filter', () {
    final sources = <String, RgbBuffer>{
      'page': _page(),
      'photo': _make(120, 90, (x, y) => (40 + x, 90 + y, 140 - x ~/ 2)),
      'dark': _make(80, 60, (x, y) => (10 + x ~/ 4, 12 + y ~/ 5, 20 + x ~/ 6)),
      'flat': _make(50, 50, (x, y) => (128, 128, 128)),
      'white': _make(50, 50, (x, y) => (255, 255, 255)),
      'black': _make(50, 50, (x, y) => (0, 0, 0)),
    };

    for (final f in ScanFilter.values) {
      test('${f.name} keeps the size, leaves the source alone and handles flat, white and black pictures', () {
        for (final e in sources.entries) {
          final before = Uint8List.fromList(e.value.data);
          final out = _apply(e.value, f);
          expect(out.width, e.value.width, reason: '${f.name} ${e.key}');
          expect(out.height, e.value.height, reason: '${f.name} ${e.key}');
          expect(out.data.length, e.value.data.length);
          expect(e.value.data, before, reason: '${f.name} must not change the picture it was given (${e.key})');
        }
      });

      test('${f.name} copes with tiny and very thin pictures', () {
        for (final size in const [(1, 1), (2, 3), (7, 5), (500, 3), (3, 500)]) {
          final src = _make(size.$1, size.$2, (x, y) => (x * 7 % 256, y * 11 % 256, (x + y) * 13 % 256));
          final out = _apply(src, f);
          expect(out.width, size.$1);
          expect(out.height, size.$2);
        }
      });
    }

    test('Original with no adjustment hands the picture back as it is', () {
      final src = _page();
      expect(_apply(src, ScanFilter.original).data, src.data);
    });

    test('brightness and contrast still apply first, under any filter', () {
      final src = _make(60, 40, (x, y) => (100, 100, 100));
      expect(_meanLum(_apply(src, ScanFilter.original, brightness: 40)), greaterThan(_meanLum(src) + 40));
      final a = _apply(_page(w: 120, h: 90), ScanFilter.auto);
      final b = _apply(_page(w: 120, h: 90), ScanFilter.auto, brightness: 30);
      expect(b.data, isNot(a.data));
    });

    test('filters are deterministic', () {
      final src = _page(w: 160, h: 120);
      for (final f in ScanFilter.values) {
        expect(_apply(src, f).data, _apply(src, f).data, reason: f.name);
      }
    });
  });

  group('Auto', () {
    test('a flat low-contrast picture is stretched, but never by an extreme amount', () {
      final src = _make(200, 100, (x, y) => (90 + x ~/ 4, 90 + x ~/ 4, 90 + x ~/ 4));
      final out = _apply(src, ScanFilter.auto);
      expect(_std(out), greaterThan(_std(src) * 1.4));
      final lo = _at(out, 0, 50), hi = _at(out, 199, 50);
      expect(_lum(hi) - _lum(lo), lessThan(255));
    });

    test('a picture that is already well exposed changes only a little', () {
      final src = _make(256, 40, (x, y) => (x, x, x));
      final out = _apply(src, ScanFilter.auto);
      var diff = 0;
      for (var x = 0; x < 256; x++) {
        diff += (_lum(_at(out, x, 5)) - x).abs();
      }
      expect(diff / 256, lessThan(25));
    });

    test('a dark picture gets lighter and a bright one darker, towards the middle', () {
      final dark = _make(100, 60, (x, y) => (20 + x ~/ 3, 20 + x ~/ 3, 20 + x ~/ 3));
      final bright = _make(100, 60, (x, y) => (200 + x ~/ 4, 200 + x ~/ 4, 200 + x ~/ 4));
      expect(_meanLum(_apply(dark, ScanFilter.auto)), greaterThan(_meanLum(dark)));
      // A bright picture is also spread, so only check it stays inside the range.
      final b = _apply(bright, ScanFilter.auto);
      expect(_meanLum(b), inInclusiveRange(0, 255));
    });

    test('a colour cast is reduced but not removed', () {
      final src = _make(200, 100, (x, y) {
        final base = 60 + x * 170 ~/ 199;
        return (base, (base * 0.85).round(), (base * 0.65).round());
      });
      final out = _apply(src, ScanFilter.auto);
      double cast(RgbBuffer b) => _mean(b, 0) - _mean(b, 2);
      expect(cast(out), lessThan(cast(src)));
      expect(cast(out), greaterThan(0));
    });
  });

  group('Clean (colour document)', () {
    test('uneven lighting becomes an even white page and the text stays dark', () {
      final src = _page();
      final out = _apply(src, ScanFilter.magicColor);
      // Paper at the left (bright) and right (shadow) ends, away from text.
      final left = _lum(_at(out, 3, 5)), right = _lum(_at(out, 396, 5));
      expect(left, greaterThanOrEqualTo(235));
      expect(right, greaterThanOrEqualTo(235));
      expect((left - right).abs(), lessThan(12));
      // A text pixel: y=19 is inside a line, x=100 inside the span.
      expect(_lum(_at(out, 100, 19)), lessThan(90));
    });

    test('colours survive: a red logo stays red', () {
      final src = _make(300, 200, (x, y) {
        final red = x > 120 && x < 180 && y > 80 && y < 120;
        return red ? (200, 40, 40) : (235, 235, 235);
      });
      final out = _apply(src, ScanFilter.magicColor);
      final (r, g, b) = _at(out, 150, 100);
      expect(r, greaterThan(g + 60));
      expect(r, greaterThan(b + 60));
    });
  });

  group('B&W', () {
    test('it is neutral, black on white, and keeps smooth edges and pale marks', () {
      // A thin dark stroke with soft edges, and a thin pale pencil line, on white paper.
      final src = _make(400, 200, (x, y) {
        final stroke = x >= 100 && x < 112;
        final edge = (x - 100).clamp(0, 3) * 55;
        final v = stroke ? (235 - 195 * (x < 103 ? edge / 165 : (x >= 109 ? (112 - x) / 3 : 1))).round() : 235;
        final pencil = x > 300 && x < 340 && y > 98 && y < 102;
        final g = pencil ? 130 : v;
        return (g, g, g);
      });
      final out = _apply(src, ScanFilter.documentBw);
      for (var i = 0; i < out.data.length; i += 3) {
        expect(out.data[i] == out.data[i + 1] && out.data[i + 1] == out.data[i + 2], isTrue);
      }
      expect(_lum(_at(out, 10, 100)), greaterThanOrEqualTo(240));
      expect(_lum(_at(out, 106, 100)), lessThanOrEqualTo(40));
      final mids = [for (var x = 98; x < 114; x++) _lum(_at(out, x, 100))].where((v) => v > 20 && v < 235);
      expect(mids, isNotEmpty, reason: 'edges are anti-aliased, not stair-stepped');
      final pencil = _lum(_at(out, 320, 100));
      expect(pencil, inInclusiveRange(30, 200), reason: 'pencil keeps some grey instead of vanishing or going solid black');
    });

    test('lighting is flattened before the threshold, so the shadow side is not black', () {
      final out = _apply(_page(), ScanFilter.documentBw);
      expect(_lum(_at(out, 396, 5)), greaterThanOrEqualTo(240));
      expect(_lum(_at(out, 100, 19)), lessThanOrEqualTo(40));
    });
  });

  group('Sharp B&W', () {
    test('every pixel is pure black or pure white, with the page white and the text black', () {
      final out = _apply(_page(), ScanFilter.sharpBw);
      for (var i = 0; i < out.data.length; i += 3) {
        expect(out.data[i] == 0 || out.data[i] == 255, isTrue);
        expect(out.data[i] == out.data[i + 1] && out.data[i] == out.data[i + 2], isTrue);
      }
      expect(_lum(_at(out, 3, 5)), 255);
      expect(_lum(_at(out, 396, 5)), 255, reason: 'the shadowed side is not turned black');
      expect(_lum(_at(out, 100, 19)), 0);
    });
  });

  group('Grey and Noir', () {
    test('Grey is neutral and never reverses the order of tones', () {
      final src = _make(256, 20, (x, y) => (x, (x * 0.9).round(), (x * 0.8).round()));
      final out = _apply(src, ScanFilter.grayscale);
      var last = -1;
      for (var x = 0; x < 256; x++) {
        final (r, g, b) = _at(out, x, 5);
        expect(r == g && g == b, isTrue);
        expect(r, greaterThanOrEqualTo(last));
        last = r;
      }
    });

    test('Noir is neutral, more contrasty than the source, with deep blacks', () {
      final src = _make(200, 60, (x, y) => (70 + x ~/ 2, 70 + x ~/ 2, 70 + x ~/ 2));
      final out = _apply(src, ScanFilter.noir);
      expect(_std(out), greaterThan(_std(src)));
      final dark = _apply(_make(10, 10, (x, y) => (20, 20, 20)), ScanFilter.noir);
      expect(_lum(_at(dark, 5, 5)), lessThan(12));
      final (r, g, b) = _at(out, 50, 5);
      expect(r == g && g == b, isTrue);
    });

    test('Noir lightens red more than blue, like a red filter', () {
      final red = _apply(_make(4, 4, (x, y) => (200, 60, 60)), ScanFilter.noir);
      final blue = _apply(_make(4, 4, (x, y) => (60, 60, 200)), ScanFilter.noir);
      expect(_lum(_at(red, 1, 1)), greaterThan(_lum(_at(blue, 1, 1))));
    });
  });

  group('Whiteboard', () {
    test('the board turns white, dark ink is dark, and marker colours get stronger', () {
      final src = _make(400, 240, (x, y) {
        final board = (190 - x * 40 ~/ 399);
        if (y > 100 && y < 104 && x > 40 && x < 360) return (board ~/ 5, board ~/ 5, board ~/ 5);
        if (y > 160 && y < 166 && x > 40 && x < 200) return (board - 10, board ~/ 2, board ~/ 2);
        return (board, board, board);
      });
      final out = _apply(src, ScanFilter.whiteboard);
      expect(_lum(_at(out, 20, 20)), greaterThanOrEqualTo(240));
      expect(_lum(_at(out, 380, 20)), greaterThanOrEqualTo(240));
      expect(_lum(_at(out, 100, 102)), lessThan(80));
      expect(_spread(_at(out, 100, 163)), greaterThan(_spread(_at(src, 100, 163))));
    });
  });

  group('Vivid', () {
    test('grey stays grey', () {
      final src = _make(30, 10, (x, y) => (x * 8, x * 8, x * 8));
      final out = _apply(src, ScanFilter.vivid);
      for (var x = 0; x < 30; x++) {
        final (r, g, b) = _at(out, x, 3);
        expect(r == g && g == b, isTrue);
      }
    });

    test('weak colours are lifted more than strong ones', () {
      final weak = _apply(_make(8, 8, (x, y) => (120, 130, 150)), ScanFilter.vivid);
      final strong = _apply(_make(8, 8, (x, y) => (40, 90, 220)), ScanFilter.vivid);
      final weakGain = _spread(_at(weak, 2, 2)) / 30;
      final strongGain = _spread(_at(strong, 2, 2)) / 180;
      expect(weakGain, greaterThan(strongGain));
      expect(weakGain, greaterThan(1.0));
    });

    test('skin tones are protected: they gain less than a blue of similar strength', () {
      final skin = _apply(_make(8, 8, (x, y) => (210, 160, 130)), ScanFilter.vivid);
      final blue = _apply(_make(8, 8, (x, y) => (130, 160, 210)), ScanFilter.vivid);
      final skinGain = _spread(_at(skin, 2, 2)) / 80;
      final blueGain = _spread(_at(blue, 2, 2)) / 80;
      expect(skinGain, lessThan(blueGain));
    });
  });

  group('Warm and Cool', () {
    final mid = _make(40, 40, (x, y) => (128, 128, 128));

    test('Warm adds red and takes blue away; Cool does the opposite', () {
      final warm = _apply(mid, ScanFilter.warm);
      final cool = _apply(mid, ScanFilter.cool);
      expect(_mean(warm, 0), greaterThan(_mean(warm, 2) + 10));
      expect(_mean(cool, 2), greaterThan(_mean(cool, 0) + 10));
    });

    test('brightness is about the same, and white stays white', () {
      for (final f in [ScanFilter.warm, ScanFilter.cool]) {
        expect((_meanLum(_apply(mid, f)) - 128).abs(), lessThan(10), reason: f.name);
        final white = _at(_apply(_make(4, 4, (x, y) => (255, 255, 255)), f), 1, 1);
        expect(white.$1, greaterThanOrEqualTo(245), reason: f.name);
        expect(white.$2, greaterThanOrEqualTo(245), reason: f.name);
        expect(white.$3, greaterThanOrEqualTo(245), reason: f.name);
      }
    });
  });

  group('the same look at any size', () {
    test('a small preview and the full picture give the same result for the filters that depend on neighbours', () {
      final full = _page(w: 800, h: 600);
      final small = full.boxShrink(2);
      for (final f in [ScanFilter.magicColor, ScanFilter.documentBw, ScanFilter.whiteboard, ScanFilter.vivid]) {
        final a = _apply(full, f).boxShrink(2);
        final b = _apply(small, f);
        expect((_meanLum(a) - _meanLum(b)).abs(), lessThan(8), reason: f.name);
      }
    });
  });

  group('speed', () {
    test('no filter is slow on a half megapixel picture', () {
      final src = _page(w: 800, h: 600);
      for (final f in ScanFilter.values) {
        final sw = Stopwatch()..start();
        _apply(src, f);
        expect(sw.elapsed, lessThan(const Duration(seconds: 6)), reason: f.name);
      }
    });
  });

  group('box shrink', () {
    test('averages blocks and keeps odd edges', () {
      final src = _make(5, 5, (x, y) => ((x + y) % 2 == 0 ? 0 : 200, 100, 50));
      final out = src.boxShrink(2);
      expect(out.width, 2);
      expect(out.height, 2);
      final (r, g, b) = _at(out, 0, 0);
      expect(r, 100);
      expect(g, 100);
      expect(b, 50);
    });

    test('a factor of one returns the same buffer', () {
      final src = _page(w: 10, h: 10);
      expect(identical(src.boxShrink(1), src), isTrue);
    });
  });

  group('preview copy', () {
    // Decoding in the debug VM is slow; the real app runs compiled code.
    const slow = Timeout(Duration(minutes: 4));
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_proxy'));
    tearDown(() => dir.deleteSync(recursive: true));

    String photo(String name, int w, int h) {
      final image = img.Image(width: w, height: h, numChannels: 3);
      for (final px in image) {
        px
          ..r = (px.x * 255) ~/ w
          ..g = (px.y * 255) ~/ h
          ..b = 90;
      }
      final path = p.join(dir.path, name);
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 90));
      return path;
    }

    ({int w, int h}) size(Uint8List jpg) {
      final i = img.decodeJpg(jpg)!;
      return (w: i.width, h: i.height);
    }

    test('a big picture is previewed at the preview size and the small copy is kept', () async {
      final path = photo('big.jpg', 2000, 1500);
      final proxy = p.join(dir.path, 'proxy.jpg');
      final bytes = await const ImageProcessingService().preview(path, const FilterSettings(filter: ScanFilter.auto), proxyPath: proxy);
      final s = size(bytes);
      expect(math.max(s.w, s.h), lessThanOrEqualTo(ImageProcessingService.previewSide));
      expect(File(proxy).existsSync(), isTrue);
    }, timeout: slow);

    test('later previews, with any filter, read the small copy: they work even when the original is gone', () async {
      final path = photo('a.jpg', 1800, 1200);
      final proxy = p.join(dir.path, 'proxy.jpg');
      const service = ImageProcessingService();
      await service.preview(path, const FilterSettings(), proxyPath: proxy);
      File(path).deleteSync();
      for (final f in const [ScanFilter.auto, ScanFilter.magicColor, ScanFilter.noir]) {
        final bytes = await service.preview(path, FilterSettings(filter: f), proxyPath: proxy);
        expect(size(bytes).w, greaterThan(0), reason: f.name);
      }
    }, timeout: slow);

    test('thumbnails come from the same copy, one per filter, at the thumbnail size', () async {
      final path = photo('b.jpg', 1800, 1200);
      final proxy = p.join(dir.path, 'proxy.jpg');
      const service = ImageProcessingService();
      await service.preview(path, const FilterSettings(), proxyPath: proxy);
      File(path).deleteSync();
      final thumbs = await service.previewBatch(path, [for (final f in filterOrder) FilterSettings(filter: f)], 180, proxyPath: proxy);
      expect(thumbs.length, filterOrder.length);
      for (final t in thumbs) {
        expect(math.max(size(t).w, size(t).h), lessThanOrEqualTo(180));
      }
    }, timeout: slow);

    test('a changed original makes a new small copy', () async {
      final path = photo('c.jpg', 1200, 900);
      final proxy = p.join(dir.path, 'proxy.jpg');
      const service = ImageProcessingService();
      final first = await service.preview(path, const FilterSettings(), proxyPath: proxy);
      expect(size(first).w, 1200);
      // Same name, new picture, written a moment later.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      photo('c.jpg', 600, 400);
      final second = await service.preview(path, const FilterSettings(), proxyPath: proxy);
      expect(size(second).w, 600);
    }, timeout: slow);

    test('a damaged small copy is replaced instead of failing', () async {
      final path = photo('d.jpg', 800, 600);
      final proxy = p.join(dir.path, 'proxy.jpg');
      File(proxy).writeAsBytesSync([1, 2, 3, 4]);
      // The damaged copy is newer than the original, so it is tried first.
      final bytes = await const ImageProcessingService().preview(path, const FilterSettings(), proxyPath: proxy);
      expect(size(bytes).w, 800);
    }, timeout: slow);

    test('without a place for the copy it still works', () async {
      final path = photo('e.jpg', 500, 400);
      final bytes = await const ImageProcessingService().preview(path, const FilterSettings(filter: ScanFilter.vivid));
      expect(size(bytes).w, 500);
    }, timeout: slow);

    test('a picture that is not an image fails clearly instead of hanging', () async {
      final path = p.join(dir.path, 'bad.jpg');
      File(path).writeAsBytesSync([0, 1, 2, 3]);
      await expectLater(const ImageProcessingService().preview(path, const FilterSettings(), proxyPath: p.join(dir.path, 'x.jpg')), throwsA(anything));
    }, timeout: slow);

    test('rendering at full size gives the same picture size and a decodable file', () async {
      final path = photo('f.jpg', 900, 700);
      final out = p.join(dir.path, 'out.jpg');
      final info = await const ImageProcessingService().applyFilter(path, const FilterSettings(filter: ScanFilter.magicColor), out);
      expect(info.width, 900);
      expect(info.height, 700);
      expect(img.decodeJpg(File(out).readAsBytesSync()), isNotNull);
    }, timeout: slow);
  });

  group('handwriting filters', () {
    const paper = (235, 235, 232);
    const rule = (150, 170, 225);
    const pen = (30, 30, 70);

    /// A ruled notebook page with blue lines every 20 rows, and a pen stroke that crosses a line.
    RgbBuffer notebook({bool short = false}) => _make(300, 200, (x, y) {
      final onRule = y % 20 == 10 || y % 20 == 11;
      final stroke = x >= 100 && x < 104 && y >= 3 && y < 17;
      if (stroke) return pen;
      // a short dash of the same colour as the lines, too short to be a line
      if (short && y == 55 && x >= 200 && x < 212) return rule;
      if (onRule && !short) return rule;
      return paper;
    });

    test('Notebook takes the ruled lines away and keeps the writing, also where it crosses a line', () {
      final out = _apply(notebook(), ScanFilter.notebook);
      for (final y in [30, 50, 70, 90, 110, 130, 150, 170]) {
        expect(_lum(_at(out, 150, y + 0)), greaterThan(235), reason: 'row $y was a line');
        expect(_lum(_at(out, 20, y + 1)), greaterThan(235), reason: 'row ${y + 1} was a line');
      }
      expect(_lum(_at(out, 101, 6)), lessThan(110), reason: 'ink above the line');
      expect(_lum(_at(out, 101, 10)), lessThan(130), reason: 'ink on the line');
      expect(_lum(_at(out, 101, 15)), lessThan(110), reason: 'ink below the line');
      expect(_lum(_at(out, 250, 100)), greaterThan(240), reason: 'the paper is white');
    });

    test('Notebook leaves strokes that are too short to be a ruled line', () {
      final out = _apply(notebook(short: true), ScanFilter.notebook);
      expect(_lum(_at(out, 206, 55)), lessThan(235), reason: 'a short horizontal mark is writing');
    });

    test('the other filters leave the ruled lines visible', () {
      for (final f in [ScanFilter.handwriting, ScanFilter.pencil]) {
        final out = _apply(notebook(), f);
        expect(_lum(_at(out, 150, 10)), lessThan(_lum(_at(out, 150, 5))), reason: f.name);
      }
    });

    test('Notebook copes with pages narrower than its window', () {
      for (final w in [1, 2, 3, 12, 40]) {
        final out = _apply(_make(w, 30, (x, y) => y % 10 == 5 ? rule : paper), ScanFilter.notebook);
        expect(out.width, w);
      }
    });

    test('Handwriting whitens the page, darkens the ink and keeps the colour of the pen', () {
      const red = (190, 50, 50);
      final src = _make(200, 100, (x, y) => (x >= 90 && x < 96 && y >= 20 && y < 80) ? red : (paper.$1 - x ~/ 10, paper.$2 - x ~/ 10, paper.$3 - x ~/ 10));
      final out = _apply(src, ScanFilter.handwriting);
      final ink = _at(out, 92, 50);
      expect(_lum(_at(out, 20, 50)), greaterThan(238));
      expect(_lum(_at(out, 180, 50)), greaterThan(238), reason: 'the shadow at the right is gone');
      expect(ink.$1, greaterThan(ink.$2 + 40), reason: 'still red: $ink');
      expect(_lum(ink), lessThan(_lum(red)), reason: 'darker than the pen was');
    });

    test('Pencil pulls faint grey strokes out of the paper, in grey, and makes thin lines a little bolder', () {
      const graphite = (185, 185, 185);
      final src = _make(120, 60, (x, y) => (y == 30 && x > 10 && x < 110) ? graphite : paper);
      final out = _apply(src, ScanFilter.pencil);
      final line = _at(out, 60, 30);
      expect(_lum(line), lessThan(150), reason: 'much darker than the graphite that was $graphite');
      expect(_spread(line), 0, reason: 'grey');
      expect(_lum(_at(out, 60, 5)), greaterThan(240), reason: 'the paper is white');
      expect(_lum(_at(out, 60, 29)), lessThan(235), reason: 'the line is a little thicker than one pixel');
    });

    test('they are saved after the others, so older saved names keep their meaning', () {
      expect(ScanFilter.values.skip(11).map((f) => f.name), ['handwriting', 'pencil', 'notebook']);
    });
  });

  test('every filter has a name, a hint, an icon and a place in the list', () {
    expect(filterOrder.toSet(), ScanFilter.values.toSet());
    expect(filterOrder.length, ScanFilter.values.length);
  });

  test('filters are saved by name, so the first four keep their meaning', () {
    expect(ScanFilter.values.take(4).map((f) => f.name), ['original', 'documentBw', 'magicColor', 'grayscale']);
  });
}

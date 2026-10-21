import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scanvault/features/export/data/document_builders.dart';
import 'package:scanvault/features/export/domain/entities/export_options.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/scanner/data/datasources/document_edge_detector.dart';
import 'package:scanvault/features/scanner/data/datasources/image_filters.dart';
import 'package:scanvault/features/scanner/data/datasources/rgb_buffer.dart';
import 'package:scanvault/features/scanner/domain/entities/filter_settings.dart';
import 'package:scanvault/features/scanner/domain/entities/quad.dart';

/// Light skewed quadrilateral on a dark background.
Uint8List _syntheticFrame(int w, int h, List<(double, double)> poly) {
  final out = Uint8List(w * h)..fillRange(0, w * h, 30);
  bool inside(double x, double y) {
    var c = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final (xi, yi) = poly[i];
      final (xj, yj) = poly[j];
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) c = !c;
    }
    return c;
  }

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (inside(x + 0.5, y + 0.5)) out[y * w + x] = 220;
    }
  }
  return out;
}

void main() {
  group('DocumentEdgeDetector', () {
    test('finds the corners of a skewed document', () {
      const w = 120, h = 160;
      final frame = _syntheticFrame(w, h, [(25, 20), (95, 28), (100, 135), (20, 128)]);
      final q = const DocumentEdgeDetector().detect(frame, w, h);

      expect(q, isNotNull);
      const tol = 0.04;
      expect(q!.tl.x, closeTo(25 / w, tol));
      expect(q.tl.y, closeTo(20 / h, tol));
      expect(q.tr.x, closeTo(95 / w, tol));
      expect(q.br.y, closeTo(135 / h, tol));
      expect(q.bl.x, closeTo(20 / w, tol));
    });

    test('returns null for a uniform frame', () {
      final flat = Uint8List(100 * 100)..fillRange(0, 10000, 128);
      expect(const DocumentEdgeDetector().detect(flat, 100, 100), isNull);
    });
  });

  group('PerspectiveTransform', () {
    test('rectifies a quad into an upright image of the expected size', () {
      final src = RgbBuffer.blank(200, 200);
      for (var i = 0; i < src.data.length; i++) {
        src.data[i] = 0;
      }
      // Red square region 50..150.
      for (var y = 50; y < 150; y++) {
        for (var x = 50; x < 150; x++) {
          src.data[(y * 200 + x) * 3] = 255;
        }
      }
      const quad = Quad(NormPoint(0.25, 0.25), NormPoint(0.75, 0.25), NormPoint(0.75, 0.75), NormPoint(0.25, 0.75));
      final out = PerspectiveTransform.warp(src, quad);

      expect(out.width, inInclusiveRange(98, 102));
      expect(out.height, inInclusiveRange(98, 102));
      final mid = (out.height ~/ 2 * out.width + out.width ~/ 2) * 3;
      expect(out.data[mid], greaterThan(240));
    });
  });

  group('ImageFilters', () {
    RgbBuffer gradient() {
      final b = RgbBuffer.blank(64, 64);
      for (var i = 0; i < 64 * 64; i++) {
        final v = (i % 64) * 4;
        b.data[i * 3] = b.data[i * 3 + 1] = b.data[i * 3 + 2] = v;
      }
      return b;
    }

    test('document filter outputs only black or white', () {
      final out = ImageFilters.apply(gradient(), const FilterSettings(filter: ScanFilter.documentBw));
      expect(out.data.every((v) => v == 0 || v == 255), isTrue);
    });

    test('grayscale equalises channels', () {
      final src = RgbBuffer.blank(4, 4)..data.fillRange(0, 48, 0);
      for (var i = 0; i < 16; i++) {
        src.data[i * 3] = 200;
      }
      final out = ImageFilters.apply(src, const FilterSettings(filter: ScanFilter.grayscale));
      for (var i = 0; i < 16; i++) {
        expect(out.data[i * 3], out.data[i * 3 + 1]);
        expect(out.data[i * 3], out.data[i * 3 + 2]);
      }
    });

    test('brightness raises and contrast spreads pixel values', () {
      final base = gradient();
      final bright = ImageFilters.apply(base, const FilterSettings(brightness: 50));
      expect(bright.data[32 * 3], greaterThan(base.data[32 * 3]));
      final contrast = ImageFilters.apply(base, const FilterSettings(contrast: 60));
      expect(contrast.data[10 * 3], lessThan(base.data[10 * 3]));
      expect(contrast.data[60 * 3], greaterThan(base.data[60 * 3]));
    });

    test('magic color keeps size and whitens a shaded page', () {
      final src = RgbBuffer.blank(80, 80);
      for (var i = 0; i < 80 * 80; i++) {
        src.data[i * 3] = src.data[i * 3 + 1] = src.data[i * 3 + 2] = 150;
      }
      final out = ImageFilters.apply(src, const FilterSettings(filter: ScanFilter.magicColor));
      expect(out.width, 80);
      expect(out.data[40 * 80 * 3 + 40 * 3], greaterThan(220));
    });
  });

  group('Exporters', () {
    late Directory tmp;
    late List<PageSource> pages;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('scanvault_test');
      pages = [];
      for (var i = 0; i < 2; i++) {
        final image = img.Image(width: 120, height: 160)..clear(img.ColorRgb8(240, 240, 240));
        final f = File('${tmp.path}/p$i.jpg')..writeAsBytesSync(img.encodeJpg(image));
        pages.add(PageSource(path: f.path, width: 120, height: 160));
      }
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('PDF has one page per image', () async {
      final out = '${tmp.path}/o.pdf';
      await buildPdf(pages, ExportQuality.high, out);
      final text = String.fromCharCodes(File(out).readAsBytesSync());
      expect(text.startsWith('%PDF'), isTrue);
      expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
    });

    test('DOCX is a valid package containing every image', () {
      final out = '${tmp.path}/o.docx';
      buildDocx(pages, ExportQuality.medium, out);
      final zip = ZipDecoder().decodeBytes(File(out).readAsBytesSync());
      final names = zip.files.map((f) => f.name).toSet();
      expect(names, containsAll(['[Content_Types].xml', '_rels/.rels', 'word/document.xml', 'word/_rels/document.xml.rels']));
      expect(names, containsAll(['word/media/image1.jpg', 'word/media/image2.jpg']));
    });
  });

  group('AdPolicy', () {
    const policy = AdPolicy(interstitialCooldown: Duration(minutes: 2));
    final now = DateTime(2026, 1, 1, 12);

    test('premium never sees ads', () {
      expect(policy.shouldShowInterstitial(plan: PlanStatus.premium, lastShownAt: null, now: now), isFalse);
      expect(policy.shouldShowBanner(PlanStatus.premium), isFalse);
    });

    test('free user sees banner and a first interstitial', () {
      expect(policy.shouldShowBanner(PlanStatus.free), isTrue);
      expect(policy.shouldShowInterstitial(plan: PlanStatus.free, lastShownAt: null, now: now), isTrue);
    });

    test('cooldown suppresses back-to-back interstitials', () {
      expect(
        policy.shouldShowInterstitial(plan: PlanStatus.free, lastShownAt: now.subtract(const Duration(seconds: 30)), now: now),
        isFalse,
      );
      expect(
        policy.shouldShowInterstitial(plan: PlanStatus.free, lastShownAt: now.subtract(const Duration(minutes: 3)), now: now),
        isTrue,
      );
    });
  });

  group('Quad', () {
    test('rotating four times returns the original', () {
      const q = Quad(NormPoint(0.1, 0.2), NormPoint(0.9, 0.1), NormPoint(0.8, 0.9), NormPoint(0.2, 0.8));
      var r = q;
      for (var i = 0; i < 4; i++) {
        r = r.rotatedClockwise();
      }
      expect(r.maxCornerDelta(q), lessThan(1e-9));
    });

    test('bow-tie is not convex', () {
      const bow = Quad(NormPoint(0, 0), NormPoint(1, 1), NormPoint(1, 0), NormPoint(0, 1));
      expect(bow.isConvex, isFalse);
    });
  });
}

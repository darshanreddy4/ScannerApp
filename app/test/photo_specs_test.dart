import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/features/photo_tools/domain/crop_math.dart';
import 'package:scanvault/features/photo_tools/domain/photo_specs.dart';
import 'package:scanvault/features/photo_tools/domain/sheet_layout.dart';

void main() {
  group('photo size catalog', () {
    test('every country has sizes, and ids and codes are unique', () {
      final codes = <String>{};
      for (final c in PhotoCatalog.countries) {
        expect(codes.add(c.code), isTrue, reason: 'duplicate ${c.code}');
        expect(c.specs, isNotEmpty, reason: c.name);
        final ids = <String>{};
        for (final s in c.specs) {
          expect(ids.add(s.id), isTrue, reason: '${c.name} repeats ${s.id}');
          expect(s.widthMm, greaterThan(10), reason: '${c.name} ${s.name}');
          expect(s.heightMm, greaterThan(10), reason: '${c.name} ${s.name}');
          expect(s.widthMm, lessThan(100));
          expect(s.heightMm, lessThan(100));
          if (s.headMinMm != null) {
            expect(s.headMinMm!, lessThan(s.headMaxMm!), reason: c.name);
            expect(s.headMaxMm!, lessThan(s.heightMm), reason: c.name);
          }
        }
      }
    });

    test('the list is sorted by name and findable', () {
      final names = PhotoCatalog.countries.map((c) => c.name).toList();
      expect(names, [...names]..sort());
      expect(PhotoCatalog.byCode('IN')!.name, 'India');
      expect(PhotoCatalog.byCode('XX'), isNull);
      expect(PhotoCatalog.search('kin').map((c) => c.code), contains('GB'));
      expect(PhotoCatalog.search('us').map((c) => c.code), contains('US'));
      expect(PhotoCatalog.search('  '), PhotoCatalog.countries);
      expect(PhotoCatalog.search('zzzz'), isEmpty);
    });

    test('well known sizes are right', () {
      PhotoSpec find(String code, String id) => PhotoCatalog.byCode(code)!.specs.firstWhere((s) => s.id == id);
      expect((find('IN', 'passport').widthMm, find('IN', 'passport').heightMm), (35, 45));
      expect((find('IN', 'pan').widthMm, find('IN', 'pan').heightMm), (25, 35));
      expect((find('US', 'passport').widthMm, find('US', 'passport').heightMm), (51, 51));
      expect((find('CA', 'passport').widthMm, find('CA', 'passport').heightMm), (50, 70));
      expect((find('CN', 'passport').widthMm, find('CN', 'passport').heightMm), (33, 48));
    });

    test('pixels follow the resolution, and pixel sizes are exact', () {
      const passport = PhotoSpec(id: 'p', name: 'Passport', widthMm: 35, heightMm: 45);
      expect((passport.pixelWidth(300), passport.pixelHeight(300)), (413, 531));
      expect((passport.pixelWidth(600), passport.pixelHeight(600)), (827, 1063));
      final online = PhotoSpec.custom(widthMm: 25.4, heightMm: 33.9, widthPx: 200, heightPx: 267);
      expect((online.pixelWidth(300), online.pixelHeight(300)), (200, 267));
      expect(online.sizeLabel, '200 x 267 px');
      expect(passport.sizeLabel, '35 x 45 mm');
      expect(const PhotoSpec(id: 'a', name: 'A', widthMm: 50.8, heightMm: 50.8).sizeLabelFull, contains('2.00 x 2.00 in'));
    });

    test('head size target uses the rule or the usual share of the photo', () {
      const ruled = PhotoSpec(id: 'p', name: 'P', widthMm: 35, heightMm: 45, headMinMm: 32, headMaxMm: 36);
      const plain = PhotoSpec(id: 'q', name: 'Q', widthMm: 25, heightMm: 35);
      expect(ruled.headTargetMm, 34);
      expect(plain.headTargetMm, closeTo(26.25, 0.001));
    });
  });

  group('crop view', () {
    // A wide 4000 x 3000 photo in a 350 x 450 frame (35 x 45 mm).
    const w = 4000, h = 3000;
    const fw = 350.0, fh = 450.0;

    test('starts covering the frame, centred, and shows the right shape', () {
      final v = CropView.initial(w, h);
      final r = v.rect(w, h, fw, fh);
      expect(r.height, closeTo(3000, 0.01), reason: 'a wide photo is limited by its height');
      expect(r.width / r.height, closeTo(fw / fh, 1e-9));
      expect(r.left + r.width / 2, closeTo(2000, 0.01));
    });

    test('zooming in shows a smaller part and never goes below 1 or above the maximum', () {
      var v = CropView.initial(w, h);
      final before = v.rect(w, h, fw, fh);
      v = v.zoomedBy(2, w, h, fw, fh);
      expect(v.rect(w, h, fw, fh).width, closeTo(before.width / 2, 0.01));
      expect(v.zoomedBy(0.01, w, h, fw, fh).zoom, 1);
      expect(v.zoomedBy(1000, w, h, fw, fh).zoom, CropView.maxZoom);
    });

    test('panning moves the photo with the finger and stops at the edges', () {
      var v = CropView.initial(w, h).zoomedBy(2, w, h, fw, fh);
      final start = v.centerX;
      v = v.panned(50, 0, w, h, fw, fh); // finger moves right: the photo moves right, so the view moves left
      expect(v.centerX, lessThan(start));
      v = v.panned(100000, 100000, w, h, fw, fh);
      final r = v.rect(w, h, fw, fh);
      expect(r.left, closeTo(0, 0.01));
      expect(r.top, closeTo(0, 0.01));
      v = v.panned(-100000, -100000, w, h, fw, fh);
      final r2 = v.rect(w, h, fw, fh);
      expect(r2.right, closeTo(w, 0.01));
      expect(r2.bottom, closeTo(h, 0.01));
    });

    test('the visible part always stays inside the photo', () {
      var v = CropView.initial(w, h);
      for (var i = 0; i < 40; i++) {
        v = v.zoomedBy(i.isEven ? 1.3 : 0.8, w, h, fw, fh).panned(i * 13.0 - 200, 170 - i * 9.0, w, h, fw, fh);
        final r = v.rect(w, h, fw, fh);
        expect(r.left, greaterThanOrEqualTo(-0.001));
        expect(r.top, greaterThanOrEqualTo(-0.001));
        expect(r.right, lessThanOrEqualTo(w + 0.001));
        expect(r.bottom, lessThanOrEqualTo(h + 0.001));
      }
    });

    test('a portrait photo in a portrait frame', () {
      final r = CropView.initial(1000, 2000).rect(1000, 2000, 350, 450);
      expect(r.width, closeTo(1000, 0.01));
      expect(r.height, closeTo(1000 * 450 / 350, 0.01));
    });
  });

  group('print sheet layout', () {
    test('a 4 x 6 in sheet holds six 35 x 45 mm photos', () {
      final l = SheetLayout.fit(paperWidthMm: 101.6, paperHeightMm: 152.4, photoWidthMm: 35, photoHeightMm: 45);
      expect(l.capacity, 6);
      expect((l.columns, l.rows), (2, 3));
      expect(l.turned, isFalse);
    });

    test('A4 holds many, and nothing leaves the paper or overlaps', () {
      final l = SheetLayout.fit(paperWidthMm: 210, paperHeightMm: 297, photoWidthMm: 35, photoHeightMm: 45);
      expect(l.capacity, greaterThanOrEqualTo(30));
      for (final s in l.slots) {
        expect(s.xMm, greaterThanOrEqualTo(5 - 0.001));
        expect(s.yMm, greaterThanOrEqualTo(5 - 0.001));
        expect(s.xMm + 35, lessThanOrEqualTo(l.paperWidthMm - 5 + 0.001));
        expect(s.yMm + 45, lessThanOrEqualTo(l.paperHeightMm - 5 + 0.001));
      }
      for (var i = 0; i < l.slots.length; i++) {
        for (var j = i + 1; j < l.slots.length; j++) {
          final a = l.slots[i], b = l.slots[j];
          final apart = (a.xMm - b.xMm).abs() >= 35 - 0.001 || (a.yMm - b.yMm).abs() >= 45 - 0.001;
          expect(apart, isTrue);
        }
      }
    });

    test('the paper is turned when that fits more', () {
      // 100 x 60 paper: upright holds 2 x 1 of 20 x 25? check by capacity comparison
      final up = SheetLayout.fit(paperWidthMm: 60, paperHeightMm: 100, photoWidthMm: 25, photoHeightMm: 35);
      final side = SheetLayout.fit(paperWidthMm: 100, paperHeightMm: 60, photoWidthMm: 25, photoHeightMm: 35);
      expect(up.capacity, side.capacity, reason: 'the same paper gives the same answer either way up');
    });

    test('fewer copies are placed from the top left and the block is centred', () {
      final l = SheetLayout.fit(paperWidthMm: 101.6, paperHeightMm: 152.4, photoWidthMm: 35, photoHeightMm: 45, copies: 2);
      expect(l.slots, hasLength(2));
      expect(l.slots[0].yMm, closeTo(l.slots[1].yMm, 0.001));
      final left = l.slots.first.xMm;
      final right = l.paperWidthMm - (l.slots.last.xMm + 35);
      expect(left, closeTo(right, 0.001));
    });

    test('asking for more copies than fit gives what fits', () {
      final l = SheetLayout.fit(paperWidthMm: 101.6, paperHeightMm: 152.4, photoWidthMm: 35, photoHeightMm: 45, copies: 50);
      expect(l.slots, hasLength(6));
    });

    test('a photo bigger than the paper gives an empty sheet instead of an error', () {
      final l = SheetLayout.fit(paperWidthMm: 50, paperHeightMm: 50, photoWidthMm: 51, photoHeightMm: 51);
      expect(l.capacity, 0);
      expect(l.slots, isEmpty);
    });
  });
}

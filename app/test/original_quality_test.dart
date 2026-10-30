import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/features/scanner/data/datasources/image_processing_service.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/quad.dart';
import 'package:doculoom/features/scanner/domain/entities/scan_mode.dart';
import 'package:doculoom/features/scanner/presentation/bloc/camera_cubit.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('photos start untouched', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_orig'));
    tearDown(() => dir.deleteSync(recursive: true));

    String photo() {
      final image = img.Image(width: 120, height: 80, numChannels: 3);
      for (final px in image) {
        px
          ..r = (px.x * 2) % 256
          ..g = (px.y * 3) % 256
          ..b = 90;
      }
      final path = p.join(dir.path, 'in.jpg');
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 90));
      return path;
    }

    test('cropping the whole picture keeps the very same pixels and file', () async {
      final source = photo();
      final out = p.join(dir.path, 'out.jpg');
      final info = await ImageProcessingService().crop(source, [0, 0, 1, 0, 1, 1, 0, 1], out);
      expect(info.width, 120);
      expect(info.height, 80);
      expect(File(out).readAsBytesSync(), File(source).readAsBytesSync(), reason: 'not decoded, resampled or compressed again');
    });

    test('a real crop still cuts, and keeps its size', () async {
      final source = photo();
      final out = p.join(dir.path, 'cut.jpg');
      final info = await ImageProcessingService().crop(source, [0.25, 0.25, 0.75, 0.25, 0.75, 0.75, 0.25, 0.75], out);
      expect(info.width, lessThan(120));
      expect(info.height, lessThan(80));
      expect(File(out).readAsBytesSync(), isNot(File(source).readAsBytesSync()));
    });

    test('a crop a hair inside the edges still counts as the whole picture', () async {
      final source = photo();
      final out = p.join(dir.path, 'edge.jpg');
      await ImageProcessingService().crop(source, [0.001, 0.001, 0.999, 0.001, 0.999, 0.999, 0.001, 0.999], out);
      expect(File(out).readAsBytesSync(), File(source).readAsBytesSync());
    });
  });

  group('settings', () {
    test('new installs start with the original look and the wide 4K camera', () {
      const s = AppSettings();
      expect(s.defaultFilter, ScanFilter.original);
      expect(s.cameraQuality, CameraQuality.high);
    });

    test('an install that still has the old colour filter and 4K camera is moved to the untouched defaults once', () async {
      SharedPreferences.setMockInitialValues({'default_filter': 'magicColor', 'camera_quality': 'high'});
      final repo = SettingsRepositoryImpl();
      final first = await repo.load();
      expect(first.defaultFilter, ScanFilter.original);
      expect(first.cameraQuality, CameraQuality.high);

      // A choice made afterwards is respected from then on.
      await repo.save(first.copyWith(defaultFilter: ScanFilter.documentBw, cameraQuality: CameraQuality.standard));
      final again = await repo.load();
      expect(again.defaultFilter, ScanFilter.documentBw);
      expect(again.cameraQuality, CameraQuality.standard);
    });

    test('an install already on Full sensor is moved to Wide 4K once, and a later choice stays', () async {
      SharedPreferences.setMockInitialValues({'photo_defaults_original': true, 'camera_quality': 'maximum'});
      final repo = SettingsRepositoryImpl();
      final first = await repo.load();
      expect(first.cameraQuality, CameraQuality.high);

      await repo.save(first.copyWith(cameraQuality: CameraQuality.maximum));
      expect((await repo.load()).cameraQuality, CameraQuality.maximum);
    });

    test('other settings survive the move', () async {
      SharedPreferences.setMockInitialValues({'default_filter': 'magicColor', 'auto_capture': false, 'ocr_script': 'devanagari'});
      final s = await SettingsRepositoryImpl().load();
      expect(s.autoCapture, isFalse);
      expect(s.ocrScript.name, 'devanagari');
    });
  });

  group('scan modes', () {
    test('receipt, card, ID and table finish by themselves; only card and ID have two sides', () {
      expect(ScanMode.values.where((m) => m.finishesItself), [ScanMode.receipt, ScanMode.card, ScanMode.id, ScanMode.table]);
      expect(ScanMode.values.where((m) => m.twoSided), [ScanMode.card, ScanMode.id]);
      expect(ScanMode.document.finishesItself, isFalse);
    });

    test('the viewfinder asks for the back after the front, in the mode\'s own words', () {
      expect(ScanMode.card.hintFor(0), 'Fit the card inside the frame');
      expect(ScanMode.card.hintFor(1), 'Now the back of the card');
      expect(ScanMode.id.hintFor(1), 'Now the back of the id');
      expect(ScanMode.receipt.hintFor(1), ScanMode.receipt.hint, reason: 'one-sided');
      expect(ScanMode.document.hintFor(3), ScanMode.document.hint);
    });

    test('a plain scan without an outline starts from the whole picture', () {
      expect(ScanMode.document.pickQuad(null, 0.5), Quad.fullFrame);
      expect(ScanMode.receipt.pickQuad(null, 0.75), Quad.fullFrame);
    });

    test('a detected outline is kept in a plain scan', () {
      const detected = Quad(NormPoint(0.1, 0.1), NormPoint(0.9, 0.12), NormPoint(0.88, 0.9), NormPoint(0.12, 0.88));
      expect(ScanMode.document.pickQuad(detected, 0.5), detected);
    });

    test('in a card mode a card-shaped outline inside the frame area is trusted', () {
      final guide = ScanMode.card.guideQuad(0.75)!;
      expect(ScanMode.card.pickQuad(guide, 0.75), guide);
    });

    test('in a card mode an outline of the wrong size or shape is replaced by the viewfinder frame', () {
      final guide = ScanMode.id.guideQuad(0.5625)!;
      const whole = Quad.fullFrame;
      const tall = Quad(NormPoint(0.3, 0.1), NormPoint(0.6, 0.1), NormPoint(0.6, 0.9), NormPoint(0.3, 0.9));
      const bowTie = Quad(NormPoint(0.1, 0.3), NormPoint(0.9, 0.7), NormPoint(0.9, 0.3), NormPoint(0.1, 0.7));
      expect(ScanMode.id.pickQuad(whole, 0.5625), guide);
      expect(ScanMode.id.pickQuad(tall, 0.5625), guide);
      expect(ScanMode.id.pickQuad(bowTie, 0.5625), guide);
      expect(ScanMode.id.pickQuad(null, 0.5625), guide);
    });

    test('a card held upright is accepted too', () {
      // 5.4 x 8.6 cm card standing on a 3:4 picture.
      const upright = Quad(NormPoint(0.3, 0.2), NormPoint(0.3 + 0.28, 0.2), NormPoint(0.3 + 0.28, 0.2 + 0.58), NormPoint(0.3, 0.2 + 0.58));
      final guide = ScanMode.id.guideQuad(0.75)!;
      final picked = ScanMode.id.pickQuad(upright, 0.75);
      expect(picked == upright || picked == guide, isTrue);
    });
  });

  group('zoom buttons', () {
    test('a phone with an ultra-wide lens offers it first, then 1x and the usual steps up to its limit', () {
      expect(zoomStops(0.6, 8), [0.6, 1.0, 2.0, 3.0, 5.0]);
      expect(zoomStops(0.5, 10), [0.5, 1.0, 2.0, 3.0, 5.0, 10.0]);
    });

    test('a camera without a wide end starts at 1x', () {
      expect(zoomStops(1, 4), [1.0, 2.0, 3.0]);
    });

    test('a camera that cannot zoom shows no buttons', () {
      expect(zoomStops(1, 1), isEmpty);
      expect(zoomStops(1, 1.2), isEmpty);
    });

    test('an odd minimum is rounded up so the button never asks for less than the camera can do', () {
      expect(zoomStops(0.57, 5).first, 0.6);
    });
  });
}

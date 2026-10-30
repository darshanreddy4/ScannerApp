import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/photo_tools/data/photo_metadata.dart';

img.Image _picture({bool gps = false, bool camera = false, int? orientation, bool software = false}) {
  final image = img.Image(width: 64, height: 48, numChannels: 3);
  for (final px in image) {
    px
      ..r = px.x * 4
      ..g = px.y * 5
      ..b = 120;
  }
  if (gps) image.exif.gpsIfd.setGpsLocation(latitude: 18.52, longitude: 73.85);
  if (camera) {
    image.exif.imageIfd.make = 'Google';
    image.exif.imageIfd.model = 'Pixel 8';
    image.exif.exifIfd.data[0x9003] = img.IfdValueAscii('2026:03:07 10:15:00');
  }
  if (software) image.exif.imageIfd.software = 'Photo Editor 3.1';
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return image;
}

Uint8List _jpeg(img.Image image) => Uint8List.fromList(img.encodeJpg(image, quality: 90));

/// Pixel data of the picture itself, to prove cleaning does not touch it.
List<int> _pixels(Uint8List jpeg) => img.decodeJpg(jpeg)!.getBytes();

void main() {
  late Directory dir;
  const cleaner = PhotoMetadataCleaner();

  setUp(() => dir = Directory.systemTemp.createTempSync('sv_meta'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) => (File(p.join(dir.path, name))..writeAsBytesSync(bytes)).path;

  group('inspect', () {
    test('finds the location, camera, date and editing program', () {
      final info = inspectMetadata(_jpeg(_picture(gps: true, camera: true, software: true)));
      expect(info.hasLocation, isTrue);
      expect(info.camera, 'Google Pixel 8');
      expect(info.takenAt, contains('2026:03:07'));
      expect(info.software, 'Photo Editor 3.1');
      expect(info.hiddenBytes, greaterThan(50));
      expect(info.isClean, isFalse);
    });

    test('a photo without private data is clean', () {
      final info = inspectMetadata(_jpeg(_picture()));
      expect(info.hasLocation, isFalse);
      expect(info.camera, isNull);
      expect(info.isClean, isTrue);
    });

    test('only a camera name is reported as that, not as a location', () {
      final info = inspectMetadata(_jpeg(_picture(camera: true)));
      expect(info.hasLocation, isFalse);
      expect(info.camera, 'Google Pixel 8');
    });

    test('PNG text chunks count as hidden data', () {
      final png = img.encodePng(_picture(), level: 6);
      final withText = _addPngText(Uint8List.fromList(png), 'Author', 'Asha Traders, Pune');
      final info = inspectMetadata(withText);
      expect(info.isPng, isTrue);
      expect(info.hasOtherData, isTrue);
      expect(info.hiddenBytes, greaterThan(10));
      expect(inspectMetadata(Uint8List.fromList(png)).isClean, isTrue);
    });

    test('other file types are refused with a clear message', () {
      expect(
        () => inspectMetadata(Uint8List.fromList(List.filled(100, 3))),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Only JPG and PNG'))),
      );
    });
  });

  group('JPEG cleaning', () {
    test('removes the location, camera, date and program', () {
      final original = _jpeg(_picture(gps: true, camera: true, software: true));
      final cleaned = stripMetadata(original);
      final exif = img.decodeJpgExif(cleaned);
      expect(exif == null || exif.isEmpty, isTrue, reason: 'no EXIF left');
      final again = inspectMetadata(cleaned);
      expect(again.isClean, isTrue);
      expect(cleaned.length, lessThan(original.length));
    });

    test('the picture is exactly the same, because nothing is re-compressed', () {
      final original = _jpeg(_picture(gps: true, camera: true));
      final cleaned = stripMetadata(original);
      expect(_pixels(cleaned), _pixels(original));
      expect(img.decodeJpg(cleaned)!.width, 64);
    });

    test('the result is a valid JPEG that other readers can open', () {
      final cleaned = stripMetadata(_jpeg(_picture(gps: true)));
      expect(cleaned.sublist(0, 2), [0xFF, 0xD8]);
      expect(cleaned.sublist(cleaned.length - 2), [0xFF, 0xD9]);
      expect(img.decodeImage(cleaned), isNotNull);
    });

    test('a rotated photo keeps its rotation flag and nothing else', () {
      final original = _jpeg(_picture(gps: true, camera: true, orientation: 6));
      final cleaned = stripMetadata(original);
      final exif = img.decodeJpgExif(cleaned)!;
      expect(exif.imageIfd.orientation, 6);
      expect(exif.gpsIfd.data, isEmpty);
      expect(exif.imageIfd.make, isNull);
      expect(img.decodeJpg(cleaned)!.width, 48, reason: 'still shown turned upright, as before');
      expect(_pixels(cleaned), _pixels(original));
    });

    test('an upright photo gets no rotation flag at all', () {
      final cleaned = stripMetadata(_jpeg(_picture(gps: true, orientation: 1)));
      final exif = img.decodeJpgExif(cleaned);
      expect(exif == null || exif.isEmpty, isTrue);
    });

    test('comments and extra blocks are dropped, but the colour profile is kept', () {
      final base = _jpeg(_picture());
      final withExtras = _insertAfterSoi(base, [
        ..._segment(0xFE, 'secret comment'.codeUnits),
        ..._segment(0xED, 'Photoshop 3.0 private'.codeUnits),
        ..._segment(0xE2, [...'ICC_PROFILE'.codeUnits, 0, 1, 1, 7, 7, 7]),
      ]);
      final cleaned = stripMetadata(withExtras);
      final text = String.fromCharCodes(cleaned);
      expect(text, isNot(contains('secret comment')));
      expect(text, isNot(contains('Photoshop 3.0')));
      expect(text, contains('ICC_PROFILE'));
      expect(img.decodeImage(cleaned), isNotNull);
    });

    test('data after the end of the picture is dropped', () {
      final original = _jpeg(_picture());
      final withTrailer = Uint8List.fromList([...original, ...'GPS: 18.52,73.85 hidden trailer'.codeUnits]);
      final cleaned = stripMetadata(withTrailer);
      expect(String.fromCharCodes(cleaned), isNot(contains('hidden trailer')));
      expect(img.decodeImage(cleaned), isNotNull);
      expect(inspectMetadata(withTrailer).hiddenBytes, greaterThan(20));
    });

    test('cleaning twice changes nothing more', () {
      final once = stripMetadata(_jpeg(_picture(gps: true, camera: true)));
      expect(stripMetadata(once), once);
    });

    test('a damaged file does not crash', () {
      final original = _jpeg(_picture(gps: true));
      final cut = original.sublist(0, original.length ~/ 2);
      expect(() => stripMetadata(cut), returnsNormally);
    });
  });

  group('PNG cleaning', () {
    test('drops text and time chunks and keeps the picture', () {
      final png = Uint8List.fromList(img.encodePng(_picture(), level: 6));
      final dirty = _addPngText(png, 'Comment', 'private note');
      final cleaned = stripMetadata(dirty);
      expect(String.fromCharCodes(cleaned), isNot(contains('private note')));
      final a = img.decodePng(png)!, b = img.decodePng(cleaned)!;
      expect(b.getBytes(), a.getBytes());
    });

    test('keeps transparency information', () {
      final image = img.Image(width: 8, height: 8, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(10, 20, 30, 77));
      final cleaned = stripMetadata(_addPngText(Uint8List.fromList(img.encodePng(image)), 'k', 'v'));
      expect(img.decodePng(cleaned)!.getPixel(0, 0).a, 77);
    });
  });

  group('cleaner service', () {
    test('writes a cleaned copy and reports what was removed', () async {
      final source = write('a.jpg', _jpeg(_picture(gps: true, camera: true)));
      final out = p.join(dir.path, 'clean.jpg');
      final result = (await cleaner.clean(sourcePath: source, outputPath: out)).valueOrNull!;
      expect(result.path, out);
      expect(result.removedBytes, greaterThan(50));
      expect(File(out).lengthSync(), result.bytes);
      expect((await cleaner.inspect(out)).valueOrNull!.isClean, isTrue);
      expect(File(source).lengthSync(), result.bytes + result.removedBytes, reason: 'the original is left alone');
    });

    test('a file that is not a photo gives a readable failure', () async {
      final bad = write('b.jpg', List.filled(100, 9));
      final result = await cleaner.inspect(bad);
      expect(result.failureOrNull, isA<ExportFailure>());
      expect(result.failureOrNull!.message, contains('Only JPG and PNG'));
      final clean = await cleaner.clean(sourcePath: bad, outputPath: p.join(dir.path, 'x.jpg'));
      expect(clean.failureOrNull, isA<ExportFailure>());
    });
  });
}

List<int> _segment(int marker, List<int> body) {
  final length = body.length + 2;
  return [0xFF, marker, length >> 8, length & 0xFF, ...body];
}

Uint8List _insertAfterSoi(Uint8List jpeg, List<int> segments) => Uint8List.fromList([...jpeg.sublist(0, 2), ...segments, ...jpeg.sublist(2)]);

/// Adds a tEXt chunk before IEND (the checksum is not needed by the readers used here).
Uint8List _addPngText(Uint8List png, String key, String value) {
  final iend = png.length - 12;
  final data = [...key.codeUnits, 0, ...value.codeUnits];
  final chunk = [(data.length >> 24) & 255, (data.length >> 16) & 255, (data.length >> 8) & 255, data.length & 255, ...'tEXt'.codeUnits, ...data, 0, 0, 0, 0];
  return Uint8List.fromList([...png.sublist(0, iend), ...chunk, ...png.sublist(iend)]);
}

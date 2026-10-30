import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/features/photo_tools/data/image_compressor.dart';
import 'package:doculoom/features/photo_tools/domain/photo_compressor.dart';

/// A smooth picture with grain, which compresses like a real photo.
img.Image _photo(int w, int h, {int seed = 1}) {
  final random = Random(seed);
  final image = img.Image(width: w, height: h);
  for (final px in image) {
    final noise = random.nextInt(40) - 20;
    px
      ..r = ((px.x * 255 ~/ w) + noise).clamp(0, 255)
      ..g = ((px.y * 255 ~/ h) + noise).clamp(0, 255)
      ..b = (((px.x + px.y) * 255 ~/ (w + h)) + noise).clamp(0, 255);
  }
  return image;
}

void main() {
  late Directory dir;
  const compressor = ImageCompressor();

  setUp(() => dir = Directory.systemTemp.createTempSync('sv_compress'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final f = File(p.join(dir.path, name))..writeAsBytesSync(bytes);
    return f.path;
  }

  Future<CompressedPhoto> run(String source, CompressOptions options, {String out = 'out.jpg'}) async {
    final result = await compressor.compress(sourcePath: source, outputPath: p.join(dir.path, out), options: options);
    return result.valueOrNull!;
  }

  test('a target that needs only lower quality keeps the full pixel size', () async {
    final source = write('a.jpg', img.encodeJpg(_photo(1200, 900), quality: 95));
    final original = File(source).lengthSync();
    final target = (original * 0.6).round();

    final r = await run(source, CompressOptions(targetBytes: target));

    expect(r.metTarget, isTrue);
    expect(r.bytes, lessThanOrEqualTo(target));
    expect(r.bytes, greaterThan(target * 0.7), reason: 'it should use the allowed size, not squeeze far below it');
    expect((r.width, r.height), (1200, 900));
    expect(r.quality, greaterThanOrEqualTo(60));
    final decoded = img.decodeJpg(File(r.path).readAsBytesSync())!;
    expect((decoded.width, decoded.height), (1200, 900));
  });

  test('a small limit shrinks the picture and still fits', () async {
    final source = write('b.jpg', img.encodeJpg(_photo(2000, 1500), quality: 95));
    for (final kb in [20, 50, 100]) {
      final r = await run(source, CompressOptions(targetBytes: kb * 1024), out: 'o$kb.jpg');
      expect(r.metTarget, isTrue, reason: '$kb kB');
      expect(r.bytes, lessThanOrEqualTo(kb * 1024), reason: '$kb kB');
      expect(File(r.path).lengthSync(), r.bytes);
      expect(r.width, lessThan(2000));
      expect(r.width / r.height, closeTo(2000 / 1500, 0.02), reason: 'the shape is kept');
      expect(img.decodeJpg(File(r.path).readAsBytesSync()), isNotNull);
    }
  });

  test('keeping the pixel size lowers only the quality', () async {
    final source = write('keep.jpg', img.encodeJpg(_photo(413, 531), quality: 98));
    final original = File(source).lengthSync();
    final r = await run(source, CompressOptions(targetBytes: (original * 0.5).round(), keepPixelSize: true));
    expect((r.width, r.height), (413, 531));
    expect(r.metTarget, isTrue);
    expect(r.quality, lessThan(95));
  });

  test('keeping the pixel size reports a missed limit instead of shrinking', () async {
    final source = write('keep2.jpg', img.encodeJpg(_photo(413, 531)));
    final r = await run(source, const CompressOptions(targetBytes: 2000, keepPixelSize: true));
    expect((r.width, r.height), (413, 531));
    expect(r.metTarget, isFalse);
    expect(r.quality, 25);
  });

  test('a bigger limit gives a bigger, sharper result', () async {
    final source = write('c.jpg', img.encodeJpg(_photo(2000, 1500), quality: 95));
    final small = await run(source, const CompressOptions(targetBytes: 30 * 1024), out: 's.jpg');
    final large = await run(source, const CompressOptions(targetBytes: 150 * 1024), out: 'l.jpg');
    expect(large.width, greaterThanOrEqualTo(small.width));
    expect(large.bytes, greaterThan(small.bytes));
  });

  test('a photo already under the limit is left byte for byte', () async {
    final bytes = img.encodeJpg(_photo(300, 200), quality: 80);
    final source = write('d.jpg', bytes);
    final r = await run(source, CompressOptions(targetBytes: bytes.length + 5000));
    expect(r.metTarget, isTrue);
    expect(File(r.path).readAsBytesSync(), bytes);
  });

  test('resizing alone needs no size limit', () async {
    final source = write('e.jpg', img.encodeJpg(_photo(1600, 800)));
    final r = await run(source, const CompressOptions(maxSide: 800));
    expect((r.width, r.height), (800, 400));
    expect(r.metTarget, isTrue);
  });

  test('a portrait photo is resized by its longest side', () async {
    final source = write('f.jpg', img.encodeJpg(_photo(600, 1200)));
    final r = await run(source, const CompressOptions(maxSide: 600));
    expect((r.width, r.height), (300, 600));
  });

  test('a photo is never enlarged', () async {
    final source = write('g.jpg', img.encodeJpg(_photo(400, 300)));
    final r = await run(source, const CompressOptions(maxSide: 2000));
    expect((r.width, r.height), (400, 300));
  });

  test('transparent PNG becomes JPG on a white background', () async {
    final png = img.Image(width: 60, height: 40, numChannels: 4);
    img.fill(png, color: img.ColorRgba8(255, 0, 0, 0));
    final source = write('h.png', img.encodePng(png));
    final r = await run(source, const CompressOptions(maxSide: 60));
    final out = img.decodeJpg(File(r.path).readAsBytesSync())!;
    final pixel = out.getPixel(5, 5);
    expect([pixel.r, pixel.g, pixel.b].every((c) => c > 240), isTrue, reason: 'fully transparent turns white');
  });

  test('PNG output reaches a size limit by shrinking, and stays a PNG', () async {
    final source = write('i.jpg', img.encodeJpg(_photo(800, 600)));
    final r = await run(
      source,
      const CompressOptions(targetBytes: 80 * 1024, format: PhotoFormat.png),
      out: 'o.png',
    );
    expect(r.metTarget, isTrue);
    expect(r.bytes, lessThanOrEqualTo(80 * 1024));
    expect(r.quality, isNull);
    expect(img.decodePng(File(r.path).readAsBytesSync()), isNotNull);
    expect(r.width, lessThan(800));
  });

  test('an impossible limit gives the smallest usable picture and says it was missed', () async {
    final source = write('j.jpg', img.encodeJpg(_photo(1000, 800)));
    final r = await run(source, const CompressOptions(targetBytes: 300));
    expect(r.metTarget, isFalse);
    expect(r.bytes, greaterThan(300));
    expect(r.width, greaterThanOrEqualTo(150));
    expect(File(r.path).existsSync(), isTrue);
  });

  test('a camera rotation flag is applied to the pixels', () async {
    final photo = _photo(300, 200)..exif.imageIfd.orientation = 6;
    final source = write('k.jpg', img.encodeJpg(photo));
    final bytes = File(source).lengthSync();
    final r = await run(source, CompressOptions(targetBytes: bytes + 10000));
    expect((r.width, r.height), (200, 300), reason: 'rotated upright');
    expect(img.decodeJpgExif(File(r.path).readAsBytesSync())?.imageIfd.orientation ?? 1, 1);
  });

  test('a file that is not a picture fails with a readable message', () async {
    final source = write('l.jpg', List.filled(100, 7));
    final result = await compressor.compress(sourcePath: source, outputPath: p.join(dir.path, 'x.jpg'), options: const CompressOptions());
    expect(result.failureOrNull, isA<ExportFailure>());
    expect(result.failureOrNull!.message, contains('could not be compressed'));
  });
}

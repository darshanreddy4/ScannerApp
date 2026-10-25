import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/features/pdf_tools/data/pdf_compress_processor.dart';
import 'package:scanvault/features/pdf_tools/domain/pdf_compressor.dart';

void main() {
  late Directory dir;
  late int importCalls;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_pdfc');
    importCalls = 0;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// Pages that look like scanned paper: noisy, so quality and size settings change the file size a lot.
  Future<List<String>> pages(String _, {int count = 3}) async {
    importCalls++;
    final rnd = math.Random(4);
    final out = <String>[];
    for (var n = 0; n < count; n++) {
      final image = img.Image(width: 1400, height: 1900, numChannels: 3);
      for (final px in image) {
        final v = 200 + rnd.nextInt(55);
        px
          ..r = v
          ..g = v - rnd.nextInt(20)
          ..b = v - rnd.nextInt(40);
      }
      final path = p.join(dir.path, 'page$n.jpg');
      File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
      out.add(path);
    }
    return out;
  }

  String source({int bytes = 6 * 1024 * 1024}) => (File(p.join(dir.path, 'in.pdf'))..writeAsBytesSync(List.filled(bytes, 7))).path;

  Future<(CompressedPdf?, Failure?, List<int>)> run(PdfCompressProcessor processor, PdfCompressOptions options, {String? input}) async {
    final attempts = <int>[];
    final result = await processor.compress(
      sourcePath: input ?? source(),
      outputPath: p.join(dir.path, 'out.pdf'),
      options: options,
      onProgress: (a, total) => attempts.add(a),
    );
    return (result.valueOrNull, result.failureOrNull, attempts);
  }

  test('without a limit it uses one balanced setting', () async {
    final (r, f, attempts) = await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions());
    expect(f, isNull);
    expect(attempts, [1]);
    expect(r!.unchanged, isFalse);
    expect(r.pages, 3);
    expect(r.bytes, lessThan(r.originalBytes));
    expect(File(r.path).readAsBytesSync().sublist(0, 4), '%PDF'.codeUnits);
    expect(File(r.path).lengthSync(), r.bytes);
  });

  test('stops at the first setting that fits the limit', () async {
    const target = 5 * 1024 * 1024;
    final (r, _, attempts) = await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions(targetBytes: target));
    expect(attempts, [1]);
    expect(r!.metTarget, isTrue);
    expect(r.bytes, lessThanOrEqualTo(target));
  });

  test('lowers the quality step by step until the limit is met', () async {
    final probe = (await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions())).$1!;
    final target = (probe.bytes * 0.5).round();
    final (r, _, attempts) = await run(PdfCompressProcessor(pdfToImages: pages), PdfCompressOptions(targetBytes: target));
    expect(attempts.length, greaterThan(1));
    expect(r!.metTarget, isTrue);
    expect(r.bytes, lessThanOrEqualTo(target));
    expect(r.savedBytes, r.originalBytes - r.bytes);
  });

  test('when the limit is out of reach the smallest result is returned and flagged', () async {
    final (r, f, attempts) = await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions(targetBytes: 3 * 1024));
    expect(f, isNull);
    expect(attempts.length, PdfCompressProcessor.levels.length);
    expect(r!.metTarget, isFalse);
    expect(r.unchanged, isFalse);
    expect(r.bytes, greaterThan(3 * 1024));
    expect(r.bytes, lessThan(r.originalBytes));
  });

  test('a file that already fits is left alone without reading it', () async {
    final input = source(bytes: 50 * 1024);
    final (r, _, attempts) = await run(
      PdfCompressProcessor(pdfToImages: pages),
      PdfCompressOptions(targetBytes: 100 * 1024),
      input: input,
    );
    expect(r!.unchanged, isTrue);
    expect(r.metTarget, isTrue);
    expect(r.path, input);
    expect(attempts, isEmpty);
    expect(importCalls, 0);
  });

  test('a file that is already more compact than a redrawn one is kept as it is', () async {
    final input = source(bytes: 4 * 1024);
    final (r, _, _) = await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions(), input: input);
    expect(r!.unchanged, isTrue);
    expect(r.path, input);
    expect(r.bytes, 4 * 1024);
    expect(File(p.join(dir.path, 'out.pdf')).existsSync(), isFalse);
  });

  test('temporary work files are removed', () async {
    await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions(targetBytes: 20 * 1024));
    expect(dir.listSync().where((e) => p.basename(e.path).startsWith('.pdf_work')), isEmpty);
  });

  test('a missing file gives a clear failure', () async {
    final (r, f, _) = await run(PdfCompressProcessor(pdfToImages: pages), const PdfCompressOptions(), input: p.join(dir.path, 'nope.pdf'));
    expect(r, isNull);
    expect(f!.message, contains('could not be found'));
  });

  test('a PDF without readable pages gives a clear failure', () async {
    final (r, f, _) = await run(PdfCompressProcessor(pdfToImages: (_) async => const []), const PdfCompressOptions());
    expect(r, isNull);
    expect(f!.message, contains('Nothing could be read'));
  });

  test('an import failure such as a password is passed on unchanged', () async {
    final (r, f, _) = await run(
      PdfCompressProcessor(pdfToImages: (_) async => throw const ImportFailure('This file is password protected.')),
      const PdfCompressOptions(),
    );
    expect(r, isNull);
    expect(f!.message, 'This file is password protected.');
  });

  test('damaged page pictures are reported instead of crashing', () async {
    final bad = File(p.join(dir.path, 'bad.jpg'))..writeAsBytesSync([1, 2, 3]);
    final (r, f, _) = await run(PdfCompressProcessor(pdfToImages: (_) async => [bad.path]), const PdfCompressOptions());
    expect(r, isNull);
    expect(f, isA<ExportFailure>());
  });
}

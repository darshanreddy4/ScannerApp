import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/features/pdf_tools/data/pdf_pages_processor.dart';
import 'package:scanvault/features/pdf_tools/domain/pdf_pages.dart';
import 'package:scanvault/features/photo_tools/data/watermark_stamp.dart';
import 'package:scanvault/features/photo_tools/domain/watermark.dart';

class _SpyRenderer extends WatermarkStampRenderer {
  _SpyRenderer();
  final texts = <String>[];

  @override
  Future<Stamp?> render({required WatermarkStyle style, required String text, required int shortSide}) {
    texts.add(text);
    return super.render(style: style, text: text, shortSide: shortSide);
  }
}

void main() {
  group('page ranges', () {
    test('reads pages, ranges and open ends in the order typed', () {
      final r = PageRanges.parse('1-3, 5, 8-', 9);
      expect(r.ok, isTrue);
      expect(r.groups, [
        [0, 1, 2],
        [4],
        [7, 8],
      ]);
      expect(r.pages, [0, 1, 2, 4, 7, 8]);
    });

    test('keeps the typed order and drops repeats', () {
      expect(PageRanges.parse('5, 1-2, 2', 6).pages, [4, 0, 1]);
    });

    test('accepts spaces, semicolons and an en dash', () {
      expect(PageRanges.parse(' 2 – 3 ; 6 ', 6).pages, [1, 2, 5]);
    });

    test('explains each kind of mistake', () {
      expect(PageRanges.parse('', 5).error, contains('Type the pages'));
      expect(PageRanges.parse('7', 5).error, 'Page 7 does not exist. This PDF has 5 pages.');
      expect(PageRanges.parse('2-9', 5).error, contains('Page 9 does not exist'));
      expect(PageRanges.parse('4-2', 5).error, contains('goes backwards'));
      expect(PageRanges.parse('0', 5).error, 'Pages start at 1.');
      expect(PageRanges.parse('a-b', 5).error, contains('is not a page or a range'));
      expect(PageRanges.parse('3', 1).error, 'Page 3 does not exist. This PDF has 1 page.');
      expect(PageRanges.parse(',,', 5).ok, isFalse);
    });

    test('labels pages compactly', () {
      expect(PageRanges.label([0, 1, 2, 4, 7, 8]), '1-3_5_8-9');
      expect(PageRanges.label([3]), '4');
      expect(PageRanges.label([0, 2], separator: ', '), '1, 3');
      expect(PageRanges.label(const []), '');
    });

    test('splits into single pages or equal parts', () {
      expect(PageRanges.splitEach(3), [
        [0],
        [1],
        [2],
      ]);
      expect(PageRanges.splitEvery(2, 5), [
        [0, 1],
        [2, 3],
        [4],
      ]);
      expect(PageRanges.splitEvery(0, 2), [
        [0],
        [1],
      ]);
      expect(PageRanges.splitEvery(10, 3), [
        [0, 1, 2],
      ]);
    });
  });

  group('page numbers', () {
    test('each style words the number', () {
      expect(PageNumberStyle.none.text(2, 5), '');
      expect(PageNumberStyle.plain.text(2, 5), '2');
      expect(PageNumberStyle.pageOf.text(2, 5), 'Page 2 of 5');
      expect(PageNumberStyle.slash.text(2, 5), '2 / 5');
    });

    test('marks are empty only when nothing is asked for', () {
      expect(const PageMarks().isEmpty, isTrue);
      expect(const PageMarks(header: '  ').isEmpty, isTrue);
      expect(const PageMarks(footer: 'Draft').isEmpty, isFalse);
      expect(const PageMarks(numbers: PageNumberStyle.plain).isEmpty, isFalse);
      expect(const PageMarks().copyWith(header: 'H'), const PageMarks(header: 'H'));
    });
  });

  group('processor', () {
    late Directory dir;
    late _SpyRenderer renderer;
    late PdfPagesProcessor processor;
    late OpenedPdf opened;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sv_pages');
      renderer = _SpyRenderer();
      final pages = <String>[];
      for (var i = 0; i < 4; i++) {
        final image = img.Image(width: 300, height: 400, numChannels: 3);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        final path = p.join(dir.path, 'src$i.jpg');
        File(path).writeAsBytesSync(img.encodeJpg(image, quality: 90));
        pages.add(path);
      }
      File(p.join(dir.path, 'in.pdf')).writeAsBytesSync([1]);
      processor = PdfPagesProcessor(pdfToImages: (_) async => pages, renderer: renderer);
      opened = (await processor.open(p.join(dir.path, 'in.pdf'))).valueOrNull!;
    });
    tearDown(() => dir.deleteSync(recursive: true));

    int pageCount(String path) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(String.fromCharCodes(File(path).readAsBytesSync())).length;

    Future<List<PdfPart>> build(
      List<PartRequest> parts, {
      Map<int, int> rotations = const {},
      PageMarks marks = const PageMarks(),
      void Function(int, int)? onProgress,
    }) async {
      final r = await processor.build(
        source: opened,
        parts: parts,
        rotations: rotations,
        marks: marks,
        outputDir: p.join(dir.path, 'out'),
        onProgress: onProgress,
      );
      expect(r.failureOrNull, isNull);
      return r.valueOrNull!;
    }

    test('opening reports the pages and the name', () {
      expect(opened.name, 'in');
      expect(opened.pages.length, 4);
    });

    test('opening a missing file or an empty PDF fails clearly', () async {
      expect((await processor.open(p.join(dir.path, 'no.pdf'))).failureOrNull!.message, contains('could not be found'));
      final empty = PdfPagesProcessor(pdfToImages: (_) async => const []);
      expect((await empty.open(p.join(dir.path, 'in.pdf'))).failureOrNull!.message, contains('Nothing could be read'));
      final locked = PdfPagesProcessor(pdfToImages: (_) async => throw const ImportFailure('This file is password protected.'));
      expect((await locked.open(p.join(dir.path, 'in.pdf'))).failureOrNull!.message, 'This file is password protected.');
    });

    test('creates a PDF from the chosen pages only', () async {
      final parts = await build([
        const PartRequest(fileName: 'two.pdf', pages: [3, 1]),
      ]);
      expect(parts.single.pages, 2);
      expect(parts.single.name, 'two.pdf');
      expect(parts.single.bytes, File(parts.single.path).lengthSync());
      expect(pageCount(parts.single.path), 2);
    });

    test('creates one file per request and reports progress', () async {
      final progress = <int>[];
      final parts = await build([
        const PartRequest(fileName: 'a.pdf', pages: [0, 1]),
        const PartRequest(fileName: 'b.pdf', pages: [2]),
        const PartRequest(fileName: 'c.pdf', pages: [3]),
      ], onProgress: (d, t) => progress.add(d * 100 + t));
      expect(parts.map((e) => e.pages), [2, 1, 1]);
      expect(parts.map((e) => pageCount(e.path)), [2, 1, 1]);
      expect(progress, [104, 204, 304, 404]);
    });

    test('a turned page changes the page shape', () async {
      String box(String path) => RegExp(r'/MediaBox\s*\[([^\]]*)\]').firstMatch(String.fromCharCodes(File(path).readAsBytesSync()))!.group(1)!;
      List<double> dims(String path) => box(path).trim().split(RegExp(r'\s+')).map(double.parse).toList();
      final parts = await build(
        [
          const PartRequest(fileName: 'turn.pdf', pages: [0]),
        ],
        rotations: {0: 1},
      );
      final d = dims(parts.single.path);
      expect(d[2] - d[0], greaterThan(d[3] - d[1]), reason: 'portrait became landscape');
      final upright = await build([
        const PartRequest(fileName: 'up.pdf', pages: [0]),
      ]);
      final u = dims(upright.single.path);
      expect(u[2] - u[0], lessThan(u[3] - u[1]));
    });

    test('page numbers follow the new file, not the original', () async {
      await build([
        const PartRequest(fileName: 'n.pdf', pages: [2, 3]),
      ], marks: const PageMarks(numbers: PageNumberStyle.pageOf));
      expect(renderer.texts, ['Page 1 of 2', 'Page 2 of 2']);
    });

    test('header, footer and numbers are all printed, and a cover page can stay clean', () async {
      await build([
        const PartRequest(fileName: 'h.pdf', pages: [0, 1]),
      ], marks: const PageMarks(numbers: PageNumberStyle.plain, header: 'Asha Traders', footer: 'Confidential', skipFirst: true));
      expect(renderer.texts, ['Asha Traders', '2', 'Confidential']);
    });

    test('a number at the bottom centre joins the footer instead of overlapping it', () async {
      await build([
        const PartRequest(fileName: 'm.pdf', pages: [0]),
      ], marks: const PageMarks(numbers: PageNumberStyle.plain, position: NumberPosition.bottomCenter, footer: 'Draft'));
      expect(renderer.texts, ['Draft\n1']);
    });

    test('the same words are drawn once for pages of the same size', () async {
      await build([
        const PartRequest(fileName: 'f.pdf', pages: [0, 1, 2, 3]),
      ], marks: const PageMarks(footer: 'Draft'));
      expect(renderer.texts, ['Draft']);
    });

    test('marks are drawn where asked and nowhere else', () async {
      final stamp = (await const WatermarkStampRenderer().render(
        style: const WatermarkStyle(layout: WatermarkLayout.single, opacity: 1, size: 0.05, rotation: 0, color: WatermarkColor.black, bold: false),
        text: 'Page 1 of 3',
        shortSide: 300,
      ))!;
      final out = p.join(dir.path, 'marked.jpg');
      composePage(opened.pages.first, out, 0, [PageMark(rgba: stamp.rgba, width: stamp.width, height: stamp.height, position: WatermarkPosition.bottomRight)]);
      final image = img.decodeJpg(File(out).readAsBytesSync())!;
      bool dark(int x0, int y0, int x1, int y1) {
        for (var y = y0; y < y1; y++) {
          for (var x = x0; x < x1; x++) {
            if (image.getPixel(x, y).r < 120) return true;
          }
        }
        return false;
      }

      expect(dark(150, 330, 300, 400), isTrue, reason: 'bottom right');
      expect(dark(0, 0, 300, 300), isFalse, reason: 'nowhere else');
      expect(dark(0, 300, 120, 400), isFalse, reason: 'not bottom left');
    });

    test('no marks and no turns embeds the original page untouched', () async {
      final parts = await build([
        const PartRequest(fileName: 'plain.pdf', pages: [0]),
      ]);
      expect(renderer.texts, isEmpty);
      expect(parts.single.bytes, greaterThan(100));
    });

    test('work files are removed', () async {
      await build(
        [
          const PartRequest(fileName: 'w.pdf', pages: [0]),
        ],
        rotations: {0: 2},
        marks: const PageMarks(footer: 'X'),
      );
      final leftovers = Directory(p.join(dir.path, 'out')).listSync().where((e) => p.basename(e.path).startsWith('.work'));
      expect(leftovers, isEmpty);
    });

    test('bad requests fail with a clear message', () async {
      Future<String?> fail(List<PartRequest> parts) async => (await processor.build(
        source: opened,
        parts: parts,
        rotations: const {},
        marks: const PageMarks(),
        outputDir: p.join(dir.path, 'out'),
      )).failureOrNull?.message;
      expect(await fail(const []), 'Choose at least one page.');
      expect(await fail(const [PartRequest(fileName: 'x.pdf', pages: [])]), 'Choose at least one page.');
      expect(
        await fail(const [
          PartRequest(fileName: 'x.pdf', pages: [9]),
        ]),
        'A chosen page is not in this PDF.',
      );
    });
  });
}

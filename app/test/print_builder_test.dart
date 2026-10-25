import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scanvault/features/export/data/document_builders.dart';
import 'package:scanvault/features/print/data/print_pdf_builder.dart';
import 'package:scanvault/features/print/domain/print_options.dart';

String _text(List<int> bytes) => String.fromCharCodes(bytes);

int _pageCount(String pdf) => RegExp(r'/Type\s*/Page\b').allMatches(pdf).length;

List<double> _mediaBox(String pdf) {
  final m = RegExp(r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(pdf)!;
  return [double.parse(m[3]!), double.parse(m[4]!)];
}

void main() {
  late Directory tmp;
  late List<PageSource> pages;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sv_print');
    pages = [];
    for (var i = 0; i < 5; i++) {
      // Page 4 is wide (landscape); the rest are tall.
      final wide = i == 3;
      final image = img.Image(width: wide ? 120 : 80, height: wide ? 80 : 120)..clear(img.ColorRgb8(30 * i, 120, 200));
      final f = File('${tmp.path}/p$i.jpg')..writeAsBytesSync(img.encodeJpg(image));
      pages.add(PageSource(path: f.path, width: image.width, height: image.height));
    }
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('PageRange.parse', () {
    test('empty means all pages', () => expect(PageRange.parse('', 4), [0, 1, 2, 3]));
    test('supports lists, ranges and open ranges', () {
      expect(PageRange.parse('1-3, 5', 6), [0, 1, 2, 4]);
      expect(PageRange.parse('4-', 6), [3, 4, 5]);
      expect(PageRange.parse('2', 6), [1]);
    });
    test('keeps the written order and drops duplicates', () => expect(PageRange.parse('3,1,3,2-3', 5), [2, 0, 1]));
    test('rejects invalid input', () {
      for (final bad in ['0', '3-1', '7', '1-9', 'a', '1,,2', '1-2-3', '-2']) {
        expect(PageRange.parse(bad, 6), isNull, reason: bad);
      }
    });
  });

  test('A4 portrait is 595 x 842 points and prints one page per sheet', () async {
    final pdf = _text(
      await buildPrintPdf(
        pages: pages,
        options: const PrintOptions(orientation: PrintOrientation.portrait),
      ),
    );
    expect(_pageCount(pdf), 5);
    final box = _mediaBox(pdf);
    expect(box[0], closeTo(595.3, 1));
    expect(box[1], closeTo(841.9, 1));
  });

  test('auto orientation turns a wide page sideways', () async {
    final pdf = _text(await buildPrintPdf(pages: [pages[3]], options: const PrintOptions()));
    final box = _mediaBox(pdf);
    expect(box[0], greaterThan(box[1]));
  });

  test('letter, legal and photo paper use their real sizes', () async {
    for (final (paper, w, h) in [(PaperSize.letter, 612.0, 792.0), (PaperSize.legal, 612.0, 1008.0), (PaperSize.photo, 288.0, 432.0)]) {
      final pdf = _text(
        await buildPrintPdf(
          pages: [pages[0]],
          options: PrintOptions(paper: paper, orientation: PrintOrientation.portrait),
        ),
      );
      final box = _mediaBox(pdf);
      expect(box[0], closeTo(w, 1), reason: paper.label);
      expect(box[1], closeTo(h, 1), reason: paper.label);
    }
  });

  test('page range selects only those pages', () async {
    final pdf = _text(
      await buildPrintPdf(
        pages: pages,
        options: const PrintOptions(pageRange: '2-3, 5'),
      ),
    );
    expect(_pageCount(pdf), 3);
  });

  test('copies repeat the whole job', () async {
    final pdf = _text(
      await buildPrintPdf(
        pages: pages,
        options: const PrintOptions(copies: 3, pageRange: '1-2'),
      ),
    );
    expect(_pageCount(pdf), 6);
  });

  test('2 and 4 pages per sheet reduce the number of sheets', () async {
    expect(_pageCount(_text(await buildPrintPdf(pages: pages, options: const PrintOptions(pagesPerSheet: 2)))), 3);
    expect(_pageCount(_text(await buildPrintPdf(pages: pages, options: const PrintOptions(pagesPerSheet: 4)))), 2);
  });

  test('black and white produces a different, valid file', () async {
    final color = await buildPrintPdf(pages: [pages[0]], options: const PrintOptions());
    final bw = await buildPrintPdf(pages: [pages[0]], options: const PrintOptions(color: false));
    expect(_pageCount(_text(bw)), 1);
    expect(bw, isNot(color));
  });

  test('fill mode and every margin setting build successfully', () async {
    for (final margin in PrintMargin.values) {
      final pdf = _text(
        await buildPrintPdf(
          pages: pages,
          options: PrintOptions(fill: true, margin: margin),
        ),
      );
      expect(_pageCount(pdf), 5);
    }
  });

  test('an invalid page range raises a clear error', () async {
    await expectLater(
      buildPrintPdf(
        pages: pages,
        options: const PrintOptions(pageRange: '9'),
      ),
      throwsA(isA<PrintOptionsException>()),
    );
  });

  test('sheetsFor counts paper correctly', () {
    expect(sheetsFor(const PrintOptions(), 5), 5);
    expect(sheetsFor(const PrintOptions(pagesPerSheet: 2, copies: 2), 5), 6);
    expect(sheetsFor(const PrintOptions(pageRange: 'x'), 5), 0);
  });

  test('presets set sensible options', () {
    expect(PrintOptions.preset(PrintPreset.eco).color, isFalse);
    expect(PrintOptions.preset(PrintPreset.eco).pagesPerSheet, 2);
    expect(PrintOptions.preset(PrintPreset.photo).paper, PaperSize.photo);
    expect(PrintOptions.preset(PrintPreset.photo).fill, isTrue);
  });
}

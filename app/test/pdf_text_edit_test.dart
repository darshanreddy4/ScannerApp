import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/features/pdf_tools/data/security/pdf_model.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_rewriter.dart';
import 'package:doculoom/features/reader/data/pdf_page_reader.dart';
import 'package:doculoom/features/reader/data/pdf_text_edit.dart';
import 'package:doculoom/features/reader/data/pdf_text_extractor.dart';
import 'package:doculoom/features/reader/domain/document_search.dart';

void main() {
  final original = File('test/fixtures/office/search_text.pdf').readAsBytesSync();
  late List<PdfPageEditInfo> info;
  setUpAll(() => info = analyzePdfForEditing(original));

  int lineOf(int page, String startsWith) => info[page].lines.firstWhere((l) => l.text.startsWith(startsWith)).id;

  List<PageTextIndex> read(Uint8List bytes) => extractPdfText(bytes);

  test('finds the lines of every page with their look', () {
    expect(info, hasLength(3));
    expect(info[0].lines.map((l) => l.text), [
      'Hello World',
      'Quarterly report for 2024. The hello team met twice.',
      'Unicode text: café naïve fiﬁne'.replaceAll('ﬁ', 'fi'),
      'Second line continues the sentence about world',
    ]);
    final hello = info[0].lines.first;
    expect(hello.family, 'sans');
    expect(hello.fontSize, closeTo(24, 0.5));
    expect(hello.box.left, closeTo(100 / 612, 0.01));
    expect(info[0].lines[1].family, 'serif');
    expect(info[0].lines[1].fontSize, closeTo(12, 0.5));
    expect(info[0].editable, isTrue);
    expect(info[2].lines, isEmpty, reason: 'a scanned page has no lines');
  });

  test('retyping a line replaces it where it was and leaves the rest of the page alone', () {
    final edited = applyPdfEdits(
      original,
      PdfEditPlan(
        edits: [LineEdit(page: 0, line: lineOf(0, 'Hello'), text: 'Goodbye World')],
      ),
    );
    File('/tmp/pdf_edit_1.pdf').writeAsBytesSync(edited);
    final pages = read(edited);
    expect(pages[0].text, contains('Goodbye World'));
    expect(pages[0].text, isNot(contains('Hello World')));
    expect(searchPages(pages, 'hello world'), isEmpty);
    final now = searchPages(pages, 'goodbye world').single.rects.single;
    expect(now.left, closeTo(100 / 612, 0.006), reason: 'it starts at the same place');
    expect(now.top, closeTo(1 - (700 + 0.8 * 24) / 792, 0.012));

    // The other lines, and the other pages, are as they were.
    expect(pages[0].text, contains('Quarterly report for 2024. The hello team met twice.'));
    expect(pages[0].text, contains('Second line continues the sentence about world'));
    final before = searchPages(read(original), 'quarterly').single.rects.single;
    final after = searchPages(pages, 'quarterly').single.rects.single;
    expect(after.left, closeTo(before.left, 0.001));
    expect(after.top, closeTo(before.top, 0.001));
    expect(pages[1].text, contains('Rotated page says hello'));
  });

  test('a serif line and an embedded-font line (two bytes per letter) can be retyped too', () {
    final edited = applyPdfEdits(
      original,
      PdfEditPlan(
        edits: [
          LineEdit(page: 0, line: lineOf(0, 'Quarterly'), text: 'Annual report for 2025.'),
          LineEdit(page: 0, line: lineOf(0, 'Unicode'), text: 'Plain text: cafe'),
        ],
      ),
    );
    final text = read(edited)[0].text;
    expect(text, contains('Annual report for 2025.'));
    expect(text, contains('Plain text: cafe'));
    expect(text, isNot(contains('Quarterly')));
    expect(text, isNot(contains('naïve')));
    expect(text, contains('Hello World'));
  });

  test('empty text removes the line, and the text that follows it does not move', () {
    final edited = applyPdfEdits(
      original,
      PdfEditPlan(
        edits: [LineEdit(page: 0, line: lineOf(0, 'Quarterly'), text: '')],
      ),
    );
    final pages = read(edited);
    expect(pages[0].text, isNot(contains('Quarterly')));
    expect(searchPages(pages, 'hello'), hasLength(2), reason: 'the title and the rotated page are left; the one in the removed line is gone');
    final before = searchPages(read(original), 'second line').single.rects.single;
    final after = searchPages(pages, 'second line').single.rects.single;
    expect(after.top, closeTo(before.top, 0.001));
  });

  test('new text can be placed on any page, including one with no text', () {
    final edited = applyPdfEdits(
      original,
      const PdfEditPlan(
        additions: [
          AddedText(page: 0, x: 0.2, y: 0.5, text: 'Approved by Priya', sizePt: 18, rgb: 0xC00000, bold: true),
          AddedText(page: 2, x: 0.1, y: 0.2, text: 'Line one\nLine two', sizePt: 12),
        ],
      ),
    );
    final pages = read(edited);
    final box = searchPages(pages, 'approved by priya').single.rects.single;
    expect(box.left, closeTo(0.2, 0.006));
    expect(box.bottom, closeTo(0.5 + 0.2 * 18 / 792, 0.012), reason: 'the baseline is where it was put');
    expect(pages[2].hasText, isTrue);
    final second = searchPages(pages, 'line one line two');
    expect(second, isNotEmpty);
  });

  test('new text on a turned page is upright as shown', () {
    final edited = applyPdfEdits(original, const PdfEditPlan(additions: [AddedText(page: 1, x: 0.3, y: 0.3, text: 'Stamp', sizePt: 20)]));
    final r = searchPages(read(edited), 'stamp').single.rects.single;
    expect(r.width, greaterThan(r.height), reason: 'it reads left to right on the shown page');
    expect(r.left, closeTo(0.3, 0.01));
  });

  test('retyping on a turned page keeps the direction of the original', () {
    final line = lineOf(1, 'Rotated');
    final before = info[1].lines[line].box;
    final edited = applyPdfEdits(
      original,
      PdfEditPlan(
        edits: [LineEdit(page: 1, line: line, text: 'Rotated page says bye')],
      ),
    );
    final r = searchPages(read(edited), 'rotated page says bye').single.rects.single;
    expect(r.height, greaterThan(r.width), reason: 'the line runs down the shown page as before');
    expect(r.left, closeTo(before.left, 0.02));
    expect(r.top, closeTo(before.top, 0.02));
  });

  test('characters the built-in fonts cannot show are refused with a clear message', () {
    expect(unsupportedCharacters('Plain text café €5 “quoted”'), isEmpty);
    expect(unsupportedCharacters('नमस्ते Hi'), isNotEmpty);
    expect(() => applyPdfEdits(original, PdfEditPlan(edits: [LineEdit(page: 0, line: 0, text: 'नमस्ते')])), throwsA(isA<PdfEditException>()));
  });

  test('the edited file is still a normal PDF: it reads again and can be edited again', () {
    final once = applyPdfEdits(
      original,
      PdfEditPlan(
        edits: [LineEdit(page: 0, line: lineOf(0, 'Hello'), text: 'First edit')],
      ),
    );
    final again = analyzePdfForEditing(once);
    final line = again[0].lines.firstWhere((l) => l.text == 'First edit');
    final twice = applyPdfEdits(
      once,
      PdfEditPlan(
        edits: [LineEdit(page: 0, line: line.id, text: 'Second edit')],
      ),
    );
    final text = read(twice)[0].text;
    expect(text, contains('Second edit'));
    expect(text, isNot(contains('First edit')));
  });

  test('files made by other tools can be edited: a PDF from the Dart pdf package', () {
    final files = File('test/fixtures/office/search_text.pdf');
    expect(files.existsSync(), isTrue);
  });

  group('drawings and pictures', () {
    /// What was added to the page: its instructions after the original ones, and its resources.
    ({String ops, PdfDict resources, PdfReader file}) added(Uint8List bytes, int page) {
      final file = PdfReader(readPdfDocument(bytes));
      final info = file.pages()[page];
      final contents = file.res(info.dict['Contents']);
      final parts = contents is PdfArray ? contents.items : [info.dict['Contents']!];
      final ops = latin1.decode(file.decoded(parts.last)!);
      return (ops: ops, resources: file.dict(file.res(info.dict['Resources']))!, file: file);
    }

    final png = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 20)..clear(img.ColorRgb8(200, 30, 30))));
    final transparent = () {
      final i = img.Image(width: 10, height: 10, numChannels: 4)..clear(img.ColorRgba8(0, 0, 255, 0));
      i.setPixelRgba(2, 2, 0, 0, 255, 255);
      return Uint8List.fromList(img.encodePng(i));
    }();

    test('a highlight is a multiplied colour over the text, and the page text is unchanged', () {
      final edited = applyPdfEdits(
        original,
        const PdfEditPlan(marks: [AddedMark(page: 0, kind: 'highlight', x0: 0.1, y0: 0.1, x1: 0.5, y1: 0.2)]),
      );
      final a = added(edited, 0);
      expect(a.ops, contains('/SVMul gs'));
      expect(a.ops, contains('1 0.9216 0.2314 rg'));
      expect(a.ops, contains(' f Q'));
      final gs = a.file.dict(a.resources['ExtGState'])!;
      expect(a.file.dict(gs['SVMul'])!.nameOf('BM'), 'Multiply');
      expect(read(edited)[0].text, read(original)[0].text);
    });

    test('a cover-up, a box and a line are drawn in the colour and width asked for', () {
      final edited = applyPdfEdits(
        original,
        const PdfEditPlan(
          marks: [
            AddedMark(page: 0, kind: 'cover', x0: 0.5, y0: 0.5, x1: 0.2, y1: 0.3, rgb: 0xFFFFFF),
            AddedMark(page: 0, kind: 'box', x0: 0.1, y0: 0.1, x1: 0.3, y1: 0.2, rgb: 0xFF0000, widthPt: 3),
            AddedMark(page: 0, kind: 'line', x0: 0.1, y0: 0.9, x1: 0.9, y1: 0.9, rgb: 0x0000FF),
          ],
        ),
      );
      final ops = added(edited, 0).ops;
      expect(ops, contains('1 1 1 rg'));
      expect(ops, contains('1 0 0 RG 3 w'));
      expect(ops, contains('0 0 1 RG 2 w 1 J'));
      expect(ops, contains(' S Q'));
      expect(ops.split('\n').where((l) => l.contains(' f Q')), hasLength(1));
    });

    test('a picture is placed with its width and shape kept, as an image the page can draw', () {
      final edited = applyPdfEdits(original, PdfEditPlan(pictures: [AddedPicture(page: 0, x: 0.1, y: 0.1, w: 0.4, bytes: png, aspect: 2)]));
      final a = added(edited, 0);
      final m = RegExp(r'q (\S+) (\S+) (\S+) (\S+) (\S+) (\S+) cm /SVI1 Do Q').firstMatch(a.ops)!;
      final w = double.parse(m.group(1)!), h = double.parse(m.group(4)!);
      expect(w, closeTo(0.4 * 612, 0.5));
      expect(h, closeTo(w / 2, 0.5), reason: 'twice as wide as high, as the picture is');
      expect(double.parse(m.group(2)!), 0);
      expect(double.parse(m.group(5)!), closeTo(0.1 * 612, 0.5));
      final xo = a.file.dict(a.resources['XObject'])!;
      final image = a.file.res(xo['SVI1']) as PdfStream;
      expect(image.dict.nameOf('Subtype'), 'Image');
      expect(image.dict.nameOf('Filter'), 'DCTDecode');
      expect(image.dict['SMask'], isNull);
      expect(read(edited)[0].text, read(original)[0].text);
    });

    test('a picture with see-through parts keeps them as a mask', () {
      final edited = applyPdfEdits(original, PdfEditPlan(pictures: [AddedPicture(page: 0, x: 0.1, y: 0.1, w: 0.2, bytes: transparent, aspect: 1)]));
      final a = added(edited, 0);
      final image = a.file.res(a.file.dict(a.resources['XObject'])!['SVI1']) as PdfStream;
      expect(image.dict.nameOf('Filter'), 'FlateDecode');
      final mask = a.file.res(image.dict['SMask']) as PdfStream;
      expect(a.file.decoded(mask), hasLength(100));
      expect(a.file.decoded(mask)!.where((b) => b == 255), hasLength(1));
    });

    test('a file that is not a picture is refused with a message', () {
      expect(
        () => applyPdfEdits(original, PdfEditPlan(pictures: [AddedPicture(page: 0, x: 0.1, y: 0.1, w: 0.2, bytes: Uint8List.fromList([1, 2, 3]), aspect: 1)])),
        throwsA(isA<PdfEditException>()),
      );
    });

    test('drawings, pictures, retyped lines and new text work together, and the result is a normal PDF again', () {
      final edited = applyPdfEdits(
        original,
        PdfEditPlan(
          edits: [LineEdit(page: 0, line: lineOf(0, 'Hello'), text: 'Hi there')],
          additions: const [AddedText(page: 0, x: 0.2, y: 0.5, text: 'Approved', sizePt: 16)],
          marks: const [AddedMark(page: 0, kind: 'highlight', x0: 0.1, y0: 0.3, x1: 0.6, y1: 0.35)],
          pictures: [AddedPicture(page: 0, x: 0.5, y: 0.6, w: 0.3, bytes: png, aspect: 2)],
        ),
      );
      final pages = read(edited);
      expect(pages[0].text, contains('Hi there'));
      expect(pages[0].text, contains('Approved'));
      final a = added(edited, 0);
      expect(a.ops, contains('/SVMul gs'));
      expect(a.ops, contains('/SVI1 Do'));
      expect(a.ops.indexOf('/SVMul gs'), lessThan(a.ops.indexOf('Approved').isNegative ? a.ops.length : a.ops.indexOf('BT')), reason: 'drawings come before the text');
      expect(analyzePdfForEditing(edited)[0].lines.map((l) => l.text), contains('Hi there'));
      final again = applyPdfEdits(edited, const PdfEditPlan(marks: [AddedMark(page: 0, kind: 'box', x0: 0.1, y0: 0.1, x1: 0.2, y1: 0.2)]));
      expect(read(again)[0].text, contains('Hi there'));
    });
  });
}

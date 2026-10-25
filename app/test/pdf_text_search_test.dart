import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:scanvault/features/pdf_tools/data/security/pdf_security.dart';
import 'package:scanvault/features/reader/data/pdf_text_extractor.dart';
import 'package:scanvault/features/reader/domain/document_search.dart';

Uint8List fixture(String path) => File('test/fixtures/$path').readAsBytesSync();

void main() {
  late List<PageTextIndex> pages;
  setUpAll(() => pages = extractPdfText(fixture('office/search_text.pdf')));

  test('reads the text of each page and notices pages that have none', () {
    expect(pages, hasLength(3));
    expect(pages[0].text, contains('Hello World'));
    expect(pages[0].text, contains('Quarterly report for 2024.'));
    expect(pages[0].text, contains('café naïve'));
    expect(pages[1].hasText, isTrue);
    expect(pages[2].hasText, isFalse, reason: 'a picture only page is scanned');
    expect(pages[0].rects.length, pages[0].text.length);
  });

  test('finds every place, ignoring case, in reading order', () {
    final hits = searchPages(pages, 'HELLO');
    expect(hits.map((h) => h.page), [0, 0, 1]);
    expect(searchPages(pages, 'nothing like this'), isEmpty);
    expect(searchPages(pages, '   '), isEmpty);
  });

  test('highlight boxes sit on the words', () {
    // "Hello" is Helvetica 24 pt at x 100, baseline 700 on a 612 x 792 page.
    final r = searchPages(pages, 'hello').first.rects.single;
    expect(r.left, closeTo(100 / 612, 0.006));
    expect(r.right, closeTo((100 + 54.7) / 612, 0.01));
    expect(r.top, closeTo(1 - (700 + 0.8 * 24) / 792, 0.006));
    expect(r.bottom, closeTo(1 - (700 - 0.2 * 24) / 792, 0.006));

    final phrase = searchPages(pages, 'hello world').first.rects.single;
    expect(phrase.right, closeTo(224 / 612, 0.01), reason: 'the whole phrase is one box');
  });

  test('words from an embedded font (with accents and ligatures) can be found', () {
    expect(searchPages(pages, 'café').single.page, 0);
    expect(searchPages(pages, 'naïve').single.page, 0);
    expect(searchPages(pages, 'fine'), hasLength(1));
  });

  test('a phrase can run over a line break and keeps one box per line', () {
    final hit = searchPages(pages, 'fine second line').single;
    expect(hit.rects, hasLength(2));
    expect(hit.rects.first.centerY, lessThan(hit.rects.last.centerY));
  });

  test('turned pages give boxes where the words are shown', () {
    // A 792 x 612 sheet shown turned 90 degrees, so it is portrait and the line of text runs down the page.
    expect(pages[1].aspect, closeTo(612 / 792, 0.001));
    final r = searchPages(pages, 'hello').last.rects.single;
    expect(r.left, closeTo(1 - (1 - 395.2 / 612), 0.012));
    expect(r.top, closeTo(272 / 792, 0.012));
    expect(r.height, greaterThan(r.width), reason: 'a word on a turned page is taller than wide');
  });

  test('a file that needs a password says so, one that only restricts copying opens', () {
    expect(() => extractPdfText(fixture('pdf_security/aes256.pdf')), throwsA(isA<WrongPasswordException>()));
    expect(extractPdfText(fixture('pdf_security/aes256_empty_user.pdf')), isNotEmpty);
    expect(extractPdfText(fixture('pdf_security/plain_objstm.pdf')), isNotEmpty);
  });

  test('damaged files do not throw and give no text', () {
    expect(() => extractPdfText(Uint8List.fromList([1, 2, 3])), throwsA(anything));
  });

  test('a PDF made by the Dart pdf package (the one this app writes) can be searched', () async {
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (_) => pw.Column(children: [pw.Text('Invoice number 4821'), pw.SizedBox(height: 40), pw.Text('Total due: 1,250.00 rupees')])));
    doc.addPage(pw.Page(build: (_) => pw.Text('Second page mentions the invoice again')));
    final found = extractPdfText(await doc.save());
    expect(found, hasLength(2));
    final hits = searchPages(found, 'invoice');
    expect(hits.map((h) => h.page), [0, 1]);
    expect(searchPages(found, '1,250.00').single.page, 0);
    expect(hits.first.rects.single.top, lessThan(0.2), reason: 'the first line is at the top of the page');
  });
}

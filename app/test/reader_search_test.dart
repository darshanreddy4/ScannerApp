import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/importer/domain/importer.dart';
import 'package:scanvault/features/reader/data/docx_reading.dart';
import 'package:scanvault/features/reader/presentation/reader_page.dart';

String docx(Directory dir, List<String> paragraphs, {String name = 'sample.docx'}) {
  final body = paragraphs.map((p) => '<w:p><w:r><w:t xml:space="preserve">${const HtmlEscape().convert(p)}</w:t></w:r></w:p>').join();
  final xml =
      '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body</w:body></w:document>';
  final archive = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  final file = File('${dir.path}/$name')..writeAsBytesSync(ZipEncoder().encode(archive));
  return file.path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('reader_search'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a Word file is searched on the pages it is shown on, with one box per line', () async {
    final lots = [for (var i = 0; i < 90; i++) 'Line $i of the long report about invoices and the number ${i * 7}'];
    final reading = await loadDocxReading(path: docx(dir, ['Intro mentions Invoices once', ...lots]), workDir: Directory('${dir.path}/work'));
    expect(reading.pages.length, greaterThan(1), reason: 'the text runs over more than one page');
    final hits = reading.search('invoices');
    expect(hits.length, 91);
    expect(hits.first.page, 0);
    expect(hits.last.page, greaterThan(0), reason: 'later matches are on later pages');
    final r = hits.first.rects.single;
    expect(r.left, inInclusiveRange(0.05, 0.6));
    expect(r.top, lessThan(0.15), reason: 'the first line is near the top of the page');
    expect(reading.search('nothing here'), isEmpty);
    expect(reading.search('mentions invoices once').single.page, 0);
    reading.dispose();
  });

  testWidgets('search bar: type a word, see the count, step through matches and close', (tester) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final path = docx(dir, ['The quick brown fox jumps over the lazy dog.', 'Another line about the Fox and the hound.']);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReaderPage(
          args: ReaderArgs(path: path, kind: ImportKind.docx),
          workDir: () async => Directory('${dir.path}/work'),
        ),
      ),
    );
    final searchButton = find.byKey(const ValueKey('reader-search-button'));
    for (var i = 0; i < 80 && searchButton.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(searchButton, findsOneWidget);

    await tester.tap(searchButton);
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('reader-search-field')), 'FOX');
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('docx-highlights-0')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('search-next')));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('search-next')));
    await tester.pump();
    expect(find.text('1 of 2'), findsOneWidget, reason: 'it wraps around');
    await tester.tap(find.byKey(const ValueKey('search-prev')));
    await tester.pump();
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('reader-search-field')), 'zebra');
    await tester.pump();
    expect(find.text('None'), findsOneWidget);
    expect(find.byKey(const ValueKey('docx-highlights-0')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('search-next'))).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('search-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('reader-search-field')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Word file with no text has no search button, and a damaged one shows a message', (tester) async {
    final empty = docx(dir, const []);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReaderPage(
          args: ReaderArgs(path: empty, kind: ImportKind.docx),
          workDir: () async => Directory('${dir.path}/work'),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    expect(find.text('This Word document is empty.'), findsOneWidget);
    expect(find.byKey(const ValueKey('reader-search-button')), findsNothing);
  });
}

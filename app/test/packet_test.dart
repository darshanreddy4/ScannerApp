import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/export/data/document_builders.dart' show PageSource;
import 'package:doculoom/features/packet/data/packet_builder.dart';
import 'package:doculoom/features/packet/domain/packet.dart';
import 'package:doculoom/features/packet/presentation/packet_cubit.dart';
import 'package:doculoom/features/packet/presentation/packet_page.dart';

class _FakeBuilder implements PacketBuilder {
  PacketRequest? last;
  bool fail = false;
  PacketResult Function(PacketRequest r)? answer;

  @override
  Future<PacketResult> build(PacketRequest request) async {
    last = request;
    if (fail) throw StateError('boom');
    return answer?.call(request) ??
        PacketResult(path: request.outputPath, bytes: 250 * 1024, pageCount: request.pages.length + (request.cover == null ? 0 : 1), step: 0, fits: true);
  }
}

Future<Uint8List> _fakeCover(CoverText text, List<ContentsLine> lines, {bool letter = false, bool rtl = false}) async => Uint8List.fromList([1, 2, 3]);

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('packet_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String picture(String name, {int w = 60, int h = 80, bool noise = false}) {
    final image = img.Image(width: w, height: h, numChannels: 3);
    if (noise) {
      final r = math.Random(7);
      for (final px in image) {
        px
          ..r = r.nextInt(256)
          ..g = r.nextInt(256)
          ..b = r.nextInt(256);
      }
    }
    final f = File('${dir.path}/$name.jpg')..writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return f.path;
  }

  ScannedDocument doc(String id, String title, int pages, {bool locked = false, int w = 60, int h = 80}) => ScannedDocument(
    id: id,
    title: title,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
    locked: locked,
    pages: [
      for (var i = 0; i < pages; i++)
        DocumentPage(
          id: '$id-$i',
          position: i,
          imagePath: picture('$id-$i', w: w, h: h),
          rawPath: '',
          width: w,
          height: h,
        ),
    ],
  );

  int pdfPages(String path) => RegExp(r'/Type\s*/Page(?![s\w])').allMatches(latin1.decode(File(path).readAsBytesSync())).length;

  group('rules', () {
    test('the title, name and purpose are checked', () {
      expect(titleIssue('  ')!.text, 'Enter a title for the packet.');
      expect(titleIssue('x' * 61)!.text, contains('too long'));
      expect(titleIssue('x' * 60), isNull);
      expect(nameIssue('x' * 61)!.text, contains('name is too long'));
      expect(purposeIssue('x' * 121)!.text, contains('purpose is too long'));
      expect(purposeIssue(''), isNull);
    });

    test('a packet needs a title and documents, within the limits', () {
      const ok = PacketSettings(title: 'Visa');
      const one = PacketEntry(docId: 'a', title: 'A', pageCount: 2);
      expect(packetProblem(ok, const [one]), isNull);
      expect(packetProblem(ok, const [])!.text, 'Add at least one document.');
      expect(packetProblem(const PacketSettings(), const [one])!.text, 'Enter a title for the packet.');
      expect(packetProblem(ok, [for (var i = 0; i < 31; i++) PacketEntry(docId: '$i', title: 'T', pageCount: 1)])!.text, 'A packet has up to 30 documents.');
      expect(packetProblem(ok, const [PacketEntry(docId: 'a', title: 'A', pageCount: 301)])!.text, contains('300 pages'));
    });

    test('the contents number the pages, after the cover when there is one', () {
      const entries = [
        PacketEntry(docId: 'a', title: 'Passport', pageCount: 2),
        PacketEntry(docId: 'b', title: 'Photo', pageCount: 1),
        PacketEntry(docId: 'c', title: 'Empty', pageCount: 0),
        PacketEntry(docId: 'd', title: 'Bank', pageCount: 4),
      ];
      final withCover = contentsLines(entries, cover: true);
      expect(withCover.map((l) => '${l.title} ${l.pages}'), ['Passport 2\u20133', 'Photo 4', 'Bank 5\u20138']);
      expect(contentsLines(entries, cover: false).map((l) => l.pages), ['1\u20132', '3', '4\u20137']);
      expect(packetPageCount(entries, cover: true), 8);
      expect(packetPageCount(entries, cover: false), 7);
    });

    test('the file name is safe, keeps letters of any script, and ends with the day', () {
      final d = DateTime(2026, 3, 9);
      expect(packetFileName('Visa: UK / 2026!', d), 'Visa_UK_2026_2026-03-09.pdf');
      expect(packetFileName('  ', d), 'Packet_2026-03-09.pdf');
      expect(packetFileName('\u0935\u0940\u091C\u093C\u093E', d), contains('\u0935'));
      expect(packetFileName('x' * 100, d).length, lessThan(60));
    });

    test('quality only goes down, and sizes are said plainly', () {
      for (var i = 2; i < qualitySteps.length; i++) {
        expect(qualitySteps[i].maxSide!, lessThan(qualitySteps[i - 1].maxSide ?? 1 << 30));
        expect(qualitySteps[i].jpegQuality, lessThan(qualitySteps[i - 1].jpegQuality == 0 ? 100 : qualitySteps[i - 1].jpegQuality + 1));
      }
      expect(qualitySteps.first.maxSide, isNull);
      expect(sizeLabel(500), '500 B');
      expect(sizeLabel(2048), '2 KB');
      expect(sizeLabel(1024 * 1024 * 3 ~/ 2), '1.50 MB');
      expect(sizeLabel(12 * 1024 * 1024), '12.0 MB');
      expect(PacketLimit.values.map((l) => l.bytes), [null, 1048576, 2097152, 5242880, 10485760]);
    });
  });

  group('the file', () {
    List<PageSource> sources(int n, {bool noise = false, int w = 900, int h = 1200}) => [
      for (var i = 0; i < n; i++)
        PageSource(
          path: picture('p$i', w: w, h: h, noise: noise),
          width: w,
          height: h,
        ),
    ];

    test('with no limit the pictures are kept as they are, and the cover adds a page', () async {
      final r = await buildPacketFile(
        PacketRequest(pages: sources(3), outputPath: '${dir.path}/out.pdf', cover: Uint8List.fromList(img.encodePng(img.Image(width: 20, height: 30)))),
      );
      expect(r.step, 0);
      expect(r.fits, isTrue);
      expect(r.reduced, isFalse);
      expect(r.pageCount, 4);
      expect(File(r.path).readAsBytesSync().sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
      expect(pdfPages(r.path), 4);
      expect(File(r.path).lengthSync(), r.bytes);
    });

    test('without a cover or numbers it still makes every page', () async {
      final r = await buildPacketFile(PacketRequest(pages: sources(2), outputPath: '${dir.path}/out.pdf', numbers: false));
      expect(r.pageCount, 2);
      expect(pdfPages(r.path), 2);
    });

    test('a limit that the first try misses makes the pictures smaller until the file fits', () async {
      final pages = sources(3, noise: true, w: 1600, h: 2000);
      final full = await buildPacketFile(PacketRequest(pages: pages, outputPath: '${dir.path}/full.pdf'));
      final limit = full.bytes ~/ 4;
      final r = await buildPacketFile(PacketRequest(pages: pages, outputPath: '${dir.path}/small.pdf', limitBytes: limit));
      expect(r.step, greaterThan(0));
      expect(r.reduced, isTrue);
      expect(r.fits, isTrue);
      expect(r.bytes, lessThanOrEqualTo(limit));
      expect(pdfPages(r.path), 3);
    });

    test('a limit that is already met keeps the best quality', () async {
      final pages = sources(2);
      final r = await buildPacketFile(PacketRequest(pages: pages, outputPath: '${dir.path}/o.pdf', limitBytes: 10 * 1024 * 1024));
      expect(r.step, 0);
      expect(r.fits, isTrue);
    });

    test('a limit nothing can meet gives the smallest file and says it does not fit', () async {
      final r = await buildPacketFile(PacketRequest(pages: sources(3, noise: true, w: 1000, h: 1400), outputPath: '${dir.path}/o.pdf', limitBytes: 2000));
      expect(r.step, qualitySteps.length - 1);
      expect(r.fits, isFalse);
      expect(r.bytes, greaterThan(2000));
      expect(pdfPages(r.path), 3);
    });

    test('US Letter and A4 give pages of different sizes', () async {
      final a4 = await buildPacketFile(PacketRequest(pages: sources(1, w: 600, h: 1000), outputPath: '${dir.path}/a4.pdf'));
      final us = await buildPacketFile(PacketRequest(pages: sources(1, w: 600, h: 1000), outputPath: '${dir.path}/us.pdf', letter: true));
      expect(latin1.decode(File(a4.path).readAsBytesSync()), contains('/MediaBox'));
      expect(File(a4.path).readAsBytesSync(), isNot(File(us.path).readAsBytesSync()));
    });
  });

  group('the cover', () {
    const text = CoverText(
      title: 'Visa application',
      purpose: 'Schengen, 3 weeks',
      applicant: 'Prepared for A. Sharma',
      contents: 'Contents',
      summary: 'Documents: 3   Pages: 9',
      date: 'Prepared on 9 Mar 2026',
    );
    final lines = [
      const ContentsLine('Passport', 2, 3),
      const ContentsLine('Bank statements for the last six months, with a very long title that has to be cut', 4, 8),
    ];

    testWidgets('is a picture of the page, in A4 or US Letter', (tester) async {
      await tester.runAsync(() async {
        final a4 = img.decodePng(await renderCover(text, lines))!;
        final us = img.decodePng(await renderCover(text, lines, letter: true))!;
        expect((a4.width, a4.height), (1190, 1684));
        expect((us.width, us.height), (1224, 1584));
      });
    });

    testWidgets('takes a full list, any script and right-to-left writing', (tester) async {
      await tester.runAsync(() async {
        final many = [for (var i = 0; i < 30; i++) ContentsLine('\u092A\u093E\u0938\u092A\u094B\u0930\u094D\u091F $i', i + 2, i + 2)];
        final bytes = await renderCover(text, many, rtl: true);
        expect(img.decodePng(bytes), isNotNull);
        expect(await renderCover(const CoverText(title: '', purpose: '', applicant: '', contents: '', summary: '', date: ''), const []), isNotEmpty);
      });
    });
  });

  group('the work behind the screen', () {
    late _FakeBuilder builder;
    late ScannedDocument a, b, empty;

    PacketCubit cubit({List<String> initial = const [], DateTime Function()? now}) => PacketCubit(
      builder: builder,
      outputDir: () async => dir,
      library: [a, b, empty],
      initial: initial,
      now: now ?? () => DateTime(2026, 3, 9),
      coverRenderer: _fakeCover,
    );

    setUp(() {
      builder = _FakeBuilder();
      a = doc('a', 'Passport', 2);
      b = doc('b', 'Bank', 3);
      empty = ScannedDocument(id: 'e', title: 'Empty', createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []);
    });

    test('documents are added once, in order, and not when they are unknown or have no pages', () {
      final c = cubit(initial: ['b', 'a', 'a', 'zzz', 'e']);
      expect(c.state.entries.map((e) => e.docId), ['b', 'a']);
      expect(c.state.entries.first.pageCount, 3);
      c.addDocuments(['a', 'b']);
      expect(c.state.entries.length, 2);
    });

    test('they can be moved and removed, and the ends stay put', () {
      final c = cubit(initial: ['a', 'b']);
      c.move('b', -1);
      expect(c.state.entries.map((e) => e.docId), ['b', 'a']);
      c.move('b', -1);
      c.move('a', 1);
      expect(c.state.entries.map((e) => e.docId), ['b', 'a']);
      c.remove('b');
      expect(c.state.entries.map((e) => e.docId), ['a']);
    });

    test('the packet is made from the pages in the order chosen, with the settings', () async {
      final c = cubit(initial: ['b', 'a']);
      c.setSettings(const PacketSettings(title: 'Visa', name: 'A. Sharma', purpose: 'UK', limit: PacketLimit.mb2, numbers: false));
      await c.make();
      expect(c.state.status, PacketStatus.done);
      final r = builder.last!;
      expect(r.pages.length, 5);
      expect(r.pages.first.path, b.pages.first.imagePath);
      expect(r.pages.last.path, a.pages.last.imagePath);
      expect(r.limitBytes, 2 * 1024 * 1024);
      expect(r.numbers, isFalse);
      expect(r.cover, isNotNull);
      expect(r.outputPath, '${dir.path}/packets/Visa_2026-03-09.pdf');
      expect(Directory('${dir.path}/packets').existsSync(), isTrue);
      expect(c.state.result!.pageCount, 6);
    });

    test('without a cover none is made, and a missing title or document stops it with a message in the fields', () async {
      final c = cubit(initial: ['a']);
      c.setSettings(const PacketSettings(title: 'Visa', cover: false));
      await c.make();
      expect(builder.last!.cover, isNull);

      final empty = cubit();
      await empty.make();
      expect(empty.state.tried, isTrue);
      expect(empty.state.status, PacketStatus.idle);
      final notitle = cubit(initial: ['a']);
      await notitle.make();
      expect(notitle.state.tried, isTrue);
      expect(notitle.state.status, PacketStatus.idle);
    });

    test('a failure is explained and the person can try again', () async {
      final c = cubit(initial: ['a']);
      c.setSettings(const PacketSettings(title: 'Visa'));
      builder.fail = true;
      await c.make();
      expect(c.state.status, PacketStatus.failed);
      expect(c.state.problem, contains('could not be made'));
      builder.fail = false;
      await c.make();
      expect(c.state.status, PacketStatus.done);
    });

    test('a page that is gone from the phone is a failure, not a crash', () async {
      final c = cubit(initial: ['a']);
      c.setSettings(const PacketSettings(title: 'Visa'));
      File(a.pages.first.imagePath).deleteSync();
      await c.make();
      expect(c.state.status, PacketStatus.failed);
      expect(builder.last, isNull);
    });

    test('changing anything clears an earlier result', () async {
      final c = cubit(initial: ['a']);
      c.setSettings(const PacketSettings(title: 'Visa'));
      await c.make();
      expect(c.state.result, isNotNull);
      c.setSettings(c.state.settings.copyWith(limit: PacketLimit.mb1));
      expect(c.state.result, isNull);
      expect(c.state.status, PacketStatus.idle);
    });
  });

  group('screen', () {
    late _FakeBuilder builder;
    late List<ScannedDocument> docs;

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> reveal(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      for (final dy in [-200.0, 200.0]) {
        if (f.evaluate().isNotEmpty) break;
        try {
          await tester.dragUntilVisible(f, find.byType(ListView), Offset(0, dy), maxIteration: 80);
        } on StateError {
          // Wrong way: the list is already at that end.
        }
      }
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, {List<String> initial = const [], double width = 400, double height = 900}) async {
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PacketPage(initial: initial, documentsOf: (_) => docs, builder: builder, outputDir: () async => dir, coverRenderer: _fakeCover),
        ),
      );
      await settle(tester);
    }

    setUp(() {
      builder = _FakeBuilder();
      docs = [doc('a', 'Passport', 2), doc('b', 'Bank statement', 3), doc('c', 'Secret', 1, locked: true)];
    });

    testWidgets('an empty packet says what to do, and the button explains what is missing', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('packet-empty')), findsOneWidget);
      expect(find.text('Application packet'), findsWidgets);
      await reveal(tester, 'packet-make');
      await tester.tap(find.byKey(const ValueKey('packet-make')));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('packet-problem'))).data, 'Add at least one document.');
      expect(builder.last, isNull);
    });

    testWidgets('documents are chosen, put in order, and the pages are counted', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('packet-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('packet-pick-a')), findsOneWidget);
      expect(find.text('Locked: unlock it first to add it'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('packet-pick-c'))).onChanged, isNull);
      await tester.tap(find.byKey(const ValueKey('packet-pick-b')));
      await tester.tap(find.byKey(const ValueKey('packet-pick-a')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('packet-pick-done')));
      await settle(tester);
      expect(find.byKey(const ValueKey('packet-doc-b')), findsOneWidget);
      expect(find.text('6 pages in all'), findsOneWidget, reason: '5 pages and the cover');
      await tester.tap(find.byKey(const ValueKey('packet-down-b')));
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(const ValueKey('packet-doc-a'))).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('packet-doc-b'))).dy));
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('packet-up-a'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('packet-down-b'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('packet-remove-b')));
      await tester.pump();
      expect(find.byKey(const ValueKey('packet-doc-b')), findsNothing);
      expect(find.text('3 pages in all'), findsOneWidget);
    });

    testWidgets('the page numbers and cover can be switched off and the size limit chosen', (tester) async {
      await open(tester, initial: ['a']);
      await reveal(tester, 'packet-cover');
      await tester.tap(find.byKey(const ValueKey('packet-cover')));
      await reveal(tester, 'packet-numbers');
      await tester.tap(find.byKey(const ValueKey('packet-numbers')));
      await reveal(tester, 'packet-limit-mb5');
      await tester.tap(find.byKey(const ValueKey('packet-limit-mb5')));
      await tester.pump();
      await reveal(tester, 'packet-make');
      await tester.tap(find.byKey(const ValueKey('packet-make')));
      await settle(tester);
      final r = builder.last!;
      expect(r.cover, isNull);
      expect(r.numbers, isFalse);
      expect(r.limitBytes, 5 * 1024 * 1024);
      await reveal(tester, 'pdf-result');
      expect(find.text('Your packet is ready'), findsOneWidget);
      await reveal(tester, 'pdf-result');
      expect(find.textContaining('2 pages, 250 KB.'), findsOneWidget);
    });

    testWidgets('an empty title is called out, and a result shows when the pictures were made smaller', (tester) async {
      await open(tester, initial: ['a', 'b']);
      await tester.enterText(find.byKey(const ValueKey('packet-title')), '');
      await reveal(tester, 'packet-make');
      await tester.tap(find.byKey(const ValueKey('packet-make')));
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('packet-problem'))).data, 'Enter a title for the packet.');
      expect(builder.last, isNull);
      await tester.enterText(find.byKey(const ValueKey('packet-title')), 'Visa pack');
      builder.answer = (r) => PacketResult(path: r.outputPath, bytes: 900 * 1024, pageCount: 6, step: 3, fits: true);
      await reveal(tester, 'packet-limit-mb1');
      await tester.tap(find.byKey(const ValueKey('packet-limit-mb1')));
      await tester.pump();
      await reveal(tester, 'packet-make');
      await tester.tap(find.byKey(const ValueKey('packet-make')));
      await settle(tester);
      await reveal(tester, 'pdf-result');
      expect(find.textContaining('6 pages, 900 KB.'), findsOneWidget);
      expect(find.textContaining('made smaller to fit the limit'), findsOneWidget);
      expect(find.byKey(const ValueKey('packet-too-big')), findsNothing);
    });

    testWidgets('a file that cannot be made small enough is not passed off as done', (tester) async {
      await open(tester, initial: ['a']);
      await reveal(tester, 'packet-limit-mb1');
      await tester.tap(find.byKey(const ValueKey('packet-limit-mb1')));
      builder.answer = (r) => PacketResult(path: r.outputPath, bytes: 3 * 1024 * 1024, pageCount: 3, step: 6, fits: false);
      await reveal(tester, 'packet-make');
      await tester.tap(find.byKey(const ValueKey('packet-make')));
      await settle(tester);
      await reveal(tester, 'packet-too-big');
      expect(find.byKey(const ValueKey('packet-too-big')), findsOneWidget);
      expect(find.textContaining('above the 1 MB limit'), findsOneWidget);
    });

    testWidgets('a failure shows a message', (tester) async {
      await open(tester, initial: ['a']);
      builder.fail = true;
      await reveal(tester, 'packet-make');
      await tester.tap(find.byKey(const ValueKey('packet-make')));
      await settle(tester);
      await reveal(tester, 'packet-failed');
      expect(find.byKey(const ValueKey('packet-failed')), findsOneWidget);
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen with a long title and many documents', (tester) async {
        docs = [for (var i = 0; i < 6; i++) doc('d$i', 'A document with a rather long name number $i for a narrow phone', 2)];
        await open(tester, initial: [for (final d in docs) d.id], width: w, height: 640);
        await reveal(tester, 'packet-title');
        await tester.enterText(find.byKey(const ValueKey('packet-title')), 'An application packet with a title that is long enough to wrap');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await reveal(tester, 'packet-make');
        await tester.tap(find.byKey(const ValueKey('packet-make')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

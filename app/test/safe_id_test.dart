import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/photo_tools/data/watermark_processor.dart';
import 'package:doculoom/features/safe_id/data/safe_id_processor.dart';
import 'package:doculoom/features/safe_id/domain/safe_id.dart';
import 'package:doculoom/features/safe_id/presentation/safe_id_page.dart';

import 'support/pdf_ui_fakes.dart';

/// A line of text with a box per word: every letter is 10 pixels wide and a space is one more letter.
OcrLine _line(String text, {double left = 100, double top = 100, double height = 20}) {
  final words = <OcrWord>[];
  var x = left;
  for (final w in text.split(' ')) {
    words.add(OcrWord(text: w, left: x, top: top, right: x + w.length * 10, bottom: top + height));
    x += (w.length + 1) * 10;
  }
  return OcrLine(text: text, left: left, top: top, right: x - 10, bottom: top + height, words: words);
}

OcrPageResult _page(List<OcrLine> lines, {double w = 1000, double h = 600}) => OcrPageResult(
  width: w,
  height: h,
  blocks: [OcrBlock(lines: lines)],
);

List<SafeFinding> _find(String text, IdKind kind, {double left = 100}) => findSensitive(_page([_line(text, left: left)]), kind);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what is found', () {
    const pad = 4.8; // 0.8% of the shorter side of a 1000 x 600 picture

    test('an Aadhaar number has its first 8 digits covered and the last 4 left', () {
      final f = _find('1234 5678 9012', IdKind.aadhaar);
      expect(f.length, 1);
      expect(f.single.covered, isTrue);
      expect(f.single.label, 'Aadhaar number');
      expect(f.single.left, closeTo(100 - pad, 0.01));
      expect(f.single.right, closeTo(190 + pad, 0.01), reason: 'ends with the second group; the third group is left');
    });

    test('a number written as one piece is cut in proportion', () {
      final f = _find('234567890123', IdKind.aadhaar);
      expect(f.single.right, closeTo(100 + 120 * 8 / 12 + pad, 0.01));
    });

    test('a number that starts with 0 or 1 is not an Aadhaar number, and neither is a phone number', () {
      expect(_find('123456789012', IdKind.aadhaar), isEmpty);
      expect(_find('Mobile 9876543210', IdKind.aadhaar), isEmpty);
      expect(_find('DOB 01/01/1990', IdKind.aadhaar), isEmpty);
    });

    test('a 16-digit virtual ID is covered up to its 12th digit, once', () {
      final f = _find('9123 4567 8912 3456', IdKind.aadhaar);
      expect(f.length, 1);
      expect(f.single.right, closeTo(240 + pad, 0.01));
    });

    test('a PAN is found but left visible, as KYC needs it', () {
      final f = _find('Permanent Account Number ABCDE1234F', IdKind.pan);
      expect(f.length, 1);
      expect(f.single.covered, isFalse);
      expect(f.single.label, 'PAN');
      expect(_find('ABCDE12345', IdKind.pan), isEmpty);
    });

    test('the code lines of a passport are covered, the number is only marked', () {
      final f = findSensitive(_page([_line('P<INDSHARMA<<RAHUL<<<<<<<<<<<<<<<<<<<<<<<<<'), _line('Z1234567 REPUBLIC OF INDIA', top: 200)]), IdKind.passport);
      expect(f.where((x) => x.label == 'Machine-readable lines').single.covered, isTrue);
      expect(f.where((x) => x.label == 'Passport number').single.covered, isFalse);
    });

    test('a Social Security number has the first 5 digits covered', () {
      final f = _find('123-45-6789', IdKind.usSsn);
      expect(f.single.covered, isTrue);
      expect(f.single.right, closeTo(100 + 110 * 6 / 11 + pad, 0.01));
    });

    test('a card number is covered but for the last 4 digits, and only when it adds up', () {
      final f = _find('4111 1111 1111 1111', IdKind.bankCard);
      expect(f.length, 1);
      expect(f.single.right, closeTo(240 + pad, 0.01));
      expect(_find('4111 1111 1111 1112', IdKind.bankCard), isEmpty, reason: 'fails the Luhn check');
    });

    test('another ID has long numbers covered but for the last 4 digits', () {
      final f = _find('Account 123456789012', IdKind.other);
      expect(f.single.covered, isTrue);
      expect(f.single.left, closeTo(100 + 80 - pad, 0.01));
      expect(f.single.right, closeTo(100 + 80 + 80 + pad, 0.01));
      expect(_find('Pin 123456', IdKind.other), isEmpty);
    });

    test('numbers of other countries are found and left visible', () {
      expect(_find('784-1990-1234567-1', IdKind.emiratesId).single.covered, isFalse);
      expect(_find('1234567890', IdKind.saudiId).single.covered, isFalse);
      expect(_find('12345', IdKind.saudiId), isEmpty);
      expect(_find('MH12 20110012345', IdKind.drivingLicence).single.label, 'Licence number');
      expect(_find('ABC1234567', IdKind.voter).single.label, 'EPIC number');
    });

    test('a kind only looks for its own numbers', () {
      expect(_find('1234 5678 9012', IdKind.pan), isEmpty);
      expect(_find('ABCDE1234F', IdKind.aadhaar), isEmpty);
    });

    test('a line without word boxes is cut in proportion', () {
      const line = OcrLine(text: '234567890123', left: 100, top: 100, right: 220, bottom: 120);
      final f = findSensitive(_page([line]), IdKind.aadhaar);
      expect(f.single.right, closeTo(100 + 120 * 8 / 12 + pad, 0.01));
    });
  });

  group('the words and boxes', () {
    test('the mark names the purpose and takes the date later', () {
      expect(safeIdMarkText('SIM card'), 'Only for SIM card - {date}');
      expect(safeIdMarkText('  Bank   account  {x} '), 'Only for Bank account x - {date}');
      expect(safeIdMarkText(''), 'Copy made on {date}');
      expect(safeIdMarkText('x' * 100).length, lessThan(100));
    });

    test('a box from two corners is put in order and kept inside the picture', () {
      final b = CoverBox.fromCorners(0.9, 0.8, -0.2, 0.1);
      expect((b.left, b.top, b.right, b.bottom), (0.0, 0.1, 0.9, 0.8));
      expect(CoverBox.fromCorners(0.5, 0.5, 1.7, 2).right, 1.0);
      expect(b.contains(0.5, 0.5), isTrue);
      expect(b.contains(0.95, 0.5), isFalse);
    });
  });

  group('the picture', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('sv_sid'));
    tearDown(() => dir.deleteSync(recursive: true));

    String white(String name, int w, int h, {bool png = false, void Function(img.Image)? edit}) {
      final image = img.Image(width: w, height: h, numChannels: png ? 4 : 3);
      img.fill(image, color: png ? img.ColorRgba8(255, 255, 255, 255) : img.ColorRgb8(255, 255, 255));
      edit?.call(image);
      return (File(p.join(dir.path, name))..writeAsBytesSync(png ? img.encodePng(image) : img.encodeJpg(image, quality: 100))).path;
    }

    test('a cover is solid black and the rest is untouched', () {
      final src = white('a.jpg', 200, 100);
      final out = p.join(dir.path, 'out.jpg');
      final size = applyCovers(src, out, const [CoverBox(0.1, 0.2, 0.5, 0.6)]);
      expect((size.width, size.height), (200, 100));
      final r = img.decodeJpg(File(out).readAsBytesSync())!;
      expect(r.getPixel(60, 40).r, lessThan(12));
      expect(r.getPixel(21, 21).r, lessThan(12), reason: 'the first pixel of the box');
      expect(r.getPixel(99, 59).r, lessThan(12), reason: 'the last pixel of the box');
      expect(r.getPixel(150, 80).r, greaterThan(245));
      expect(r.getPixel(10, 10).r, greaterThan(245));
    });

    test('boxes may overlap or reach past the picture', () {
      final out = p.join(dir.path, 'o.jpg');
      applyCovers(white('b.jpg', 100, 100), out, const [CoverBox(0, 0, 1, 1), CoverBox(0.5, 0.5, 1.2, 1.2), CoverBox(0.4, 0.4, 0.4, 0.9)]);
      expect(img.decodeJpg(File(out).readAsBytesSync())!.getPixel(50, 50).r, lessThan(12));
    });

    test('the working copy is upright, of a limited size, flat and without camera data', () {
      final src = white(
        'c.jpg',
        200,
        100,
        edit: (i) {
          i.exif.imageIfd.orientation = 6;
          i.exif.imageIfd.make = 'PhoneMaker';
        },
      );
      final prepared = prepareId(src, p.join(dir.path, 'w.jpg'));
      expect((prepared.width, prepared.height), (100, 200), reason: 'turned upright');
      final bytes = File(prepared.path).readAsBytesSync();
      expect(img.decodeJpgExif(bytes)?.isEmpty ?? true, isTrue);
      expect(String.fromCharCodes(bytes).contains('PhoneMaker'), isFalse);

      final big = prepareId(white('big.png', 3000, 1000, png: true), p.join(dir.path, 'w2.jpg'));
      expect((big.width, big.height), (2400, 800));
      expect(img.decodeJpg(File(big.path).readAsBytesSync())!.numChannels, 3);
    });

    test('the service makes a picture with the covers and the mark, and clears what it made on the way', () async {
      final service = SafeIdProcessor(
        watermark: WatermarkProcessor(pdfToImages: (_) async => const []),
        now: () => DateTime(2026, 3, 7, 10),
      );
      final work = (await service.prepare(sourcePath: white('d.jpg', 600, 400), outputDir: p.join(dir.path, 'out'))).valueOrNull!;
      final plain = (await service.make(
        workPath: work.path,
        boxes: const [CoverBox(0.1, 0.1, 0.4, 0.3)],
        pdf: false,
        name: 'SafeID_aadhaar',
        outputDir: p.join(dir.path, 'out'),
      )).valueOrNull!;
      final marked = (await service.make(
        workPath: work.path,
        boxes: const [CoverBox(0.1, 0.1, 0.4, 0.3)],
        markText: 'Only for KYC - {date}',
        pdf: false,
        name: 'SafeID_aadhaar',
        outputDir: p.join(dir.path, 'out'),
      )).valueOrNull!;
      expect(plain.mimeType, 'image/jpeg');
      expect(plain.name, startsWith('SafeID_aadhaar_'));
      final a = img.decodeJpg(File(plain.path).readAsBytesSync())!;
      final b = img.decodeJpg(File(marked.path).readAsBytesSync())!;
      expect((a.width, a.height), (600, 400));
      expect(a.getPixel(150, 80).r, lessThan(12));
      expect(b.getPixel(150, 80).r, lessThan(12), reason: 'still black under a mark');
      var differs = 0;
      for (var y = 0; y < 400; y += 2) {
        for (var x = 0; x < 600; x += 2) {
          if ((a.getPixel(x, y).g - b.getPixel(x, y).g).abs() > 20) differs++;
        }
      }
      expect(differs, greaterThan(100), reason: 'the mark is on the picture');
      final names = Directory(p.join(dir.path, 'out')).listSync().map((f) => p.basename(f.path)).toList();
      expect(names.where((n) => n.contains('cover') || n.contains('watermarked')), isEmpty, reason: names.toString());
      expect(names.length, 3, reason: 'the working copy and the two results');
    });

    test('the service can make a PDF', () async {
      final service = SafeIdProcessor(watermark: WatermarkProcessor(pdfToImages: (_) async => const []));
      final work = (await service.prepare(sourcePath: white('e.jpg', 600, 400), outputDir: dir.path)).valueOrNull!;
      final r = (await service.make(workPath: work.path, boxes: const [], pdf: true, name: 'SafeID_other', outputDir: dir.path)).valueOrNull!;
      expect(r.isPdf, isTrue);
      expect(String.fromCharCodes(File(r.path).readAsBytesSync().take(5)), '%PDF-');
    });

    test('a file that is not a picture is refused with a plain message', () async {
      final bad = File(p.join(dir.path, 'x.jpg'))..writeAsStringSync('not a picture');
      final service = SafeIdProcessor(watermark: WatermarkProcessor(pdfToImages: (_) async => const []));
      final r = await service.prepare(sourcePath: bad.path, outputDir: dir.path);
      expect(r.failureOrNull, isA<ExportFailure>());
      expect((await service.prepare(sourcePath: p.join(dir.path, 'gone.jpg'), outputDir: dir.path)).failureOrNull!.message, contains('could not be found'));
    });
  });

  group('the page', () {
    late Directory dir;
    late FakeShare share;
    late FakeSave save;
    late String picture;
    late List<int> pictureBytes;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('sv_sidp');
      final image = img.Image(width: 1000, height: 600, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      picture = (File(p.join(dir.path, 'id.jpg'))..writeAsBytesSync(img.encodeJpg(image, quality: 100))).path;
      pictureBytes = File(picture).readAsBytesSync();
      share = FakeShare();
      save = FakeSave();
      await sl.reset();
      sl
        ..registerSingleton<ShareService>(share)
        ..registerSingleton<SaveService>(save);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    final idPage = _page([_line('1234 5678 9012', top: 100), _line('RAHUL SHARMA', top: 300)]);

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 14; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      }
      await tester.pump();
    }

    Future<void> open(WidgetTester tester, {OcrEngine? ocr, double width = 400, Future<String?> Function(SafeIdSource)? pick}) async {
      tester.view.physicalSize = Size(width * 3, 6000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SafeIdPage(
            pick: pick ?? (_) async => picture,
            ocr: ocr ?? _Ocr(idPage),
            workDir: () async => Directory(p.join(dir.path, 'work'))..createSync(recursive: true),
            service: SafeIdProcessor(watermark: WatermarkProcessor(pdfToImages: (_) async => const [])),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> pickGallery(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('safeid-pick-gallery')));
      await settle(tester);
    }

    Offset at(WidgetTester tester, double fx, double fy) {
      final r = tester.getRect(find.byKey(const ValueKey('safeid-preview')));
      return r.topLeft + Offset(r.width * fx, r.height * fy);
    }

    Future<void> tapKind(WidgetTester tester, IdKind k) async {
      await tester.ensureVisible(find.byKey(ValueKey('safeid-kind-${k.name}')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('safeid-kind-${k.name}')));
      await tester.pump();
    }

    Future<void> create(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('safeid-create')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('safeid-create')));
      await settle(tester);
      await settle(tester);
    }

    List<File> results() => Directory(p.join(dir.path, 'work')).listSync().whereType<File>().where((f) => p.basename(f.path).startsWith('SafeID_')).toList();

    testWidgets('nothing is shown until a picture is chosen', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('safeid-preview')), findsNothing);
      expect(find.byKey(const ValueKey('safeid-kind-aadhaar')), findsNothing);
    });

    testWidgets('choosing Aadhaar covers the first 8 digits, and a tap covers or shows a line', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.aadhaar);
      expect(find.text('1 area covered'), findsOneWidget);
      expect(find.textContaining('first 8 digits'), findsOneWidget);
      await tester.tapAt(at(tester, 0.2, 0.18));
      await tester.pump();
      expect(find.text('2 areas covered'), findsOneWidget, reason: 'the line that holds the number is covered as a whole');
      await tester.tapAt(at(tester, 0.2, 0.5));
      await tester.pump();
      expect(find.text('3 areas covered'), findsOneWidget);
      await tester.tapAt(at(tester, 0.2, 0.5));
      await tester.pump();
      expect(find.text('2 areas covered'), findsOneWidget);
    });

    testWidgets('changing the kind changes what is covered by itself, and keeps boxes that were drawn', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.aadhaar);
      await tester.tap(find.text('Draw a box'));
      await tester.pump();
      final from = at(tester, 0.6, 0.6);
      final g = await tester.startGesture(from);
      await g.moveTo(from + const Offset(60, 30));
      await g.moveTo(from + const Offset(120, 50));
      await g.up();
      await tester.pump();
      expect(find.text('2 areas covered'), findsOneWidget);
      await tapKind(tester, IdKind.pan);
      expect(find.text('1 area covered'), findsOneWidget, reason: 'nothing by itself for a PAN card, but the drawn box stays');
    });

    testWidgets('a box that was drawn is removed with a tap', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.pan);
      expect(find.text('0 areas covered'), findsOneWidget);
      await tester.tap(find.text('Draw a box'));
      await tester.pump();
      final from = at(tester, 0.6, 0.7);
      final g = await tester.startGesture(from);
      await g.moveTo(from + const Offset(40, 20));
      await g.moveTo(from + const Offset(120, 60));
      await g.up();
      await tester.pump();
      expect(find.text('1 area covered'), findsOneWidget);
      await tester.tapAt(from + const Offset(80, 40));
      await tester.pump();
      expect(find.text('0 areas covered'), findsOneWidget);
    });

    testWidgets('the copy has black where it was covered, a mark over it, and the original is not changed', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.aadhaar);
      await create(tester);
      final out = results().single;
      expect(out.path, endsWith('.jpg'));
      final r = img.decodeJpg(out.readAsBytesSync())!;
      expect((r.width, r.height), (1000, 600));
      expect(r.getPixel(150, 110).r, lessThan(80), reason: 'inside the covered number, even under the mark');
      expect(File(picture).readAsBytesSync(), pictureBytes, reason: 'the original is not touched');
      expect(find.byKey(const ValueKey('safeid-result')), findsOneWidget);
      expect(find.byKey(const ValueKey('safeid-preview')), findsNothing, reason: 'the picture that showed everything is gone');
      final left = Directory(p.join(dir.path, 'work')).listSync().map((f) => p.basename(f.path)).where((n) => n.startsWith('safeid_work')).toList();
      expect(left, isEmpty, reason: 'the working copy is deleted');
    });

    testWidgets('the mark follows the purpose that was typed or chosen', (tester) async {
      await open(tester);
      await pickGallery(tester);
      expect(find.text('The mark will read: Only for KYC verification - the date'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('safeid-preset-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('safeid-preset-2')));
      await tester.pump();
      expect(find.text('The mark will read: Only for SIM card - the date'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('safeid-purpose')), 'Gym joining');
      await tester.pump();
      expect(find.text('The mark will read: Only for Gym joining - the date'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('safeid-mark')));
      await tester.pump();
      expect(find.byKey(const ValueKey('safeid-purpose')), findsNothing);
    });

    testWidgets('a PDF can be made, and the result can be shared and saved', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.aadhaar);
      await tester.ensureVisible(find.byKey(const ValueKey('safeid-format')));
      await tester.pump();
      await tester.tap(find.text('PDF'));
      await tester.pump();
      await create(tester);
      final out = results().single;
      expect(out.path, endsWith('.pdf'));
      expect(String.fromCharCodes(out.readAsBytesSync().take(5)), '%PDF-');
      expect(find.byKey(const ValueKey('safeid-gallery')), findsNothing, reason: 'a PDF does not go to the gallery');
      await tester.ensureVisible(find.byKey(const ValueKey('safeid-share')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('safeid-share')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('safeid-files')));
      await tester.pump();
      expect(share.shared.single.mime, 'application/pdf');
      expect(save.files.single, startsWith('SafeID_aadhaar_'));
    });

    testWidgets('a picture result can go to the gallery', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.aadhaar);
      await create(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('safeid-gallery')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('safeid-gallery')));
      await tester.pump();
      expect(save.gallery.single.single, endsWith('.jpg'));
    });

    testWidgets('with nothing covered the person is asked before the copy is made', (tester) async {
      await open(tester);
      await pickGallery(tester);
      await tapKind(tester, IdKind.pan);
      await tester.ensureVisible(find.byKey(const ValueKey('safeid-create')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('safeid-create')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing is covered'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(results(), isEmpty);
      expect(find.byKey(const ValueKey('safeid-preview')), findsOneWidget);
    });

    testWidgets('when the text cannot be read the person is told and can still draw boxes', (tester) async {
      await open(tester, ocr: _Ocr(null));
      await pickGallery(tester);
      expect(find.byKey(const ValueKey('safeid-read-failed')), findsOneWidget);
      expect(find.text('0 areas covered'), findsOneWidget);
      expect(find.byKey(const ValueKey('safeid-preview')), findsOneWidget);
    });

    testWidgets('a picture that cannot be opened is reported and nothing is shown', (tester) async {
      File(picture).writeAsStringSync('not a picture');
      await open(tester);
      await pickGallery(tester);
      expect(find.byKey(const ValueKey('safeid-preview')), findsNothing);
      expect(find.textContaining('could not be opened'), findsOneWidget);
    });

    testWidgets('leaving the page deletes the working copy', (tester) async {
      await open(tester);
      await pickGallery(tester);
      List<String> work() => Directory(p.join(dir.path, 'work')).listSync().map((f) => p.basename(f.path)).where((n) => n.startsWith('safeid_work')).toList();
      expect(work(), hasLength(1));
      await tester.pumpWidget(const SizedBox());
      expect(work(), isEmpty);
    });

    for (final w in [320.0, 900.0]) {
      testWidgets('fits a ${w.toInt()} px wide screen', (tester) async {
        await open(tester, width: w);
        await pickGallery(tester);
        await tapKind(tester, IdKind.aadhaar);
        await create(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _Ocr implements OcrEngine {
  _Ocr(this.page);
  final OcrPageResult? page;

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async =>
      page == null ? const Err(OcrFailure('The text could not be read.')) : Ok(page!);
}

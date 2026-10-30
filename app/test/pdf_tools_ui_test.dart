import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_page_tools.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_redact_processor.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_forms.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_redact.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_crop_cubit.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_crop_page.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_images_cubit.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_images_page.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_redact_cubit.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_redact_page.dart';
import 'package:doculoom/features/reader/data/pdf_page_reader.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_model.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_rewriter.dart';

import 'support/pdf_builder.dart';
import 'support/pdf_ui_fakes.dart';

void main() {
  late Directory dir;
  late FakeToolsService tools;
  late FakeRedactService redact;
  late FakeShare share;
  late FakeSave save;

  setUp(() async {
    dir = tempDir();
    tools = FakeToolsService();
    redact = FakeRedactService();
    share = FakeShare();
    save = FakeSave();
    await sl.reset();
    sl
      ..registerSingleton<PdfPageToolsService>(tools)
      ..registerSingleton<PdfRedactService>(redact)
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<SaveService>(save);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  void mockPaths(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
  }

  void phone(WidgetTester tester, {double width = 400, double height = 900}) {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  group('picture shape', () {
    test('is read from a JPEG and a PNG header', () {
      expect(imageAspect(samplePage(w: 60, h: 80)), closeTo(0.75, 0.001));
      expect(imageAspect(samplePage(w: 100, h: 50, png: true)), closeTo(2, 0.001));
      expect(imageAspect(Uint8List.fromList([1, 2, 3])), isNull);
      expect(imageAspect(Uint8List(0)), isNull);
    });
  });

  group('crop', () {
    PdfCropCubit make({int pages = 3, Future<FakeRenderer> Function(String)? open}) => PdfCropCubit(
      service: tools,
      outputDir: () async => dir,
      openRenderer: open ?? (_) async => FakeRenderer(pages),
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    test('each page keeps its own cut, and moving between pages does not mix them up', () async {
      final c = make();
      await c.pick('/x/a.pdf');
      expect(c.state.pageCount, 3);
      c.setSide(CropSide.left, 0.1);
      c.goTo(1);
      expect(c.state.insetsOf(1).isNone, isTrue);
      c.setSide(CropSide.top, 0.2);
      c.goTo(0);
      expect(c.state.insetsOf(0), const CropInsets(left: 0.1));
      expect(c.state.plan.keys, [0, 1]);
      await c.close();
    });

    test('"same cut for every page" copies the cut on view to all pages, and a slider moves all of them', () async {
      final c = make();
      await c.pick('/x/a.pdf');
      c.setSide(CropSide.right, 0.15);
      c.setAll(true);
      expect(c.state.plan.keys, [0, 1, 2]);
      c.goTo(2);
      c.setSide(CropSide.bottom, 0.05);
      expect(c.state.insetsOf(0), const CropInsets(right: 0.15, bottom: 0.05));
      c.setAll(false);
      expect(c.state.insetsOf(1), const CropInsets(), reason: 'back to the cuts of each page, which were never set');
      await c.close();
    });

    test('a slider never goes beyond 45% and reset clears everything', () async {
      final c = make();
      await c.pick('/x/a.pdf');
      c.setSide(CropSide.left, 0.9);
      expect(c.state.insetsOf(0).left, 0.45);
      c.setSide(CropSide.left, -1);
      expect(c.state.insetsOf(0).left, 0);
      c.setSide(CropSide.top, 0.2);
      c.reset();
      expect(c.state.plan, isEmpty);
      await c.close();
    });

    test('saving sends only the pages that are cut, names the file after the PDF, and offers the result', () async {
      final c = make();
      await c.pick('/x/Lease agreement.pdf');
      c.goTo(1);
      c.setSide(CropSide.left, 0.1);
      await c.save();
      expect(tools.crops.single.keys, [1]);
      expect(c.state.status, CropStatus.done);
      expect(p.basename(c.state.result!.path), 'Lease agreement_cropped_1700000000000.pdf');
      await c.close();
    });

    test('saving with no cut asks for one; a failed save shows the failure and no result', () async {
      final c = make();
      await c.pick('/x/a.pdf');
      await c.save();
      expect(tools.crops, isEmpty);
      expect(c.state.failure?.message, contains('Choose how much to cut off'));
      c.setSide(CropSide.left, 0.1);
      tools.failure = const ExportFailure('This PDF is protected with a password.');
      await c.save();
      expect(c.state.result, isNull);
      expect(c.state.failure?.message, contains('password'));
      await c.close();
    });

    test('a PDF that cannot be opened, or has no pages, is reported and nothing is left open', () async {
      final broken = make(open: (_) async => throw StateError('no'));
      await broken.pick('/x/a.pdf');
      expect(broken.state.pageCount, 0);
      expect(broken.state.failure?.message, contains('could not be opened'));
      await broken.close();

      final empty = make(pages: 0);
      await empty.pick('/x/a.pdf');
      expect(empty.state.failure?.message, contains('Nothing could be read'));
      await empty.close();
    });

    testWidgets('the screen shows the page, the sliders move the cut, and the result can be shared', (tester) async {
      phone(tester);
      mockPaths(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PdfCropPage(openRenderer: (_) async => FakeRenderer(2)),
        ),
      );
      expect(find.byKey(const ValueKey('crop-pick')), findsOneWidget);
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfCropCubit>();
      await tester.runAsync(() => cubit.pick('/x/a.pdf'));
      await tester.pump();
      await settle(tester);
      expect(find.text('Page 1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('crop-shade')), findsOneWidget);

      await tester.drag(find.byKey(const ValueKey('crop-slider-left')), const Offset(60, 0));
      await tester.pump();
      expect(cubit.state.insetsOf(0).left, greaterThan(0.05));
      expect(find.textContaining('%'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('crop-next')));
      await settle(tester);
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(cubit.state.insetsOf(1).isNone, isTrue);
      await tester.tap(find.byKey(const ValueKey('crop-prev')));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('crop-save')));
      await settle(tester);
      expect(tools.crops.single.keys, [0]);
      expect(find.byKey(const ValueKey('pdf-result')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pdf-result-share')));
      await settle(tester);
      expect(share.shared.single.paths.single, contains('_cropped_'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('saving with nothing cut shows a message and fits a small phone', (tester) async {
      phone(tester, width: 320, height: 568);
      mockPaths(tester);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.4)),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: PdfCropPage(openRenderer: (_) async => FakeRenderer(1)),
          ),
        ),
      );
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfCropCubit>();
      await tester.runAsync(() => cubit.pick('/x/a.pdf'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('crop-save')));
      await settle(tester);
      expect(find.textContaining('Choose how much to cut off'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('pictures', () {
    late FakePicturePages pages;

    PdfImagesCubit make({int count = 4, bool failOpen = false}) {
      pages = FakePicturePages(count, failOpen: failOpen);
      return PdfImagesCubit(tools: tools, outputDir: () async => dir, pages: () => pages, now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000));
    }

    test('all pages by default, as JPEG at the standard size, one file each named after the page', () async {
      final c = make();
      await c.pick('/x/Report.pdf');
      await c.makePages();
      expect(pages.rendered.map((r) => r.page), [0, 1, 2, 3]);
      expect(pages.rendered.every((r) => r.width == 1240 && !r.png), isTrue);
      expect(c.state.files.map(p.basename), ['Report_page_01.jpg', 'Report_page_02.jpg', 'Report_page_03.jpg', 'Report_page_04.jpg']);
      expect(c.state.files.every((f) => File(f).existsSync()), isTrue);
      expect(c.state.status, ImagesStatus.done);
      expect(c.state.mime, 'image/jpeg');
      await c.close();
    });

    test('a range, PNG and high detail are all used', () async {
      final c = make(count: 12);
      await c.pick('/x/Report.pdf');
      c.setRange('2-3, 12');
      c.setPng(true);
      c.setHigh(true);
      await c.makePages();
      expect(pages.rendered.map((r) => r.page), [1, 2, 11]);
      expect(pages.rendered.every((r) => r.width == 2480 && r.png), isTrue);
      expect(c.state.files.map(p.basename), ['Report_page_02.png', 'Report_page_03.png', 'Report_page_12.png']);
      expect(c.state.mime, 'image/png');
      await c.close();
    });

    test('a page that is not in the PDF, or a range that makes no sense, is explained and nothing is drawn', () async {
      final c = make();
      await c.pick('/x/Report.pdf');
      c.setRange('9');
      await c.makePages();
      expect(c.state.failure?.message, contains('Page 9 does not exist'));
      c.setRange('3-1');
      await c.makePages();
      expect(c.state.failure?.message, contains('goes backwards'));
      c.setRange('x');
      await c.makePages();
      expect(c.state.failure?.message, contains('is not a page or a range'));
      expect(pages.rendered, isEmpty);
      await c.close();
    });

    test('pictures found inside the PDF are listed with the number that could not be saved', () async {
      final c = make();
      tools.extraction = ExtractionResult(
        images: [
          ExtractedImage(path: p.join(dir.path, 'a.jpg'), page: 1, width: 10, height: 10, bytes: 3),
          ExtractedImage(path: p.join(dir.path, 'b.png'), page: 2, width: 10, height: 10, bytes: 3),
        ],
        skipped: 2,
      );
      await c.pick('/x/Report.pdf');
      c.setMode(ImagesMode.inside);
      await c.findPictures();
      expect(c.state.files.map(p.basename), ['a.jpg', 'b.png']);
      expect(c.state.skipped, 2);
      expect(c.state.searched, isTrue);
      expect(c.state.mime, 'image/*');
      expect(tools.extractions.single, contains('Report_inside_1700000000000'));
      c.setMode(ImagesMode.pages);
      expect(c.state.files, isEmpty, reason: 'the list belongs to the way it was made');
      await c.close();
    });

    test('a failure while looking for pictures is shown and nothing is claimed to be found', () async {
      final c = make();
      tools.failure = const ExportFailure('This file is not a readable PDF. It may be damaged.');
      await c.pick('/x/Report.pdf');
      await c.findPictures();
      expect(c.state.failure?.message, contains('not a readable PDF'));
      expect(c.state.searched, isFalse);
      expect(c.state.files, isEmpty);
      await c.close();
    });

    test('a PDF that cannot be opened is reported', () async {
      final c = make(failOpen: true);
      await c.pick('/x/Report.pdf');
      expect(c.state.open, isFalse);
      expect(c.state.failure?.message, contains('could not be opened'));
      await c.close();
    });

    testWidgets('the screen makes pages, offers sharing and gallery, and the other mode says when nothing is inside', (tester) async {
      phone(tester);
      mockPaths(tester);
      final fake = FakePicturePages(3);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PdfImagesPage(pages: () => fake),
        ),
      );
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfImagesCubit>();
      await tester.runAsync(() => cubit.pick('/x/Report.pdf'));
      await tester.pump();
      expect(find.text('3 pages'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('images-range')), '1-2');
      await tester.tap(find.byKey(const ValueKey('images-make')));
      await settle(tester);
      expect(find.text('2 pages are ready'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('images-share')));
      await tester.tap(find.byKey(const ValueKey('images-share')));
      await settle(tester);
      expect(share.shared.single.paths, hasLength(2));
      expect(share.shared.single.mime, 'image/jpeg');
      await tester.tap(find.byKey(const ValueKey('images-gallery')));
      await settle(tester);
      expect(save.gallery.single, hasLength(2));
      expect(find.textContaining('Saved 2 pictures'), findsOneWidget);

      await tester.tap(find.text('Pictures inside'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('images-find')));
      await settle(tester);
      expect(find.text('No pictures found'), findsOneWidget);
      expect(find.textContaining('A scanned PDF is made of page pictures'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong page range is shown on the screen', (tester) async {
      phone(tester);
      mockPaths(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PdfImagesPage(pages: () => FakePicturePages(2)),
        ),
      );
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfImagesCubit>();
      await tester.runAsync(() => cubit.pick('/x/Report.pdf'));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('images-range')), '5');
      await tester.tap(find.byKey(const ValueKey('images-make')));
      await settle(tester);
      expect(find.byKey(const ValueKey('images-failure')), findsOneWidget);
      expect(find.textContaining('Page 5 does not exist'), findsOneWidget);
    });
  });

  group('hide text', () {
    PdfRedactCubit make({int count = 2, FakePicturePages? pages}) => PdfRedactCubit(
      service: redact,
      outputDir: () async => dir,
      pages: () => pages ?? FakePicturePages(count),
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    test('a box can be drawn from any corner, is kept inside the page, and tiny ones are dropped', () async {
      final c = make();
      await c.pick('/x/a.pdf');
      expect(c.addBox(0, 0.6, 0.5, 0.2, 0.3), isTrue);
      expect(c.state.boxes.single, const RedactBox(page: 0, left: 0.2, top: 0.3, right: 0.6, bottom: 0.5));
      expect(c.addBox(1, -0.5, -0.5, 2, 0.1), isTrue);
      expect(c.state.boxes.last, const RedactBox(page: 1, left: 0, top: 0, right: 1, bottom: 0.1));
      expect(c.addBox(0, 0.5, 0.5, 0.505, 0.9), isFalse, reason: 'a tap or a slip is not a box');
      expect(c.addBox(7, 0.1, 0.1, 0.5, 0.5), isFalse, reason: 'no such page');
      expect(c.state.boxes, hasLength(2));
      await c.close();
    });

    test('undo and remove take boxes away, and saving needs at least one', () async {
      final c = make();
      await c.pick('/x/a.pdf');
      await c.save();
      expect(redact.calls, isEmpty);
      expect(c.state.failure?.message, contains('Draw over what to hide'));
      c.addBox(0, 0.1, 0.1, 0.4, 0.2);
      c.addBox(0, 0.5, 0.5, 0.9, 0.6);
      c.undo();
      expect(c.state.boxes, hasLength(1));
      c.removeBox(c.state.boxes.single);
      expect(c.state.boxes, isEmpty);
      await c.close();
    });

    test('saving sends every box with the detail setting and offers a file named after the PDF', () async {
      final c = make();
      await c.pick('/x/Payslip.pdf');
      c.addBox(0, 0.1, 0.1, 0.4, 0.2);
      c.setHigh(true);
      await c.save();
      expect(redact.calls.single.boxes, hasLength(1));
      expect(redact.calls.single.high, isTrue);
      expect(p.basename(c.state.result!.path), 'Payslip_redacted_1700000000000.pdf');
      await c.close();
    });

    test('a failure is shown and no result is offered; changing the boxes afterwards drops an old result', () async {
      final c = make();
      await c.pick('/x/Payslip.pdf');
      c.addBox(0, 0.1, 0.1, 0.4, 0.2);
      redact.failure = const ExportFailure('This PDF could not be processed.');
      await c.save();
      expect(c.state.result, isNull);
      expect(c.state.failure, isNotNull);
      redact.failure = null;
      await c.save();
      expect(c.state.result, isNotNull);
      c.addBox(0, 0.5, 0.5, 0.9, 0.6);
      expect(c.state.result, isNull, reason: 'the file no longer matches what is on screen');
      await c.close();
    });

    testWidgets('dragging in Hide mode draws a black box; scrolling mode does not; a box can be removed', (tester) async {
      phone(tester);
      mockPaths(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PdfRedactPage(pages: () => FakePicturePages(1)),
        ),
      );
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfRedactCubit>();
      await tester.runAsync(() => cubit.pick('/x/a.pdf'));
      await tester.pump();
      await settle(tester);
      expect(find.byKey(const ValueKey('draw-0')), findsNothing, reason: 'scrolling mode');

      await tester.tap(find.byKey(const ValueKey('redact-draw')));
      await tester.pump();
      expect(find.textContaining('Drag on a page'), findsOneWidget);
      final rect = tester.getRect(find.byKey(const ValueKey('draw-0')));
      final gesture = await tester.startGesture(Offset(rect.left + rect.width * 0.2, rect.top + rect.height * 0.3));
      await gesture.moveTo(Offset(rect.left + rect.width * 0.6, rect.top + rect.height * 0.4));
      await gesture.up();
      await tester.pump();
      expect(cubit.state.boxes, hasLength(1));
      final box = cubit.state.boxes.single;
      expect(box.left, closeTo(0.2, 0.03));
      expect(box.right, closeTo(0.6, 0.03));
      expect(box.top, closeTo(0.3, 0.03));
      expect(box.bottom, closeTo(0.4, 0.03));
      expect(find.text('Hide 1 area and save'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('box-0-${box.left.toStringAsFixed(3)}-${box.top.toStringAsFixed(3)}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('redact-remove')));
      await tester.pumpAndSettle();
      expect(cubit.state.boxes, isEmpty);
    });

    testWidgets('saving shows the result and says what happened to the text', (tester) async {
      phone(tester);
      mockPaths(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PdfRedactPage(pages: () => FakePicturePages(1)),
        ),
      );
      final cubit = tester.element(find.byType(Scaffold).first).read<PdfRedactCubit>();
      await tester.runAsync(() => cubit.pick('/x/a.pdf'));
      await tester.pump();
      cubit.addBox(0, 0.1, 0.1, 0.5, 0.2);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('redact-save')));
      await settle(tester);
      expect(redact.calls, hasLength(1));
      expect(find.textContaining('what was under them is gone'), findsOneWidget);
      expect(find.byKey(const ValueKey('pdf-result')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the start screen explains that the text is not just covered', (tester) async {
      phone(tester, width: 320, height: 568);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PdfRedactPage()));
      expect(find.textContaining('is not in the file at all'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('hiding really removes what was there', () {
    test('the picture of a page has the box painted black and the rest unchanged', () {
      final src = img.Image(width: 200, height: 100, numChannels: 3);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(src, x1: 20, y1: 20, x2: 120, y2: 30, color: img.ColorRgb8(20, 20, 20));
      final out = p.join(dir.path, 'page.jpg');
      final size = blackenPage(Uint8List.fromList(img.encodePng(src)), const [RedactBox(page: 0, left: 0.05, top: 0.1, right: 0.7, bottom: 0.4)], out);
      expect(size, (width: 200, height: 100));
      final done = img.decodeJpg(File(out).readAsBytesSync())!;
      final inside = done.getPixel(70, 25), corner = done.getPixel(180, 90);
      expect(inside.r, lessThan(10));
      expect(corner.r, greaterThan(240));
      // Around the old text, 12 px of every side of the box is black too, so no stroke of a letter can be seen at the edge.
      expect(done.getPixel(10, 15).r, lessThan(10), reason: 'one pixel margin around the box');
    });

    test('a whole PDF: every page becomes a picture, the covered words are not in the file, and the black box is', () async {
      // A source PDF with real text on it; the renderer fake draws that text as dark marks where it is.
      final source = TestPdf()..page(text: 'Account 4455 6677 8899');
      final src = File(p.join(dir.path, 'bank.pdf'))..writeAsBytesSync(source.finish());

      final fake = _TextlikePages();
      final out = p.join(dir.path, 'bank_redacted.pdf');
      final result = await PdfRedactProcessor(
        pages: () => fake,
      ).redact(sourcePath: src.path, outputPath: out, boxes: const [RedactBox(page: 0, left: 0.0, top: 0.2, right: 1.0, bottom: 0.4)]);
      expect(result.valueOrNull, isNotNull);

      final bytes = File(out).readAsBytesSync();
      final file = PdfReader(readPdfDocument(bytes));
      expect(file.pages(), hasLength(1));
      // No text at all in the new file: the page is one picture.
      final page = file.pages().single;
      final content =
          file.decoded(file.res(page.dict['Contents']) is PdfArray ? (file.list(page.dict['Contents'])).first : page.dict['Contents']) ?? Uint8List(0);
      expect(String.fromCharCodes(content), isNot(contains('Tj')));
      expect(interpretPage(file, page).glyphs, isEmpty);
      expect(String.fromCharCodes(bytes), isNot(contains('Account')));

      final pictures = extractPdfPictures(bytes).pictures;
      expect(pictures, hasLength(1));
      final decoded = img.decodeJpg(pictures.single.bytes)!;
      final h = decoded.height;
      // The marks that stood for the text, in the covered band, are gone; the band is black.
      expect(decoded.getPixel(decoded.width ~/ 2, (h * 0.3).round()).r, lessThan(10));
      // The mark outside the band is still there.
      expect(decoded.getPixel(decoded.width ~/ 2, (h * 0.6).round()).r, lessThan(60));
      expect(decoded.getPixel(5, (h * 0.9).round()).r, greaterThan(240));
      expect(Directory('$out.work').existsSync(), isFalse, reason: 'working files are removed');
    });

    test('nothing to hide, a missing file and a box on a page that does not exist are refused', () async {
      final processor = PdfRedactProcessor(pages: () => FakePicturePages(1));
      final none = await processor.redact(sourcePath: p.join(dir.path, 'x.pdf'), outputPath: p.join(dir.path, 'o.pdf'), boxes: const []);
      expect(none.failureOrNull?.message, contains('Draw over what to hide'));
      final missing = await processor.redact(
        sourcePath: p.join(dir.path, 'x.pdf'),
        outputPath: p.join(dir.path, 'o.pdf'),
        boxes: const [RedactBox(page: 0, left: 0, top: 0, right: 0.5, bottom: 0.5)],
      );
      expect(missing.failureOrNull?.message, contains('could not be found'));
      final src = File(p.join(dir.path, 'a.pdf'))..writeAsBytesSync(Uint8List(8));
      final far = await processor.redact(
        sourcePath: src.path,
        outputPath: p.join(dir.path, 'o.pdf'),
        boxes: const [RedactBox(page: 4, left: 0, top: 0, right: 0.5, bottom: 0.5)],
      );
      expect(far.failureOrNull?.message, contains('not in this PDF'));
      expect(File(p.join(dir.path, 'o.pdf')).existsSync(), isFalse);
    });
  });
}

/// Draws two dark bars as a page: one in the band that will be hidden (at 30% of the height) and one below it (at 60%).
class _TextlikePages extends FakePicturePages {
  _TextlikePages() : super(1);

  @override
  Future<Uint8List> render(int page, {required int width, required bool png}) async {
    final image = img.Image(width: 300, height: 400, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(image, x1: 30, y1: 115, x2: 270, y2: 125, color: img.ColorRgb8(30, 30, 30));
    img.fillRect(image, x1: 30, y1: 235, x2: 270, y2: 245, color: img.ColorRgb8(30, 30, 30));
    return Uint8List.fromList(img.encodePng(image));
  }
}

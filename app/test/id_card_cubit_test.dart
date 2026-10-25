import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:scanvault/app/di.dart';
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/id_card/domain/id_card.dart';
import 'package:scanvault/features/id_card/presentation/id_card_cubit.dart';
import 'package:scanvault/features/id_card/presentation/id_card_page.dart';
import 'package:scanvault/features/photo_tools/domain/crop_math.dart';
import 'package:scanvault/features/photo_tools/domain/passport_maker.dart';

class _Maker implements IdCardMaker {
  _Maker(this.dir);
  final Directory dir;
  final prepared = <({String source, bool rotate})>[];
  List<CardCrop> lastSides = const [];
  IdCardOptions? lastOptions;
  Failure? prepareFailure;

  @override
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false}) async {
    prepared.add((source: sourcePath, rotate: rotateRight));
    if (prepareFailure != null) return Err(prepareFailure!);
    // Landscape card photos, 1600 x 1000; a turned one is portrait.
    final w = rotateRight ? 1000 : 1600, h = rotateRight ? 1600 : 1000;
    File(outputPath).writeAsBytesSync(img.encodeJpg(img.Image(width: 16, height: 10, numChannels: 3), quality: 50));
    return Ok(WorkingPhoto(path: outputPath, width: w, height: h));
  }

  @override
  Future<Result<CardSheetFiles>> sheet({required List<CardCrop> sides, required IdCardOptions options, required String outputBase}) async {
    lastSides = sides;
    lastOptions = options;
    final jpg = '$outputBase.jpg';
    File(jpg).writeAsBytesSync(img.encodeJpg(img.Image(width: 21, height: 30, numChannels: 3), quality: 50));
    return Ok(CardSheetFiles(jpgPath: jpg, pdfPath: '$outputBase.pdf', cards: sides.length, scale: 1, shrunk: false));
  }
}

void main() {
  late Directory dir;
  late _Maker maker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_idc');
    maker = _Maker(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  IdCardCubit make() => IdCardCubit(maker: maker, workDir: () async => dir);

  group('cubit', () {
    test('adding a photo opens the crop with the photo covering the frame', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      expect(c.state.editing, CardSideId.front);
      expect(c.state.front.has, isTrue);
      expect(c.state.back.has, isFalse);
      expect(c.state.front.view!.zoom, 1);
      expect(c.state.busy, isFalse);
      await c.close();
    });

    test('a photo that cannot be read reports it and changes nothing', () async {
      maker.prepareFailure = const ExportFailure('This photo could not be opened.');
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      expect(c.state.failure!.message, contains('could not be opened'));
      expect(c.state.front.has, isFalse);
      expect(c.state.editing, isNull);
      await c.close();
    });

    test('done goes back to the overview, adjust returns to the crop', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      c.done();
      expect(c.state.editing, isNull);
      c.edit(CardSideId.back);
      expect(c.state.editing, isNull, reason: 'nothing to adjust yet');
      c.edit(CardSideId.front);
      expect(c.state.editing, CardSideId.front);
      await c.close();
    });

    test('zooming and moving stay inside the photo', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      c.setZoom(3);
      expect(c.state.front.view!.zoom, 3);
      c.pan(-5, -5);
      final r = c.state.front.view!.rect(1600, 1000, c.state.frameW, c.state.frameH);
      expect(r.left, greaterThanOrEqualTo(-0.001));
      expect(r.right, lessThanOrEqualTo(1600.001));
      expect(r.top, greaterThanOrEqualTo(-0.001));
      expect(r.bottom, lessThanOrEqualTo(1000.001));
      c.setZoom(100);
      expect(c.state.front.view!.zoom, CropView.maxZoom);
      c.resetView();
      expect(c.state.front.view!.zoom, 1);
      await c.close();
    });

    test('rotate makes a turned copy and starts the crop again', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      c.setZoom(2);
      await c.rotate();
      expect(maker.prepared.last.rotate, isTrue);
      expect(c.state.front.photo!.height, 1600);
      expect(c.state.front.view!.zoom, 1);
      await c.close();
    });

    test('a new card size starts every crop again, other settings keep them', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      c.setZoom(2.5);
      c.setOptions(c.state.options.copyWith(blackAndWhite: true));
      expect(c.state.front.view!.zoom, 2.5);
      c.setOptions(c.state.options.copyWith(size: CardSize.a6));
      expect(c.state.front.view!.zoom, 1);
      expect(c.state.frameW, 148);
      await c.close();
    });

    test('the front is required', () async {
      final c = make();
      await c.create();
      expect(c.state.failure!.message, contains('front'));
      expect(maker.lastSides, isEmpty);
      await c.close();
    });

    test('creates a page from one side or both, cropped to the shape of the card', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      await c.create();
      expect(maker.lastSides.length, 1);
      expect(c.state.result!.cards, 1);
      final first = maker.lastSides.single;
      expect(first.width / first.height, closeTo(CardSize.idCard.aspect, 0.001));
      await c.setPhoto(CardSideId.back, '/b.jpg');
      c.setZoom(2);
      await c.create();
      expect(maker.lastSides.length, 2);
      final zoomed = maker.lastSides[1];
      expect(zoomed.width, closeTo(first.width / 2, 0.5));
      expect(maker.lastOptions, const IdCardOptions());
      await c.close();
    });

    test('changing anything clears the earlier page; removing a side too', () async {
      final c = make();
      await c.setPhoto(CardSideId.front, '/a.jpg');
      await c.setPhoto(CardSideId.back, '/b.jpg');
      await c.create();
      expect(c.state.result, isNotNull);
      c.setOptions(c.state.options.copyWith(paper: CardPaper.letter));
      expect(c.state.result, isNull);
      await c.create();
      c.remove(CardSideId.back);
      expect(c.state.result, isNull);
      expect(c.state.back.has, isFalse);
      expect(c.state.front.has, isTrue);
      await c.close();
    });
  });

  group('page', () {
    Future<IdCardCubit> show(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      await sl.reset();
      sl.registerSingleton<IdCardMaker>(maker);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const IdCardPage()));
      await tester.pump();
      return tester.element(find.byType(Scaffold).first).read<IdCardCubit>();
    }

    testWidgets('starts with two empty slots and a disabled create button', (tester) async {
      await show(tester);
      expect(find.text('Add photo'), findsNWidgets(2));
      expect(find.text('Back (optional)'), findsOneWidget);
      final create = find.widgetWithText(FilledButton, 'Create page');
      await tester.scrollUntilVisible(create, 200, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<FilledButton>(create).onPressed, isNull);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('adds both sides, adjusts and creates the page at ${width.toInt()} px', (tester) async {
        final cubit = await show(tester, width: width);
        await tester.runAsync(() => cubit.setPhoto(CardSideId.front, '/a.jpg'));
        await tester.pump();
        expect(find.text('Adjust the front'), findsOneWidget, reason: 'crop screen title');
        expect(find.byKey(const ValueKey('card-crop')), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pump();
        expect(find.text('Copy of ID card'), findsOneWidget);
        expect(find.text('Adjust'), findsOneWidget);
        expect(find.text('Replace'), findsOneWidget);
        await tester.runAsync(() => cubit.setPhoto(CardSideId.back, '/b.jpg'));
        cubit.done();
        await tester.pump();
        expect(find.text('Adjust'), findsNWidgets(2));

        final create = find.widgetWithText(FilledButton, 'Create page');
        await tester.scrollUntilVisible(create, 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(create);
        await tester.pump();
        await tester.tap(create);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        final ready = find.text('Your page with both sides is ready');
        await tester.scrollUntilVisible(ready, 200, scrollable: find.byType(Scrollable).first);
        expect(ready, findsOneWidget);
        expect(find.textContaining('real size of the card on A4'), findsOneWidget);
        expect(find.text('Print'), findsOneWidget);
        expect(find.text('Share PDF'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a custom card size can be typed', (tester) async {
      await show(tester);
      await tester.scrollUntilVisible(find.text('Custom'), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Custom'));
      await tester.pump();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '100');
      await tester.enterText(find.byType(TextField).last, '60');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.text('100 x 60 mm'), findsWidgets);
    });

    testWidgets('a custom size that cannot be printed is refused', (tester) async {
      await show(tester);
      await tester.scrollUntilVisible(find.text('Custom'), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Custom'));
      await tester.pump();
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5');
      await tester.enterText(find.byType(TextField).last, '60');
      await tester.tap(find.text('Use'));
      await tester.pump();
      expect(find.textContaining('between 20 and 280 mm'), findsOneWidget);
    });
  });
}

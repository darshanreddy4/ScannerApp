import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/app/di.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/photo_tools/domain/passport_maker.dart';
import 'package:scanvault/features/photo_tools/domain/photo_compressor.dart';
import 'package:scanvault/features/photo_tools/domain/photo_specs.dart';
import 'package:scanvault/features/photo_tools/presentation/passport_cubit.dart';
import 'package:scanvault/features/photo_tools/presentation/passport_photo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Maker implements PassportMaker {
  final rendered = <RenderRequest>[];
  final sheets = <SheetPaper>[];

  @override
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false}) async =>
      Ok(WorkingPhoto(path: outputPath, width: 3000, height: 4000));

  @override
  Future<Result<RenderedPhoto>> render(RenderRequest request) async {
    rendered.add(request);
    return Ok(RenderedPhoto(path: request.outputPath, bytes: 41000, width: request.outWidth, height: request.outHeight));
  }

  @override
  Future<Result<SheetFiles>> sheet({
    required String photoPath,
    required PhotoSpec spec,
    required SheetPaper paper,
    int? copies,
    required String outputBase,
  }) async {
    sheets.add(paper);
    return Ok(SheetFiles(jpgPath: '$outputBase.jpg', pdfPath: '$outputBase.pdf', copies: copies ?? 6, columns: 2, rows: 3));
  }
}

class _Compressor implements PhotoCompressor {
  final targets = <int>[];

  @override
  Future<Result<CompressedPhoto>> compress({required String sourcePath, required String outputPath, required CompressOptions options}) async {
    targets.add(options.targetBytes!);
    return Ok(
      CompressedPhoto(path: outputPath, bytes: options.targetBytes! - 500, width: 413, height: 531, originalBytes: 41000, metTarget: true, quality: 60),
    );
  }
}

void main() {
  late Directory dir;
  late _Maker maker;
  late _Compressor compressor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('sv_pp');
    maker = _Maker();
    compressor = _Compressor();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<PassportCubit> open(WidgetTester tester, {double width = 400, double height = 800}) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
    await sl.reset();
    sl
      ..registerSingleton<PassportMaker>(maker)
      ..registerSingleton<PhotoCompressor>(compressor);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PassportPhotoPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    return tester.element(find.byType(Scaffold).first).read<PassportCubit>();
  }

  Future<void> toEdit(WidgetTester tester, PassportCubit cubit) async {
    await tester.runAsync(() => cubit.pickPhoto('${dir.path}/p.jpg'));
    await tester.pump();
  }

  group('choose', () {
    testWidgets('starts with India, its photo types and a custom option', (tester) async {
      await open(tester);
      expect(find.text('India'), findsOneWidget);
      expect(find.text('Passport'), findsOneWidget);
      expect(find.textContaining('35 x 45 mm'), findsWidgets);
      expect(find.text('Visa and OCI'), findsOneWidget);
      expect(find.text('PAN card'), findsOneWidget);
      expect(find.text('Custom size'), findsOneWidget);
      expect(find.text('Take a photo', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('Sizes can change', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the country list can be searched and changes the photo types', (tester) async {
      final cubit = await open(tester);
      await tester.tap(find.text('India'));
      await tester.pumpAndSettle();
      expect(find.text('Search country'), findsOneWidget);

      await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'unit');
      await tester.pumpAndSettle();
      expect(find.text('United States'), findsOneWidget);
      expect(find.text('United Kingdom'), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('India')), findsNothing);

      await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'zzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('No country found'), findsOneWidget);

      await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'canada');
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Canada')));
      await tester.pumpAndSettle();

      expect(cubit.state.countryCode, 'CA');
      expect(find.text('Passport'), findsOneWidget);
      expect(find.text('Visa and permits'), findsOneWidget);
      expect(find.textContaining('50 x 70 mm'), findsWidgets);

      // The choice is remembered for next time.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('photo_country'), 'CA');
    });

    testWidgets('the remembered country is used next time', (tester) async {
      SharedPreferences.setMockInitialValues({'photo_country': 'JP'});
      final cubit = await open(tester);
      expect(cubit.state.countryCode, 'JP');
      expect(find.text('Japan'), findsOneWidget);
    });

    testWidgets('picking another photo type selects it', (tester) async {
      final cubit = await open(tester);
      await tester.tap(find.text('PAN card'));
      await tester.pump();
      expect(cubit.state.spec.id, 'pan');
      expect((cubit.state.spec.widthMm, cubit.state.spec.heightMm), (25, 35));
    });

    testWidgets('a custom size in millimetres, inches or pixels', (tester) async {
      final cubit = await open(tester);
      await tester.tap(find.text('Custom size'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.text('Enter both width and height.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Width'), '30');
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '40');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(cubit.state.spec.id, 'custom');
      expect((cubit.state.spec.widthMm, cubit.state.spec.heightMm), (30, 40));
    });

    testWidgets('pixel sizes are exact and out of range sizes are refused', (tester) async {
      final cubit = await open(tester);
      await tester.tap(find.text('Custom size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('pixels'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Width'), '10');
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '300');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.textContaining('between 50 and 3000 pixels'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Width'), '200');
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '267');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect((cubit.state.spec.exactWidthPx, cubit.state.spec.exactHeightPx), (200, 267));
      expect(find.textContaining('200 x 267 px'), findsWidgets);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('fits a ${width.toInt()} dp wide screen', (tester) async {
        await open(tester, width: width, height: 700);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('adjust', () {
    for (final size in [const Size(320, 568), const Size(400, 800), const Size(900, 700)]) {
      testWidgets('the crop screen fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        final cubit = await open(tester, width: size.width, height: size.height);
        await toEdit(tester, cubit);
        expect(find.text('Adjust the photo'), findsOneWidget);
        expect(find.textContaining('Drag to move'), findsOneWidget);
        expect(find.text('Rotate'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Create photo'), 200);
        await tester.ensureVisible(find.text('Create photo'));
        await tester.pump();
        expect(find.text('Create photo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the frame has the shape of the photo', (tester) async {
      final cubit = await open(tester);
      await tester.tap(find.text('PAN card'));
      await tester.pump();
      await toEdit(tester, cubit);
      final frame = tester.getSize(find.byKey(const ValueKey('crop-frame')));
      expect(frame.width / frame.height, closeTo(25 / 35, 0.01));
    });

    testWidgets('dragging moves the photo, the slider zooms and Reset undoes it', (tester) async {
      final cubit = await open(tester);
      await toEdit(tester, cubit);
      await tester.runAsync(() async {});
      cubit.setZoom(3);
      await tester.pump();
      final before = cubit.state.view!.centerY;
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('crop-frame'))));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, 8));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      expect(cubit.state.view!.centerY, lessThan(before), reason: 'the photo follows the finger down');

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(cubit.state.view!.zoom, 1);
    });

    testWidgets('replacing the background shows colours and strength', (tester) async {
      final cubit = await open(tester);
      await toEdit(tester, cubit);
      await tester.scrollUntilVisible(find.byType(Switch), 200);
      await tester.ensureVisible(find.byType(Switch));
      await tester.pump();
      expect(find.text('Light blue'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Light blue'), 100);
      await tester.ensureVisible(find.text('Light blue'));
      await tester.pump();
      expect(find.text('Light blue'), findsOneWidget);
      await tester.tap(find.text('Light blue'));
      await tester.pump();
      expect(cubit.state.background, PhotoBackground.lightBlue);
      expect(cubit.state.replaceBackground, isTrue);
    });

    testWidgets('the guide can be hidden', (tester) async {
      final cubit = await open(tester);
      await toEdit(tester, cubit);
      expect(find.text('Hide guide'), findsOneWidget);
      await tester.tap(find.text('Hide guide'));
      await tester.pump();
      expect(find.text('Show guide'), findsOneWidget);
    });

    testWidgets('quality choice changes the resulting size shown', (tester) async {
      final cubit = await open(tester);
      await toEdit(tester, cubit);
      await tester.scrollUntilVisible(find.text('Create photo'), 200);
      await tester.ensureVisible(find.text('Create photo'));
      await tester.pump();
      expect(find.text('Result: 413 x 531 pixels'), findsOneWidget);
      cubit.setDpi(600);
      await tester.pump();
      expect(find.text('Result: 827 x 1063 pixels'), findsOneWidget);
    });
  });

  group('result', () {
    Future<PassportCubit> toResult(WidgetTester tester) async {
      final cubit = await open(tester);
      await toEdit(tester, cubit);
      await tester.runAsync(cubit.create);
      await tester.pump();
      return cubit;
    }

    testWidgets('shows the size, the file size and the ways to keep it', (tester) async {
      await toResult(tester);
      expect(find.text('Your photo'), findsOneWidget);
      expect(find.textContaining('413 x 531 px'), findsOneWidget);
      expect(find.textContaining('40 kB'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('upload limits compress while keeping the pixels', (tester) async {
      final cubit = await toResult(tester);
      await tester.scrollUntilVisible(find.text('Under 50 kB'), 200);
      await tester.ensureVisible(find.text('Under 50 kB'));
      await tester.pump();
      await tester.tap(find.text('Under 50 kB'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(compressor.targets, [50 * 1024]);
      expect(cubit.state.rendered!.bytes, 50 * 1024 - 500);
      expect(find.textContaining('50 kB'), findsWidgets);
    });

    testWidgets('a print sheet shows how many photos fit', (tester) async {
      final cubit = await toResult(tester);
      await tester.scrollUntilVisible(find.text('A4'), 200);
      await tester.ensureVisible(find.text('A4'));
      await tester.pump();
      await tester.tap(find.text('A4'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Create print sheet'), 200);
      await tester.ensureVisible(find.text('Create print sheet'));
      await tester.pump();
      await tester.tap(find.text('Create print sheet'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(maker.sheets, [SheetPaper.a4]);
      expect(cubit.state.sheet, isNotNull);
      expect(find.textContaining('photos on A4'), findsOneWidget);
      expect(find.text('Share PDF', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 900.0]) {
      testWidgets('the result fits ${width.toInt()} dp with a sheet', (tester) async {
        final cubit = await open(tester, width: width, height: 700);
        await toEdit(tester, cubit);
        await tester.runAsync(cubit.create);
        await tester.pump();
        await tester.runAsync(() => cubit.makeSheet(paper: SheetPaper.photo4x6));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('back steps through result, crop and the first screen', (tester) async {
      final cubit = await toResult(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(cubit.state.step, PassportStep.edit);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(cubit.state.step, PassportStep.choose);
      expect(find.text('Passport and ID photo'), findsOneWidget);
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/photo_tools/domain/watermark.dart';
import 'package:doculoom/features/photo_tools/domain/watermark_service.dart';
import 'package:doculoom/features/photo_tools/presentation/watermark_cubit.dart';
import 'package:doculoom/features/photo_tools/presentation/watermark_page.dart';

class _Service implements WatermarkService {
  final calls = <String>[];

  @override
  Future<Result<WatermarkOutput>> apply({
    required String inputPath,
    required WatermarkStyle style,
    required String outputDir,
    String businessName = '',
    void Function(int done, int total)? onProgress,
  }) async {
    calls.add(inputPath);
    final pdf = inputPath.endsWith('.pdf');
    return Ok(
      WatermarkOutput(
        path: p.join(outputDir, 'o_${p.basename(inputPath)}'),
        mimeType: pdf ? 'application/pdf' : 'image/jpeg',
        name: p.basename(inputPath),
        pages: pdf ? 4 : 1,
      ),
    );
  }
}

class _Profiles implements BusinessProfileStore {
  BusinessProfile profile = const BusinessProfile();

  @override
  Future<BusinessProfile> load() async => profile;

  @override
  Future<BusinessProfile> save(BusinessProfile profile, {String? newLogoSource}) async => this.profile = profile;
}

void main() {
  late Directory dir;
  late _Service service;
  late _Profiles profiles;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_wmp');
    service = _Service();
    profiles = _Profiles();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String photo(String name) => (File(p.join(dir.path, name))..writeAsBytesSync(img.encodeJpg(img.Image(width: 80, height: 60, numChannels: 3)))).path;
  String pdf(String name) => (File(p.join(dir.path, name))..writeAsBytesSync([1, 2, 3])).path;

  Future<WatermarkCubit> open(WidgetTester tester, {double width = 400, double height = 800}) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
    await sl.reset();
    sl
      ..registerSingleton<WatermarkService>(service)
      ..registerSingleton<BusinessProfileStore>(profiles);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const WatermarkPage()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    return tester.element(find.byType(Scaffold).first).read<WatermarkCubit>();
  }

  // The label also appears in the app bar, so look inside the button.
  final addButton = find.descendant(of: find.bySubtype<FilledButton>(), matching: find.text('Add watermark'));

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pump();
  }

  testWidgets('starts with a sample page, the default words and the presets', (tester) async {
    await open(tester);
    await settle(tester);
    expect(find.text('Add watermark'), findsOneWidget, reason: 'the title; the button is further down');
    expect(find.widgetWithText(TextField, 'CONFIDENTIAL'), findsOneWidget);
    expect(find.byKey(const ValueKey('watermark-preview')), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('For KYC only'), findsOneWidget);
    expect(find.textContaining('Add photos or PDF files'), findsOneWidget);
    await reveal(tester, addButton);
    expect(
      tester.widget<FilledButton>(find.ancestor(of: addButton, matching: find.bySubtype<FilledButton>())).onPressed,
      isNull,
      reason: 'nothing to mark yet',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preset fills the words field', (tester) async {
    final cubit = await open(tester);
    await reveal(tester, find.text('For KYC only'));
    await tester.tap(find.text('For KYC only'));
    await settle(tester);
    expect(cubit.state.style.text, WatermarkPresets.kyc);
    expect(find.widgetWithText(TextField, WatermarkPresets.kyc), findsOneWidget);
  });

  testWidgets('typing in the field updates the watermark without losing the cursor', (tester) async {
    final cubit = await open(tester);
    await tester.enterText(find.byType(TextField).first, 'Asha Traders');
    await settle(tester);
    expect(cubit.state.style.text, 'Asha Traders');
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, 'Asha Traders');
  });

  testWidgets('added files are listed, PDFs get an icon, and others are reported as skipped', (tester) async {
    final cubit = await open(tester);
    await tester.runAsync(() => cubit.add([photo('a.jpg'), pdf('b.pdf'), pdf('c.docx')]));
    await settle(tester);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);
    expect(find.textContaining('1 file was skipped'), findsOneWidget);
    expect(find.textContaining('Add photos or PDF files'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a PDF alone shows a sample page and says every page is marked', (tester) async {
    final cubit = await open(tester);
    await tester.runAsync(() => cubit.add([pdf('only.pdf')]));
    await settle(tester);
    expect(find.textContaining('A sample page is shown'), findsOneWidget);
  });

  testWidgets('layout choice shows the position grid only for one mark', (tester) async {
    final cubit = await open(tester);
    await reveal(tester, find.text('One mark'));
    expect(find.text('Position'), findsNothing, reason: 'repeated marks have no position');
    await tester.tap(find.text('One mark'));
    await settle(tester);
    expect(cubit.state.style.layout, WatermarkLayout.single);
    await reveal(tester, find.text('Position'));
    expect(find.text('Position'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Position topLeft'));
    await tester.pump();
    expect(cubit.state.style.position, WatermarkPosition.topLeft);
  });

  testWidgets('angle, colour and bold choices reach the style', (tester) async {
    final cubit = await open(tester);
    await reveal(tester, find.text('Straight'));
    await tester.tap(find.text('Straight'));
    await settle(tester);
    expect(cubit.state.style.rotation, 0);
    await tester.tap(find.text('Steep diagonal'));
    await settle(tester);
    expect(cubit.state.style.rotation, -45);
    await reveal(tester, find.text('Red'));
    await tester.tap(find.text('Red'));
    await settle(tester);
    expect(cubit.state.style.color, WatermarkColor.red);
    await reveal(tester, find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await settle(tester);
    expect(cubit.state.style.bold, isFalse);
  });

  testWidgets('business details can be saved and then used as the watermark', (tester) async {
    final cubit = await open(tester);
    await reveal(tester, find.text('Add business details'));
    await tester.tap(find.text('Add business details'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Business name'), 'Asha Traders');
    await tester.enterText(find.widgetWithText(TextField, 'Second line'), 'GST 27ABCDE1234F1Z5');
    await tester.tap(find.text('Save'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(profiles.profile.name, 'Asha Traders');
    expect(cubit.state.profile.details, 'GST 27ABCDE1234F1Z5');

    await reveal(tester, find.text('Use my details'));
    await tester.tap(find.text('Use my details'));
    await settle(tester);
    expect(cubit.state.style.text, 'Asha Traders\nGST 27ABCDE1234F1Z5');
    expect(find.text('Edit details'), findsOneWidget);
  });

  testWidgets('saved details are there next time', (tester) async {
    profiles.profile = const BusinessProfile(name: 'Asha Traders', details: 'Pune');
    await open(tester);
    await reveal(tester, find.text('Use my details'));
    expect(find.textContaining('Asha Traders'), findsWidgets);
  });

  testWidgets('adding the watermark shows what happened to each file and the ways to keep them', (tester) async {
    final cubit = await open(tester);
    await tester.runAsync(() => cubit.add([photo('a.jpg'), pdf('b.pdf')]));
    await settle(tester);
    await reveal(tester, addButton);
    await tester.tap(addButton);
    for (var i = 0; i < 30 && service.calls.length < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await tester.pump();
    expect(service.calls, hasLength(2));
    expect(find.text('2 files are ready', skipOffstage: false), findsOneWidget);
    expect(find.text('Share', skipOffstage: false), findsOneWidget);
    expect(find.text('Save to gallery', skipOffstage: false), findsOneWidget);
    expect(find.text('Save to Files', skipOffstage: false), findsNothing, reason: 'only for a single file');
    await tester.scrollUntilVisible(find.text('a.jpg'), -200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Watermark added to 4 pages', skipOffstage: false), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty watermark is refused with a message', (tester) async {
    final cubit = await open(tester);
    await tester.runAsync(() => cubit.add([photo('a.jpg')]));
    await tester.enterText(find.byType(TextField).first, '');
    await settle(tester);
    await reveal(tester, addButton);
    await tester.tap(addButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Type the words'), findsOneWidget);
    expect(service.calls, isEmpty);
  });

  for (final size in [const Size(320, 568), const Size(400, 800), const Size(900, 700)]) {
    testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} with files and a result', (tester) async {
      final cubit = await open(tester, width: size.width, height: size.height);
      await tester.runAsync(() => cubit.add([photo('a.jpg')]));
      await tester.runAsync(cubit.run);
      await settle(tester);
      await reveal(tester, find.text('Share'));
      expect(tester.takeException(), isNull);
    });
  }
}

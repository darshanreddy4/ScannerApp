import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/signature/domain/signature.dart';
import 'package:doculoom/features/signature/presentation/sign_document_page.dart';
import 'package:doculoom/features/signature/presentation/signature_cubits.dart';
import 'package:doculoom/features/signature/presentation/signature_pages.dart';

class _Store implements SignatureStore {
  _Store(this.dir);
  final Directory dir;
  final items = <SavedSignature>[];
  Failure? saveFailure;
  var counter = 0;

  SavedSignature add({SignatureKind kind = SignatureKind.signature, String name = ''}) {
    final path = p.join(dir.path, 'sig${counter++}.png');
    final image = img.Image(width: 150, height: 50, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(image, x1: 10, y1: 10, x2: 140, y2: 40, color: img.ColorRgba8(20, 30, 120, 255));
    File(path).writeAsBytesSync(img.encodePng(image));
    final s = SavedSignature(id: 's$counter', path: path, width: 150, height: 50, kind: kind, name: name, isDefault: !items.any((e) => e.kind == kind));
    items.add(s);
    return s;
  }

  @override
  Future<List<SavedSignature>> list() async => [...items];

  @override
  Future<Result<SavedSignature>> save(String pngPath, {SignatureKind kind = SignatureKind.signature, String name = ''}) async {
    if (saveFailure != null) return Err(saveFailure!);
    if (items.length >= SignatureStore.maxSaved) return Err(ExportFailure('You can keep up to ${SignatureStore.maxSaved} signatures.'));
    lastKind = kind;
    return Ok(add(kind: kind, name: name));
  }

  SignatureKind? lastKind;
  final calls = <String>[];

  void _replace(String id, SavedSignature Function(SavedSignature) f) {
    final i = items.indexWhere((s) => s.id == id);
    if (i >= 0) items[i] = f(items[i]);
  }

  @override
  Future<void> update(String id, {String? name, SignatureKind? kind}) async {
    calls.add('update $id $name ${kind?.name}');
    _replace(id, (s) => s.copyWith(name: name, kind: kind));
  }

  @override
  Future<void> setDefault(String id) async {
    calls.add('default $id');
    final kind = items.firstWhere((s) => s.id == id).kind;
    for (final s in [...items]) {
      if (s.kind == kind) _replace(s.id, (x) => x.copyWith(isDefault: x.id == id));
    }
  }

  @override
  Future<void> move(String id, int index) async {
    calls.add('move $id $index');
    final i = items.indexWhere((s) => s.id == id);
    final s = items.removeAt(i);
    items.insert(index, s);
  }

  @override
  Future<Result<SavedSignature>> recolor(String id, InkColor ink) async {
    calls.add('recolor $id ${ink.name}');
    return Ok(items.firstWhere((s) => s.id == id));
  }

  @override
  Future<Result<SavedSignature>> duplicate(String id) async {
    calls.add('duplicate $id');
    if (items.length >= SignatureStore.maxSaved) return const Err(ExportFailure('full'));
    return Ok(add());
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((s) => s.id == id);

  @override
  Future<void> deleteAll() async => items.clear();
}

class _Maker implements SignatureMaker {
  List<Stroke> lastStrokes = const [];
  double lastPad = 0;
  double? lastSensitivity;
  InkColor? lastInk;
  var photoCalls = 0;
  Failure? photoFailure;
  late final Directory dir;

  SignaturePng _png(String path) {
    File(path).writeAsBytesSync(img.encodePng(img.Image(width: 120, height: 40, numChannels: 4)));
    return SignaturePng(path: path, width: 120, height: 40);
  }

  @override
  Future<Result<SignaturePng>> fromStrokes({
    required List<Stroke> strokes,
    required double padWidth,
    required double padHeight,
    required double penWidth,
    required InkColor ink,
    required String outputPath,
  }) async {
    lastStrokes = strokes;
    lastPad = padWidth;
    lastInk = ink;
    return Ok(_png(outputPath));
  }

  @override
  Future<Result<SignaturePng>> fromPhoto({required String sourcePath, required String outputPath, required double sensitivity, InkColor? ink}) async {
    photoCalls++;
    lastSensitivity = sensitivity;
    lastInk = ink;
    if (photoFailure != null) return Err(photoFailure!);
    return Ok(_png(outputPath));
  }
}

class _Signer implements DocumentSigner {
  _Signer(this.pages, {this.pdf = true});
  final List<String> pages;
  final bool pdf;
  List<int> lastPages = const [];
  SignPlacement? lastPlacement;
  String? lastSignature;

  @override
  Future<Result<SignDocument>> open(String path) async =>
      Ok(SignDocument(name: 'Rent agreement', pages: pages, sizes: [for (final _ in pages) (width: 600, height: 800)], isPdf: pdf));

  @override
  Future<Result<SignedFile>> sign({
    required SignDocument document,
    required String signaturePath,
    required SignPlacement placement,
    required List<int> pages,
    required String outputDir,
    void Function(int, int)? onProgress,
  }) async {
    lastPages = pages;
    lastPlacement = placement;
    lastSignature = signaturePath;
    onProgress?.call(pages.length, pages.length);
    return Ok(
      SignedFile(
        path: '$outputDir/x',
        name: pdf ? 'Rent agreement signed.pdf' : 'Rent agreement signed.jpg',
        mimeType: pdf ? 'application/pdf' : 'image/jpeg',
        pages: document.pages.length,
        signedPages: pages.length,
      ),
    );
  }
}

void main() {
  late Directory dir;
  late _Store store;
  late _Maker maker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_sigui');
    store = _Store(dir);
    maker = _Maker()..dir = dir;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> pagePictures(int n) => [
    for (var i = 0; i < n; i++)
      (File(p.join(dir.path, 'pg$i.jpg'))..writeAsBytesSync(img.encodeJpg(img.Image(width: 30, height: 40, numChannels: 3), quality: 40))).path,
  ];

  group('draw cubit', () {
    SignatureDrawCubit make() => SignatureDrawCubit(maker: maker, store: store, workDir: () async => dir);

    test('strokes grow, undo removes the last and clear removes all', () {
      final c = make();
      c.begin(10, 10);
      c.extend(30, 40);
      c.extend(30.2, 40.1);
      expect(c.state.strokes.single.points.length, 2, reason: 'tiny moves are ignored');
      c.begin(50, 50);
      expect(c.state.strokes.length, 2);
      c.undo();
      expect(c.state.strokes.length, 1);
      c.clear();
      expect(c.state.isEmpty, isTrue);
      c.undo();
      c.extend(1, 1);
      expect(c.state.isEmpty, isTrue);
    });

    test('saving makes a picture of the strokes and keeps it', () async {
      final c = make();
      c.begin(10, 10);
      c.extend(100, 80);
      c.setInk(InkColor.blue);
      c.setPen(5.5);
      await c.save(padWidth: 320, padHeight: 220);
      expect(maker.lastStrokes.length, 1);
      expect(maker.lastPad, 320);
      expect(maker.lastInk, InkColor.blue);
      expect(c.state.saved, isNotNull);
      expect(store.items.length, 1);
    });

    test('a full store is reported', () async {
      for (var i = 0; i < SignatureStore.maxSaved; i++) {
        store.add();
      }
      final c = make();
      c.begin(1, 1);
      c.extend(50, 50);
      await c.save(padWidth: 100, padHeight: 100);
      expect(c.state.saved, isNull);
      expect(c.state.failure!.message, contains('up to 20 signatures'));
    });
  });

  group('photo cubit', () {
    SignaturePhotoCubit make() => SignaturePhotoCubit(maker: maker, store: store, workDir: () async => dir);

    test('picking extracts the signature, and settings extract again', () async {
      final c = make();
      await c.pick('/photo.jpg');
      expect(c.state.preview, isNotNull);
      expect(maker.photoCalls, 1);
      await c.setSensitivity(0.8);
      expect(maker.lastSensitivity, 0.8);
      await c.setInk(null);
      expect(maker.lastInk, isNull);
      expect(maker.photoCalls, 3);
      await c.save();
      expect(c.state.saved, isNotNull);
    });

    test('a photo without a signature shows the reason and cannot be saved', () async {
      maker.photoFailure = const ExportFailure('No signature found in this photo.');
      final c = make();
      await c.pick('/photo.jpg');
      expect(c.state.preview, isNull);
      expect(c.state.failure!.message, contains('No signature found'));
      await c.save();
      expect(store.items, isEmpty);
    });
  });

  group('sign cubit', () {
    SignDocumentCubit make(_Signer signer) => SignDocumentCubit(signer: signer, store: store, outputDir: () async => dir);

    test('uses the first saved signature and defaults to the last page of a long PDF', () async {
      final first = store.add();
      store.add();
      final signer = _Signer(pagePictures(3));
      final c = make(signer);
      await c.loadSignatures();
      expect(c.state.selected!.id, first.id);
      await c.open('/x.pdf');
      expect(c.state.target, SignPages.lastPage);
      await c.sign();
      expect(signer.lastPages, [2]);
      expect(signer.lastSignature, first.path);
      expect(c.state.result!.signedPages, 1);
    });

    test('a single page or photo is signed on that page', () async {
      store.add();
      final signer = _Signer(pagePictures(1), pdf: false);
      final c = make(signer);
      await c.loadSignatures();
      await c.open('/x.jpg');
      expect(c.state.target, SignPages.thisPage);
      await c.sign();
      expect(signer.lastPages, [0]);
    });

    test('moving and resizing keep the signature on the page', () async {
      store.add();
      final c = make(_Signer(pagePictures(2)));
      await c.loadSignatures();
      await c.open('/x.pdf');
      c.move(5, 5);
      expect(c.state.placement.centerX, lessThanOrEqualTo(1 - c.state.placement.width / 2 + 0.0001));
      expect(c.state.placement.centerY, lessThanOrEqualTo(1));
      c.move(-9, -9);
      expect(c.state.placement.centerX, greaterThanOrEqualTo(c.state.placement.width / 2 - 0.0001));
      c.resize(5);
      expect(c.state.placement.width, SignPlacement.maxWidth);
    });

    test('pages are limited to the document and every page can be chosen', () async {
      store.add();
      final signer = _Signer(pagePictures(3));
      final c = make(signer);
      await c.loadSignatures();
      await c.open('/x.pdf');
      c.setPage(9);
      expect(c.state.page, 2);
      c.setPage(-3);
      expect(c.state.page, 0);
      c.setTarget(SignPages.allPages);
      await c.sign();
      expect(signer.lastPages, [0, 1, 2]);
    });

    test('changing anything clears the earlier result', () async {
      store.add();
      final c = make(_Signer(pagePictures(2)));
      await c.loadSignatures();
      await c.open('/x.pdf');
      await c.sign();
      expect(c.state.result, isNotNull);
      c.setTarget(SignPages.allPages);
      expect(c.state.result, isNull);
    });

    test('signing without a saved signature asks to create one', () async {
      final c = make(_Signer(pagePictures(1)));
      await c.loadSignatures();
      await c.open('/x.pdf');
      await c.sign();
      expect(c.state.failure!.message, 'Create a signature first.');
    });
  });

  group('pages', () {
    Future<void> setUpPage(WidgetTester tester, Widget page, {double width = 400, DocumentSigner? signer}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      await sl.reset();
      sl
        ..registerSingleton<SignatureStore>(store)
        ..registerSingleton<SignatureMaker>(maker)
        ..registerSingleton<DocumentSigner>(signer ?? _Signer(const []));
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: page));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }

    testWidgets('the hub explains an empty state and lists saved signatures', (tester) async {
      await setUpPage(tester, const SignatureHubPage());
      expect(find.textContaining('No signature yet'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign a PDF or photo')).onPressed, isNull);
      expect(find.textContaining('not a certified digital signature'), findsOneWidget);
    });

    testWidgets('the hub shows saved signatures and disables adding at the limit', (tester) async {
      for (var i = 0; i < SignatureStore.maxSaved; i++) {
        store.add();
      }
      await setUpPage(tester, const SignatureHubPage());
      expect(find.text('You have 20 signatures. Delete one to add another.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Draw')).onPressed, isNull);
    });

    Future<void> menu(WidgetTester tester, String id, String item) async {
      await tester.tap(find.byKey(ValueKey('sig-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
    }

    testWidgets('the hub names the first signature and marks the default', (tester) async {
      store
        ..add()
        ..add(name: 'Work');
      await setUpPage(tester, const SignatureHubPage());
      expect(find.text('Signature 1 (default)'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
    });

    testWidgets('a menu action renames, sets the default, moves and makes a copy', (tester) async {
      final a = store.add();
      final b = store.add();
      await setUpPage(tester, const SignatureHubPage());

      await menu(tester, b.id, 'Use this signature first');
      expect(store.calls.last, 'default ${b.id}');
      expect(find.text('Signature 2 (default)'), findsOneWidget);

      await menu(tester, b.id, 'Move up');
      expect(store.calls.last, 'move ${b.id} 0');
      expect(store.items.first.id, b.id);

      await menu(tester, a.id, 'Make a copy');
      expect(store.calls.last, 'duplicate ${a.id}');
      expect(store.items.length, 3);

      await menu(tester, a.id, 'Keep as initials');
      expect(store.calls.last, 'update ${a.id} null initials');
    });

    testWidgets('rename asks for a name and keeps it', (tester) async {
      final a = store.add();
      await setUpPage(tester, const SignatureHubPage());
      await tester.tap(find.byKey(ValueKey('sig-menu-${a.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Office');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(store.items.single.name, 'Office');
      expect(find.text('Office (default)'), findsOneWidget);
    });

    testWidgets('change of ink colour asks which colour', (tester) async {
      final a = store.add();
      await setUpPage(tester, const SignatureHubPage());
      await menu(tester, a.id, 'Change ink colour');
      await tester.tap(find.text('Dark blue'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(store.calls.last, 'recolor ${a.id} darkBlue');
    });

    testWidgets('the kind filter shows one kind, and new pictures follow it', (tester) async {
      store
        ..add()
        ..add(kind: SignatureKind.initials, name: 'JD');
      await setUpPage(tester, const SignatureHubPage());
      expect(find.byType(SignatureThumb), findsNWidgets(2));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Initials'));
      await tester.pump();
      expect(find.byType(SignatureThumb), findsOneWidget);
      expect(find.text('JD (default)'), findsOneWidget);
      expect(find.text('Draw initials'), findsOneWidget);
      expect(find.text('Initials from a photo'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Signatures'));
      await tester.pump();
      expect(find.byType(SignatureThumb), findsOneWidget);
      expect(find.text('Draw'), findsOneWidget);
    });

    testWidgets('initials are saved as initials from the draw and photo pages', (tester) async {
      await setUpPage(tester, const SignatureDrawPage(kind: SignatureKind.initials));
      final cubit = tester.element(find.byType(Scaffold).first).read<SignatureDrawCubit>();
      cubit
        ..begin(10, 10)
        ..extend(60, 40);
      await tester.runAsync(() => cubit.save(padWidth: 300, padHeight: 150));
      await tester.pump();
      expect(store.lastKind, SignatureKind.initials);
    });

    testWidgets('the sign page starts with the default signature, not just the first', (tester) async {
      store
        ..add()
        ..add();
      store.items[1] = store.items[1].copyWith(isDefault: true);
      store.items[0] = store.items[0].copyWith(isDefault: false);
      await setUpPage(tester, const SignDocumentPage(), signer: _Signer(pagePictures(1)));
      final cubit = tester.element(find.byType(Scaffold).first).read<SignDocumentCubit>();
      await tester.runAsync(() => cubit.open('/x.pdf'));
      await tester.pump();
      expect(cubit.state.selected!.id, store.items[1].id);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('drawing on the pad enables saving at ${width.toInt()} px', (tester) async {
        await setUpPage(tester, const SignatureDrawPage(), width: width);
        final save = find.widgetWithText(FilledButton, 'Save signature');
        await tester.scrollUntilVisible(save, 200, scrollable: find.byType(Scrollable).first);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await tester.dragFrom(tester.getTopLeft(find.byKey(const ValueKey('signature-pad'))) + const Offset(40, 100), const Offset(120, 30));
        await tester.pump();
        final cubit = tester.element(find.byType(Scaffold).first).read<SignatureDrawCubit>();
        expect(cubit.state.strokes, isNotEmpty);
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the photo page asks for a photo and then shows the result', (tester) async {
      await setUpPage(tester, const SignaturePhotoPage());
      expect(find.text('Add a photo'), findsOneWidget);
      final cubit = tester.element(find.byType(Scaffold).first).read<SignaturePhotoCubit>();
      await tester.runAsync(() => cubit.pick('/photo.jpg'));
      await tester.pump();
      expect(find.text('Keep pen colour'), findsOneWidget);
      expect(find.byType(SignatureThumb), findsOneWidget);
      expect(find.text('Faint lines'), findsOneWidget);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('signing shows the page with the signature and the result at ${width.toInt()} px', (tester) async {
        store.add();
        final signer = _Signer(pagePictures(3));
        await setUpPage(tester, const SignDocumentPage(), width: width, signer: signer);
        final cubit = tester.element(find.byType(Scaffold).first).read<SignDocumentCubit>();
        await tester.runAsync(() => cubit.open('/x.pdf'));
        await tester.pump();
        expect(find.byKey(const ValueKey('signature-overlay')), findsOneWidget);
        expect(find.text('Page 1 of 3'), findsOneWidget);
        await tester.tap(find.byTooltip('Next page'));
        await tester.pump();
        expect(find.text('Page 2 of 3'), findsOneWidget);
        final before = cubit.state.placement;
        // A finger on the signature stops the list from scrolling, then dragging moves it.
        final finger = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('signature-overlay'))));
        await tester.pump();
        await finger.moveBy(const Offset(-30, -30));
        await tester.pump();
        await finger.moveBy(const Offset(-30, -30));
        await tester.pump();
        await finger.up();
        await tester.pump();
        expect(cubit.state.placement.centerX, lessThan(before.centerX));
        expect(cubit.state.placement.centerY, lessThan(before.centerY));

        final add = find.widgetWithText(FilledButton, 'Add signature');
        await tester.scrollUntilVisible(add, 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(add);
        await tester.pump();
        await tester.tap(add);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
        final signed = find.text('Signed');
        await tester.scrollUntilVisible(signed, 200, scrollable: find.byType(Scrollable).first);
        expect(signed, findsOneWidget);
        expect(signer.lastPages, [2], reason: 'last page is the default for a PDF');
        expect(find.textContaining('signature added to 1 of 3 pages'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('without a saved signature the page explains what to do first', (tester) async {
      await setUpPage(tester, const SignDocumentPage());
      expect(find.textContaining('no saved signature yet'), findsOneWidget);
    });
  });
}

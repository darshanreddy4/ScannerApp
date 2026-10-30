import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/photo_tools/domain/photo_compressor.dart';
import 'package:doculoom/features/photo_tools/presentation/compress_cubit.dart';
import 'package:doculoom/features/photo_tools/presentation/compress_photo_page.dart';

class _Fake implements PhotoCompressor {
  final calls = <CompressOptions>[];
  final failFor = <String>{};
  bool miss = false;

  @override
  Future<Result<CompressedPhoto>> compress({required String sourcePath, required String outputPath, required CompressOptions options}) async {
    calls.add(options);
    if (failFor.any(sourcePath.endsWith)) return const Err(ExportFailure('This photo could not be compressed.'));
    final bytes = options.targetBytes ?? 150000;
    return Ok(
      CompressedPhoto(path: outputPath, bytes: miss ? bytes * 2 : bytes, width: 800, height: 600, originalBytes: 2000000, metTarget: !miss, quality: 80),
    );
  }
}

void main() {
  late Directory dir;
  late _Fake fake;

  File photo(String name, {int size = 3000}) => File('${dir.path}/$name')..writeAsBytesSync(List.filled(size, 1));

  CompressCubit cubit() => CompressCubit(compressor: fake, outputDir: () async => dir);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_cp');
    fake = _Fake();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('CompressCubit', () {
    test('adds photos once, skips missing files and remembers their sizes', () async {
      final c = cubit();
      final a = photo('a.jpg', size: 4000);
      await c.add([a.path, a.path, '${dir.path}/missing.jpg']);
      expect(c.state.items.map((i) => i.name), ['a.jpg']);
      expect(c.state.items.single.bytes, 4000);
    });

    test('stops at 30 photos', () async {
      final c = cubit();
      await c.add([for (var i = 0; i < 35; i++) photo('p$i.jpg').path]);
      expect(c.state.items, hasLength(CompressCubit.maxPhotos));
    });

    test('compresses every photo in order with the chosen limits and keeps each result', () async {
      final c = cubit();
      await c.add([photo('a.jpg').path, photo('b.png').path]);
      c
        ..setTarget(50 * 1024)
        ..setMaxSide(1280)
        ..setFormat(PhotoFormat.png);
      await c.run();

      expect(fake.calls, hasLength(2));
      expect(fake.calls.first.targetBytes, 50 * 1024);
      expect(fake.calls.first.maxSide, 1280);
      expect(fake.calls.first.format, PhotoFormat.png);
      expect(c.state.status, CompressStatus.done);
      expect(c.state.results, hasLength(2));
      expect(c.state.results.first.path, endsWith('.png'));
      expect(c.state.results.first.path, contains('a_compressed'));
      expect(c.state.results.map((r) => r.path).toSet(), hasLength(2), reason: 'results never overwrite each other');
    });

    test('one failing photo does not stop the others', () async {
      final c = cubit();
      await c.add([photo('bad.jpg').path, photo('ok.jpg').path]);
      fake.failFor.add('bad.jpg');
      await c.run();
      expect(c.state.items.first.failure, isNotNull);
      expect(c.state.items.last.result, isNotNull);
      expect(c.state.results, hasLength(1));
    });

    test('changing a setting discards old results so they are not shared by mistake', () async {
      final c = cubit();
      await c.add([photo('a.jpg').path]);
      await c.run();
      expect(c.state.results, isNotEmpty);
      c.setTarget(20 * 1024);
      expect(c.state.results, isEmpty);
      expect(c.state.status, CompressStatus.idle);
    });

    test('"No limit" only resizes and converts', () async {
      final c = cubit();
      await c.add([photo('a.jpg').path]);
      c.setTarget(null);
      await c.run();
      expect(fake.calls.single.targetBytes, isNull);
    });

    test('removing and clearing work, and nothing runs without photos', () async {
      final c = cubit();
      await c.run();
      expect(fake.calls, isEmpty);
      final a = photo('a.jpg');
      await c.add([a.path, photo('b.jpg').path]);
      c.remove(a.path);
      expect(c.state.items.single.name, 'b.jpg');
      c.clear();
      expect(c.state.items, isEmpty);
    });
  });

  group('Compress photos screen', () {
    Future<CompressCubit?> open(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await sl.reset();
      sl.registerSingleton<PhotoCompressor>(fake);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const CompressPhotoPage()));
      await tester.pump();
      return null;
    }

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('fits a ${width.toInt()} dp wide screen with options', (tester) async {
        await open(tester, width);
        expect(find.text('Compress photos'), findsOneWidget);
        expect(find.text('100 kB'), findsOneWidget);
        expect(find.text('Compress', skipOffstage: false), findsOneWidget);
        expect(tester.widget<FilledButton>(find.byType(FilledButton, skipOffstage: false)).onPressed, isNull, reason: 'nothing to compress yet');
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a custom limit is read in kB or MB', (tester) async {
      await open(tester, 400);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '45');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.text('45 kB'), findsOneWidget);

      await tester.tap(find.text('45 kB'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number above 0.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number above 0.'), findsNothing);
    });
  });
}

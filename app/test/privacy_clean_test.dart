import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/photo_tools/domain/metadata_cleaner.dart';
import 'package:doculoom/features/photo_tools/presentation/privacy_clean_cubit.dart';
import 'package:doculoom/features/photo_tools/presentation/privacy_clean_page.dart';

class _Cleaner implements MetadataCleaner {
  final cleaned = <String>[];

  @override
  Future<Result<PhotoMetadata>> inspect(String path) async {
    if (path.endsWith('bad.jpg')) return const Err(ExportFailure(PhotoMetadataMessages.unsupported));
    if (path.endsWith('plain.jpg')) return const Ok(PhotoMetadata());
    if (path.endsWith('shot.png')) return const Ok(PhotoMetadata(isPng: true, hasOtherData: true, hiddenBytes: 300));
    return const Ok(PhotoMetadata(hasLocation: true, camera: 'Google Pixel 8', takenAt: '2026:03:07 10:15:00', hiddenBytes: 4200));
  }

  @override
  Future<Result<CleanedPhoto>> clean({required String sourcePath, required String outputPath}) async {
    cleaned.add(sourcePath);
    File(outputPath).writeAsBytesSync([1, 2, 3]);
    return Ok(CleanedPhoto(path: outputPath, bytes: 3, removedBytes: 4197));
  }
}

class PhotoMetadataMessages {
  static const unsupported = 'Only JPG and PNG photos can be cleaned.';
}

void main() {
  late Directory dir;
  late _Cleaner cleaner;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_priv');
    cleaner = _Cleaner();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String file(String name) => (File(p.join(dir.path, name))..writeAsBytesSync([9, 9, 9])).path;

  group('cubit', () {
    PrivacyCleanCubit make() => PrivacyCleanCubit(cleaner: cleaner, outputDir: () async => dir);

    test('looks at each photo when added and skips duplicates and missing files', () async {
      final cubit = make();
      await cubit.add([file('a.jpg'), file('a.jpg'), p.join(dir.path, 'missing.jpg'), file('plain.jpg'), file('bad.jpg')]);
      expect(cubit.state.items.map((i) => i.name), ['a.jpg', 'plain.jpg', 'bad.jpg']);
      expect(cubit.state.items[0].metadata!.hasLocation, isTrue);
      expect(cubit.state.items[2].failure, isNotNull);
      expect(cubit.state.cleanable.length, 2);
      await cubit.close();
    });

    test('cleans every readable photo into separate files and keeps the originals', () async {
      final cubit = make();
      final a = file('a.jpg'), s = file('shot.png');
      await cubit.add([a, s, file('bad.jpg')]);
      await cubit.run();
      expect(cubit.state.status, CleanStatus.done);
      expect(cleaner.cleaned, [a, s]);
      final results = cubit.state.results;
      expect(results.length, 2);
      expect(results[0].path, endsWith('.jpg'));
      expect(results[1].path, endsWith('.png'));
      expect(results.map((r) => r.path).toSet().length, 2);
      expect(File(a).existsSync(), isTrue);
      await cubit.close();
    });

    test('a photo that cannot be cleaned is reported and the rest still finish', () async {
      final bad = _FailingSecond();
      final cubit = PrivacyCleanCubit(cleaner: bad, outputDir: () async => dir);
      await cubit.add([file('a.jpg'), file('b.jpg')]);
      await cubit.run();
      expect(cubit.state.results.length, 1);
      expect(cubit.state.items[1].failure, isNotNull);
      await cubit.close();
    });

    test('nothing to clean means nothing runs', () async {
      final cubit = make();
      await cubit.add([file('bad.jpg')]);
      await cubit.run();
      expect(cubit.state.status, CleanStatus.idle);
      expect(cleaner.cleaned, isEmpty);
      await cubit.close();
    });

    test('remove and clear update the list', () async {
      final cubit = make();
      final a = file('a.jpg');
      await cubit.add([a, file('plain.jpg')]);
      cubit.remove(a);
      expect(cubit.state.items.length, 1);
      cubit.clear();
      expect(cubit.state.items, isEmpty);
      await cubit.close();
    });

    test('the number of photos is limited', () async {
      final cubit = make();
      await cubit.add([for (var i = 0; i < PrivacyCleanCubit.maxPhotos + 5; i++) file('p$i.jpg')]);
      expect(cubit.state.items.length, PrivacyCleanCubit.maxPhotos);
      await cubit.close();
    });
  });

  group('page', () {
    Future<PrivacyCleanCubit> open(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      await sl.reset();
      sl.registerSingleton<MetadataCleaner>(cleaner);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PrivacyCleanPage()));
      await tester.pump();
      return tester.element(find.byType(Scaffold).first).read<PrivacyCleanCubit>();
    }

    Future<void> addPhotos(WidgetTester tester, PrivacyCleanCubit cubit, List<String> paths) async {
      await tester.runAsync(() => cubit.add(paths));
      await tester.pump();
    }

    testWidgets('explains the tool before any photo is added', (tester) async {
      await open(tester);
      expect(find.textContaining('place and time they were taken'), findsOneWidget);
      expect(find.textContaining('send as file'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.bySubtype<FilledButton>().first).onPressed, isNull);
    });

    testWidgets('lists what each photo carries in plain words', (tester) async {
      final cubit = await open(tester);
      await addPhotos(tester, cubit, [file('a.jpg'), file('plain.jpg'), file('bad.jpg')]);
      expect(find.textContaining('Location where it was taken'), findsOneWidget);
      expect(find.textContaining('Phone or camera: Google Pixel 8'), findsOneWidget);
      expect(find.textContaining('Date and time: 2026:03:07'), findsOneWidget);
      expect(find.text('Nothing hidden found'), findsOneWidget);
      expect(find.text('Only JPG and PNG photos can be cleaned.'), findsOneWidget);
      expect(find.text('Remove hidden data (4.1 kB)'), findsOneWidget);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('cleaning shows the result and sharing options at ${width.toInt()} px', (tester) async {
        final cubit = await open(tester, width: width);
        await addPhotos(tester, cubit, [file('a.jpg'), file('shot.png')]);
        await tester.runAsync(cubit.run);
        await tester.pump();
        expect(find.text('2 clean photos are ready'), findsOneWidget);
        expect(find.textContaining('Clean. Removed'), findsNWidgets(2));
        final share = find.text('Share');
        await tester.scrollUntilVisible(share, 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Save to gallery'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _FailingSecond extends _Cleaner {
  @override
  Future<Result<CleanedPhoto>> clean({required String sourcePath, required String outputPath}) async {
    if (sourcePath.endsWith('b.jpg')) return const Err(ExportFailure('Could not clean this photo.'));
    return super.clean(sourcePath: sourcePath, outputPath: outputPath);
  }
}

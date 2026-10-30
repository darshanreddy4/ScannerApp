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
import 'package:doculoom/features/pdf_tools/domain/pdf_compressor.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_compress_cubit.dart';
import 'package:doculoom/features/pdf_tools/presentation/pdf_compress_page.dart';

class _Compressor implements PdfCompressor {
  _Compressor(this.build);
  final Result<CompressedPdf> Function(String source, String output, PdfCompressOptions options) build;
  PdfCompressOptions? lastOptions;

  @override
  Future<Result<CompressedPdf>> compress({
    required String sourcePath,
    required String outputPath,
    required PdfCompressOptions options,
    void Function(int attempt, int attempts)? onProgress,
  }) async {
    lastOptions = options;
    onProgress?.call(1, 3);
    onProgress?.call(2, 3);
    return build(sourcePath, outputPath, options);
  }
}

Result<CompressedPdf> _ok(String source, String output, PdfCompressOptions o) {
  File(output).writeAsBytesSync(List.filled(300 * 1024, 1));
  return Ok(CompressedPdf(path: output, bytes: 300 * 1024, originalBytes: 4 * 1024 * 1024, pages: 5, metTarget: true));
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('sv_pdfp'));
  tearDown(() => dir.deleteSync(recursive: true));

  String pdf({int bytes = 4 * 1024 * 1024}) => (File(p.join(dir.path, 'Bank statement.pdf'))..writeAsBytesSync(List.filled(bytes, 1))).path;

  group('cubit', () {
    test('picking, running and clearing', () async {
      final c = _Compressor(_ok);
      final cubit = PdfCompressCubit(compressor: c, outputDir: () async => dir);
      await cubit.pick(pdf());
      expect(cubit.state.name, 'Bank statement.pdf');
      expect(cubit.state.bytes, 4 * 1024 * 1024);
      await cubit.run();
      expect(cubit.state.status, PdfCompressStatus.done);
      expect(c.lastOptions!.targetBytes, 500 * 1024);
      expect(cubit.state.result!.bytes, 300 * 1024);
      expect(cubit.state.result!.path, contains('Bank statement_compressed_'));
      cubit.setTarget(null);
      expect(cubit.state.result, isNull, reason: 'a new setting makes the old result out of date');
      cubit.clear();
      expect(cubit.state.path, isNull);
      await cubit.close();
    });

    test('shows the failure and allows another try', () async {
      final c = _Compressor((_, _, _) => const Err(ImportFailure('This file is password protected.')));
      final cubit = PdfCompressCubit(compressor: c, outputDir: () async => dir);
      await cubit.pick(pdf());
      await cubit.run();
      expect(cubit.state.failure!.message, 'This file is password protected.');
      expect(cubit.state.result, isNull);
      await cubit.run();
      expect(cubit.state.status, PdfCompressStatus.done);
      await cubit.close();
    });

    test('a missing file is reported', () async {
      final cubit = PdfCompressCubit(compressor: _Compressor(_ok), outputDir: () async => dir);
      await cubit.pick(p.join(dir.path, 'nope.pdf'));
      expect(cubit.state.path, isNull);
      expect(cubit.state.failure, isNotNull);
      await cubit.close();
    });

    test('running without a file does nothing', () async {
      final c = _Compressor(_ok);
      final cubit = PdfCompressCubit(compressor: c, outputDir: () async => dir);
      await cubit.run();
      expect(c.lastOptions, isNull);
      await cubit.close();
    });
  });

  group('page', () {
    Future<PdfCompressCubit> open(WidgetTester tester, _Compressor compressor, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      await sl.reset();
      sl.registerSingleton<PdfCompressor>(compressor);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PdfCompressPage()));
      await tester.pump();
      return tester.element(find.byType(Scaffold).first).read<PdfCompressCubit>();
    }

    testWidgets('starts with a choose button and an honest note', (tester) async {
      await open(tester, _Compressor(_ok));
      expect(find.text('Choose a PDF'), findsOneWidget);
      expect(find.textContaining('can no longer be selected'), findsOneWidget);
      expect(find.text('500 kB'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Compress PDF')).onPressed, isNull);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('shows before and after sizes at ${width.toInt()} px', (tester) async {
        final cubit = await open(tester, _Compressor(_ok), width: width);
        await tester.runAsync(() => cubit.pick(pdf()));
        await tester.pump();
        expect(find.text('Bank statement.pdf'), findsOneWidget);
        expect(find.text('4.0 MB'), findsOneWidget);
        await tester.runAsync(cubit.run);
        await tester.pump();
        await tester.scrollUntilVisible(find.text('Done: 4.0 MB to 300 kB'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Done: 4.0 MB to 300 kB'), findsOneWidget);
        expect(find.textContaining('across 5 pages'), findsOneWidget);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Save to Files'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('explains when the limit cannot be reached', (tester) async {
      final cubit = await open(
        tester,
        _Compressor((s, o, _) => Ok(CompressedPdf(path: o, bytes: 900 * 1024, originalBytes: 4 * 1024 * 1024, pages: 1, metTarget: false))),
      );
      await tester.runAsync(() => cubit.pick(pdf()));
      await tester.runAsync(cubit.run);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Smaller, but still above your limit'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Smaller, but still above your limit'), findsOneWidget);
      expect(find.textContaining('900 kB'), findsOneWidget);
    });

    testWidgets('says so when the PDF cannot get smaller', (tester) async {
      final cubit = await open(
        tester,
        _Compressor(
          (s, o, _) => Ok(CompressedPdf(path: s, bytes: 4 * 1024 * 1024, originalBytes: 4 * 1024 * 1024, pages: 2, metTarget: false, unchanged: true)),
        ),
      );
      await tester.runAsync(() => cubit.pick(pdf()));
      await tester.runAsync(cubit.run);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Could not make it smaller'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Could not make it smaller'), findsOneWidget);
    });

    testWidgets('says so when the PDF already fits', (tester) async {
      final cubit = await open(
        tester,
        _Compressor(
          (s, o, _) => Ok(CompressedPdf(path: s, bytes: 4 * 1024 * 1024, originalBytes: 4 * 1024 * 1024, pages: 0, metTarget: true, unchanged: true)),
        ),
      );
      await tester.runAsync(() => cubit.pick(pdf()));
      cubit.setTarget(5 * 1024 * 1024);
      await tester.runAsync(cubit.run);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Already small enough'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Already small enough'), findsOneWidget);
    });

    testWidgets('shows a failure message', (tester) async {
      final cubit = await open(tester, _Compressor((_, _, _) => const Err(ImportFailure('This file is password protected.'))));
      await tester.runAsync(() => cubit.pick(pdf()));
      await tester.runAsync(cubit.run);
      await tester.pump();
      await tester.scrollUntilVisible(find.text('This file is password protected.'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('This file is password protected.'), findsOneWidget);
    });
  });
}

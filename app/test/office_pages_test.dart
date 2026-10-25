import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanvault/app/di.dart';
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/export/domain/repositories/export_repository.dart';
import 'package:scanvault/features/importer/domain/importer.dart';
import 'package:scanvault/features/office/convert/office_converter.dart';
import 'package:scanvault/features/office/presentation/office_convert_page.dart';
import 'package:scanvault/features/office/presentation/office_hub_page.dart';
import 'package:scanvault/features/office/slides/data/slide_export.dart';

class _Share implements ShareService {
  final shared = <List<String>>[];

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    shared.add([path]);
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async {
    shared.add(paths);
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoImporter implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) async => const Err(ImportFailure('no'));
}

void main() {
  testWidgets('the spreadsheet hub lists opening, creating and converting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const OfficeHubPage(hub: OfficeHub.sheets),
      ),
    );
    expect(find.text('Open an Excel or CSV file'), findsOneWidget);
    expect(find.text('New spreadsheet'), findsOneWidget);
    for (final t in ['Excel to PDF', 'Excel to CSV', 'CSV to Excel']) {
      await tester.scrollUntilVisible(find.text(t), 200);
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('PowerPoint to PDF'), findsNothing);
  });

  testWidgets('the presentation hub lists opening, creating and converting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const OfficeHubPage(hub: OfficeHub.slides),
      ),
    );
    expect(find.text('Open a PowerPoint file'), findsOneWidget);
    expect(find.text('New presentation'), findsOneWidget);
    for (final t in ['PowerPoint to PDF', 'PowerPoint to images', 'Images to PowerPoint', 'PDF to PowerPoint']) {
      await tester.scrollUntilVisible(find.text(t), 200);
      expect(find.text(t), findsOneWidget);
    }
  });

  testWidgets('a conversion runs from the page and its result can be shared', (tester) async {
    final work = Directory.systemTemp.createTempSync('convert_page');
    addTearDown(() => work.deleteSync(recursive: true));
    final share = _Share();
    await sl.reset();
    sl
      ..registerSingleton<ShareService>(share)
      ..registerSingleton<OfficeConverter>(
        OfficeConverter(
          workDir: () async => work,
          slideConversions: SlideConverter(importer: _NoImporter()).convert,
        ),
      );
    addTearDown(sl.reset);

    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OfficeConvertPage(conversion: OfficeConversion.xlsxToCsv, initialInputs: [File('test/fixtures/office/basic.xlsx').absolute.path]),
      ),
    );
    expect(find.text('basic.xlsx'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('convert_go')));
    for (var i = 0; i < 60 && find.byKey(const ValueKey('convert_result')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('Done: 2 files'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('convert_share')));
    await tester.pump();
    expect(share.shared.single, hasLength(2));
  });

  testWidgets('a bad file shows the failure on the page', (tester) async {
    final work = Directory.systemTemp.createTempSync('convert_bad');
    addTearDown(() => work.deleteSync(recursive: true));
    final bad = File('${work.path}/x.pptx')..writeAsBytesSync([1, 2, 3]);
    await sl.reset();
    sl.registerSingleton<OfficeConverter>(
      OfficeConverter(
        workDir: () async => work,
        slideConversions: SlideConverter(importer: _NoImporter()).convert,
      ),
    );
    addTearDown(sl.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OfficeConvertPage(conversion: OfficeConversion.pptxToPdf, initialInputs: [bad.path]),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('convert_go')));
    for (var i = 0; i < 60 && find.byKey(const ValueKey('convert_error')).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('not a valid .pptx'), findsOneWidget);
  });
}

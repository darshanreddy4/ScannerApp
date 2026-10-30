import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/presentation/widgets/document_actions.dart';
import 'package:doculoom/features/documents/presentation/widgets/share_options_sheet.dart';
import 'package:doculoom/features/export/data/share_packager.dart';
import 'package:doculoom/features/export/domain/entities/export_options.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/export/domain/usecases/export_usecases.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_protect_processor.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

import 'support/coins_fakes.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  _Prefs(this.settings);
  final AppSettings settings;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Export implements ExportRepository {
  _Export(this.path);
  final String path;
  final qualities = <ExportQuality>[];
  @override
  Future<Result<String>> export({required ScannedDocument document, required ExportFormat format, required ExportQuality quality}) async {
    qualities.add(quality);
    return Ok(path);
  }
}

class _Share implements ShareService {
  final shared = <({String path, String mime})>[];
  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    shared.add((path: path, mime: mimeType));
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ScannedDocument _doc() => ScannedDocument(
  id: 'd1',
  title: 'Rent agreement',
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 2),
  pages: const [DocumentPage(id: 'p0', position: 0, imagePath: '/x/0.jpg', rawPath: '/x/r0.jpg', width: 10, height: 10)],
);

void main() {
  late Directory dir;
  late String pdf;
  const protector = PdfProtectProcessor();

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_share');
    pdf = p.join(dir.path, 'Rent_agreement.pdf');
    File(p.absolute('test/fixtures/pdf_security/plain.pdf')).copySync(pdf);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  SharePackager packager() => SharePackager(protector, tempDir: () async => dir);

  group('the packager', () {
    test('with nothing chosen the exported PDF is sent as it is', () async {
      final r = (await packager().pack(pdfPath: pdf)).valueOrNull!;
      expect((r.path, r.mimeType), (pdf, 'application/pdf'));
    });

    test('a password gives a new locked file and leaves the PDF it was given untouched', () async {
      final before = File(pdf).readAsBytesSync();
      final r = (await packager().pack(pdfPath: pdf, password: 'Sunrise 2026')).valueOrNull!;
      expect(r.path, isNot(pdf));
      expect(p.basename(r.path), 'Rent_agreement.pdf', reason: 'the receiver sees a clean name');
      expect(r.mimeType, 'application/pdf');
      expect((await protector.inspect(r.path)).valueOrNull!.needsPassword, isTrue);
      expect(File(pdf).readAsBytesSync(), before);
      expect((await protector.inspect(pdf)).valueOrNull!.encrypted, isFalse);
    });

    test('ZIP puts the PDF inside one .zip file', () async {
      final r = (await packager().pack(pdfPath: pdf, zip: true)).valueOrNull!;
      expect((p.extension(r.path), r.mimeType), ('.zip', 'application/zip'));
      final files = ZipDecoder().decodeBytes(File(r.path).readAsBytesSync()).files;
      expect(files.map((f) => f.name), ['Rent_agreement.pdf']);
      expect(files.single.content, File(pdf).readAsBytesSync());
    });

    test('password and ZIP together put the locked PDF in the ZIP', () async {
      final r = (await packager().pack(pdfPath: pdf, password: 'Sunrise 2026', zip: true)).valueOrNull!;
      final inner = ZipDecoder().decodeBytes(File(r.path).readAsBytesSync()).files.single;
      final copy = File(p.join(dir.path, 'inner.pdf'))..writeAsBytesSync(inner.content);
      expect((await protector.inspect(copy.path)).valueOrNull!.needsPassword, isTrue);
      expect((await protector.inspect(pdf)).valueOrNull!.encrypted, isFalse);
    });

    test('a short password is refused and nothing is written', () async {
      final r = await packager().pack(pdfPath: pdf, password: 'abc');
      expect(r.failureOrNull, isA<PasswordFailure>());
      expect(Directory(p.join(dir.path, 'share_out')).existsSync(), isFalse);
    });

    test('each share starts from a clean folder, so an earlier file is never sent again', () async {
      final first = (await packager().pack(pdfPath: pdf, zip: true)).valueOrNull!;
      final second = (await packager().pack(pdfPath: pdf, zip: true)).valueOrNull!;
      expect(File(first.path).existsSync(), isFalse);
      expect(File(second.path).existsSync(), isTrue);
    });
  });

  group('Share PDF', () {
    late _Export export;
    late _Share share;

    setUp(() async {
      await sl.reset();
      sl
        ..registerSingleton(ExportDocument(export = _Export(pdf)))
        ..registerSingleton<ShareService>(share = _Share())
        ..registerSingleton<AdService>(ScriptedAds())
        ..registerSingleton(packager());
    });

    Future<void> open(WidgetTester tester, {AppSettings settings = const AppSettings()}) async {
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider(lazy: false, create: (_) => SettingsCubit(_Prefs(settings))..load()),
            BlocProvider(create: (_) => PlanCubit(_Plans())),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(onPressed: () => shareDocumentPdf(context, _doc()), child: const Text('go')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.ensureVisible(find.byKey(ValueKey(key)));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey(key)));
      await tester.pump();
    }

    // Real file work runs outside the fake clock.
    Future<void> go(WidgetTester tester) async {
      await tapKey(tester, 'share-go');
      for (var i = 0; i < 40 && share.shared.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    testWidgets('the options come first, nothing is shared until Share is chosen, and Cancel shares nothing', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('share-size')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-password')), findsOneWidget);
      expect(find.byKey(const ValueKey('share-zip')), findsOneWidget);
      expect(find.textContaining('document in this app stays as it is'), findsOneWidget);
      expect(share.shared, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(share.shared, isEmpty);
      expect(export.qualities, isEmpty);
    });

    testWidgets('with no option chosen the PDF is shared as before', (tester) async {
      await open(tester);
      await go(tester);
      expect(share.shared.single, (path: pdf, mime: 'application/pdf'));
      expect(export.qualities, [ExportQuality.high]);
    });

    testWidgets('Compress builds the copy at a lower quality, and never above the quality set in Settings', (tester) async {
      await open(tester);
      await tester.tap(find.text('Compress'));
      await tester.pump();
      await go(tester);
      expect(export.qualities, [ExportQuality.medium]);
    });

    testWidgets('a lower quality set in Settings is kept when Compress is chosen', (tester) async {
      await open(tester, settings: const AppSettings(exportQuality: ExportQuality.low));
      await tester.tap(find.text('Compress'));
      await tester.pump();
      await go(tester);
      expect(export.qualities.last, ExportQuality.low, reason: 'Settings already asked for the smallest');
    });

    testWidgets('ZIP shares one .zip file', (tester) async {
      await open(tester);
      await tapKey(tester, 'share-zip');
      await go(tester);
      expect(share.shared.single.mime, 'application/zip');
      expect(p.extension(share.shared.single.path), '.zip');
    });

    testWidgets('the password needs 4 characters and a matching repeat before Share works, then the shared copy is locked', (tester) async {
      await open(tester);
      await tapKey(tester, 'share-password');
      FilledButton button() => tester.widget<FilledButton>(find.byKey(const ValueKey('share-go')));
      expect(button().onPressed, isNull);

      await tester.ensureVisible(find.byKey(const ValueKey('share-pw')));
      await tester.enterText(find.byKey(const ValueKey('share-pw')), 'abc');
      await tester.enterText(find.byKey(const ValueKey('share-pw2')), 'abc');
      await tester.pump();
      expect(button().onPressed, isNull, reason: 'too short');

      await tester.enterText(find.byKey(const ValueKey('share-pw')), 'Sunrise 2026');
      await tester.pump();
      expect(find.text('The two passwords are not the same.'), findsOneWidget);
      expect(button().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('share-pw2')), 'Sunrise 2026');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      final before = File(pdf).readAsBytesSync();
      await go(tester);
      final sent = share.shared.single;
      expect(sent.path, isNot(pdf));
      final locked = await tester.runAsync(() => protector.inspect(sent.path));
      expect(locked!.valueOrNull!.needsPassword, isTrue);
      expect(File(pdf).readAsBytesSync(), before, reason: 'the exported file is not changed');
    });

    test('the sheet offers the three sizes', () {
      expect(ShareSize.values.map((s) => s.label), ['Original', 'Compress', 'Compress more']);
    });
  });
}

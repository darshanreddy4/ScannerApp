import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/app.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/app/router.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/coins_fakes.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('with the real theme a document opens its menu, then the text recognition screen with working Save', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('sv_smoke2');
    addTearDown(() => root.deleteSync(recursive: true));
    final img = File('${root.path}/p.jpg')..writeAsStringSync('x');
    final local = DocumentLocalDataSource(rootDir: root);
    await tester.runAsync(
      () => DocumentRepositoryImpl(local).saveDocument(
        title: 'Lease',
        pages: [NewPage(imagePath: img.path, rawPath: img.path, width: 10, height: 10)],
      ),
    );
    await sl.reset();
    configureDependencies();
    sl
      ..unregister<AdService>()
      ..registerSingleton<AdService>(ScriptedAds())
      ..unregister<DocumentLocalDataSource>()
      ..registerSingleton<DocumentLocalDataSource>(local);

    appRouter.go('/'); // the router is a global, so start every test at home
    await tester.pumpWidget(const DoculoomApp());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    for (var i = 0; i < 20 && find.text('Lease').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Lease'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.more).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Extract text (OCR)'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Extract text (OCR)'));
    for (var i = 0; i < 20 && find.text('Extract the text').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Extract the text'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the real app opens the Settings tab and shows the text recognition option', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('sv_smoke');
    addTearDown(() => root.deleteSync(recursive: true));
    await sl.reset();
    configureDependencies();
    sl
      ..unregister<AdService>()
      ..registerSingleton<AdService>(ScriptedAds())
      ..unregister<DocumentLocalDataSource>()
      ..registerSingleton<DocumentLocalDataSource>(DocumentLocalDataSource(rootDir: root));

    appRouter.go('/'); // the router is a global, so start every test at home
    await tester.pumpWidget(const DoculoomApp());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Settings'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Text recognition language'), findsOneWidget);
  });

  testWidgets('a file address from Open with is not treated as a page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('sv_smoke3');
    addTearDown(() => root.deleteSync(recursive: true));
    await sl.reset();
    configureDependencies();
    sl
      ..unregister<AdService>()
      ..registerSingleton<AdService>(ScriptedAds())
      ..unregister<DocumentLocalDataSource>()
      ..registerSingleton<DocumentLocalDataSource>(DocumentLocalDataSource(rootDir: root));

    appRouter.go('content://com.oneplus.filemanager/root/storage/emulated/0/Android/data/x/Spurti%20Biodata.pdf');
    await tester.pumpWidget(const DoculoomApp());
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Page Not Found'), findsNothing);
    expect(find.text('Documents'), findsWidgets);
    expect(tester.takeException(), isNull);

    appRouter.go('file:///storage/emulated/0/Download/a.pdf');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Page Not Found'), findsNothing);
  });
}

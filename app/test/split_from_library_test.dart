import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:doculoom/features/documents/presentation/pages/home_page.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/coins_fakes.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('splitting a three-page document from the library list works end to end', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final root = Directory.systemTemp.createTempSync('sv_repro_root');
    final work = Directory.systemTemp.createTempSync('sv_repro_work');
    addTearDown(() {
      root.deleteSync(recursive: true);
      work.deleteSync(recursive: true);
    });
    final repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
    NewPage page(int i) {
      final f = File(p.join(work.path, 'p$i.jpg'))..writeAsStringSync('x$i');
      return NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10);
    }

    await tester.runAsync(() => repo.saveDocument(title: 'Three pages', pages: [page(1), page(2), page(3)]));

    sl
      ..registerSingleton<AdService>(ScriptedAds())
      ..registerSingleton<GetDocumentSize>(GetDocumentSize(repo))
      ..registerSingleton<SplitDocument>(SplitDocument(repo))
      ..registerSingleton<UpdateDocumentMeta>(UpdateDocumentMeta(repo));

    final docs = DocumentsCubit(
      listDocuments: ListDocuments(repo),
      listFolders: ListFolders(repo),
      deleteDocument: DeleteDocument(repo),
      renameDocument: RenameDocument(repo),
      moveDocument: MoveDocument(repo),
      mergeDocuments: MergeDocuments(repo),
      createFolder: CreateFolder(repo),
      renameFolder: RenameFolder(repo),
      updateFolderMeta: UpdateFolderMeta(repo),
      deleteFolder: DeleteFolder(repo),
    );
    await tester.runAsync(docs.load);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider(create: (_) => SettingsCubit(_Prefs())),
          BlocProvider.value(value: docs),
          BlocProvider(create: (_) => coinsCubit()),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Three pages'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.more).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Split document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split document'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'the chooser must lay out without framework errors');
    expect(find.text('Choose where the new document starts. Earlier pages stay here.'), findsOneWidget);

    await tester.tap(find.text('Pages 2 to 3'));
    // The busy dialog spins until the real file work ends, so let real time pass and then settle.
    await tester.pump();
    for (var i = 0; i < 40 && find.text('Splitting').evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Splitting'), findsNothing, reason: 'the busy dialog closes when the split is done');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Three pages'), findsOneWidget);
    expect(find.text('Three pages (part 2)'), findsOneWidget);
    final all = (await tester.runAsync(repo.listDocuments))!.valueOrNull!;
    expect({for (final d in all) d.title: d.pageCount}, {'Three pages': 1, 'Three pages (part 2)': 2});
  });
}

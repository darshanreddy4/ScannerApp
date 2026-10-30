import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
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

  late Directory root;
  late Directory work;
  late DocumentRepositoryImpl repo;

  setUp(() async {
    await sl.reset();
    root = Directory.systemTemp.createTempSync('sv_tag_root');
    work = Directory.systemTemp.createTempSync('sv_tag_work');
    repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
    work.deleteSync(recursive: true);
  });

  NewPage page(String name) {
    final f = File(p.join(work.path, '$name.jpg'))..writeAsStringSync(name);
    return NewPage(imagePath: f.path, rawPath: f.path, width: 10, height: 10);
  }

  Future<ScannedDocument> doc(String title, List<String> tags, {String? folderId}) async {
    final saved = (await repo.saveDocument(title: title, pages: [page(title)], folderId: folderId)).valueOrNull!;
    return (await repo.updateMeta(saved.id, tags: tags)).valueOrNull!;
  }

  DocumentsCubit cubit() => DocumentsCubit(
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

  test('tags are listed most used first, ignoring letter case, and never from locked folders', () async {
    final secret = (await repo.createFolder('Secret')).valueOrNull!;
    await repo.updateFolderMeta(secret.id, locked: true);
    await doc('a', ['Receipt']);
    await doc('b', ['receipt', 'Work']);
    await doc('c', ['ID']);
    await doc('d', ['Hidden', 'Receipt'], folderId: secret.id);

    final state = DocumentsState(
      status: LoadStatus.ready,
      documents: (await repo.listDocuments()).valueOrNull!,
      folders: (await repo.listFolders()).valueOrNull!,
    );
    expect(state.allTags.first.toLowerCase(), 'receipt');
    expect(state.allTags.map((t) => t.toLowerCase()), ['receipt', 'id', 'work']);
    expect(state.allTags.map((t) => t.toLowerCase()), isNot(contains('hidden')));
  });

  test('no tags at all gives an empty list', () {
    expect(const DocumentsState().allTags, isEmpty);
  });

  testWidgets('choosing a tag lists its documents from every folder, and choosing it again shows everything', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final folder = (await tester.runAsync(() => repo.createFolder('Trips')))!.valueOrNull!;
    await tester.runAsync(() async {
      await doc('Lunch bill', ['Receipt']);
      await doc('Taxi bill', ['receipt', 'Work'], folderId: folder.id);
      await doc('Passport copy', ['ID']);
    });
    sl.registerSingleton<AdService>(ScriptedAds());
    final docs = cubit();
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

    expect(find.byKey(const ValueKey('tag-filter-receipt')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-filter-id')), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-filter-work')), findsOneWidget);
    expect(find.text('Lunch bill'), findsOneWidget);
    expect(find.text('Taxi bill'), findsNothing, reason: 'it is inside a folder');
    expect(find.text('Trips'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-filter-receipt')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch bill'), findsOneWidget);
    expect(find.text('Taxi bill'), findsOneWidget, reason: 'a tag looks in every folder');
    expect(find.text('Passport copy'), findsNothing);
    expect(find.text('Trips'), findsNothing, reason: 'folders are hidden while filtering');
    expect(find.textContaining('2 results'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tag-filter-id')));
    await tester.pumpAndSettle();
    expect(find.text('Passport copy'), findsOneWidget);
    expect(find.text('Lunch bill'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tag-filter-id')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch bill'), findsOneWidget);
    expect(find.text('Passport copy'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
  });

  testWidgets('a library without tags shows no tag row', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => doc('Plain', []));
    sl.registerSingleton<AdService>(ScriptedAds());
    final docs = cubit();
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
    expect(find.byType(FilterChip), findsNothing);
  });
}

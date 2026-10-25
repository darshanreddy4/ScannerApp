import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scanvault/app/di.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/features/documents/domain/entities/compress_level.dart';
import 'package:scanvault/features/documents/domain/entities/scanned_document.dart';
import 'package:scanvault/features/documents/domain/repositories/document_repository.dart';
import 'package:scanvault/features/documents/domain/usecases/document_usecases.dart';
import 'package:scanvault/features/documents/presentation/widgets/document_actions.dart';
import 'package:scanvault/features/monetization/domain/entities/plan_status.dart';
import 'package:scanvault/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:scanvault/features/monetization/presentation/plan_cubit.dart';
import 'package:scanvault/features/settings/data/settings_repository.dart';
import 'package:scanvault/features/settings/domain/app_settings.dart';
import 'package:scanvault/features/settings/presentation/settings_cubit.dart';

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

class _Docs implements DocumentRepository {
  final metaCalls = <String>[];
  final splits = <(String, int)>[];

  @override
  Future<Result<ScannedDocument>> splitDocument({required String id, required int startPage}) async {
    splits.add((id, startPage));
    return Ok(_doc(pageCount: 2));
  }

  @override
  Future<Result<int>> documentSize(String id) async => const Ok(452 * 1024);

  @override
  Future<Result<ScannedDocument>> updateMeta(String id, {bool? favorite, bool? pinned, bool? locked, List<String>? tags, DateTime? date}) async {
    metaCalls.add('fav=$favorite pin=$pinned');
    return Ok(_doc(favorite: favorite ?? false, pinned: pinned ?? false));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

ScannedDocument _doc({bool favorite = false, bool pinned = false, int pageCount = 0}) => ScannedDocument(
  id: 'd1',
  title: 'Rent agreement',
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 2),
  pages: [for (var i = 0; i < pageCount; i++) DocumentPage(id: 'p$i', position: i, imagePath: '/x/$i.jpg', rawPath: '/x/r$i.jpg', width: 10, height: 10)],
  favorite: favorite,
  pinned: pinned,
);

void main() {
  late _Docs docs;

  setUpAll(() {
    docs = _Docs();
    sl.registerSingleton<GetDocumentSize>(GetDocumentSize(docs));
    sl.registerSingleton<UpdateDocumentMeta>(UpdateDocumentMeta(docs));
    sl.registerSingleton<SplitDocument>(SplitDocument(docs));
  });

  Future<void> open(WidgetTester tester, {double width = 360, int pages = 0}) async {
    tester.view.physicalSize = Size(width * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDocumentActions(context, _doc(pageCount: pages), refresh: () async {}),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/ocr',
          builder: (_, s) => Scaffold(body: Text('OCR ${(s.extra! as ScannedDocument).title}')),
        ),
        GoRoute(
          path: '/print',
          builder: (_, s) => Scaffold(body: Text('PRINT ${(s.extra! as ScannedDocument).title}')),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider(create: (_) => SettingsCubit(_Prefs())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet shows the header, quick actions and rows without overflow on a narrow phone', (tester) async {
    await open(tester, width: 320);

    expect(find.text('Rent agreement'), findsOneWidget);
    expect(find.textContaining('452 kB'), findsOneWidget);
    for (final label in ['Share PDF', 'Share images', 'Print', 'Compress', 'Lock', 'Delete']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Save to Files or Drive (PDF)'), findsOneWidget);
    expect(find.text('Move to folder'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet is not stretched across a tablet', (tester) async {
    await open(tester, width: 1280);
    expect(tester.getSize(find.byType(GridView)).width, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit and More expand to show the extra actions', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Split document'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Split document'), findsOneWidget);

    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Date and time'));
    await tester.pumpAndSettle();
    for (final label in ['Add to favourites', 'Pin to top', 'Tags', 'Duplicate', 'Date and time']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Extract text opens the text screen for the document', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Extract text (OCR)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract text (OCR)'));
    await tester.pumpAndSettle();
    expect(find.text('OCR Rent agreement'), findsOneWidget);
  });

  testWidgets('Print closes the sheet and opens the print screen for the document', (tester) async {
    await open(tester);
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();
    expect(find.text('PRINT Rent agreement'), findsOneWidget);
  });

  testWidgets('Split document opens a chooser and splits at the chosen page', (tester) async {
    docs.splits.clear();
    await open(tester, pages: 3);
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Split document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split document'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'the chooser must lay out without framework errors');
    expect(find.text('Choose where the new document starts. Earlier pages stay here.'), findsOneWidget);
    expect(find.text('Pages 2 to 3'), findsOneWidget);
    expect(find.text('Page 3 only'), findsOneWidget);

    await tester.tap(find.text('Pages 2 to 3'));
    await tester.pumpAndSettle();
    expect(docs.splits, [('d1', 2)]);
  });

  testWidgets('a one-page document explains why it cannot be split instead of doing nothing', (tester) async {
    docs.splits.clear();
    await open(tester, pages: 1);
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Split document'));
    await tester.pumpAndSettle();
    expect(find.text('Needs at least 2 pages'), findsOneWidget);
    await tester.tap(find.text('Split document'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where the new document starts. Earlier pages stay here.'), findsNothing);
    expect(docs.splits, isEmpty);
  });

  testWidgets('Add to favourites saves the change', (tester) async {
    docs.metaCalls.clear();
    await open(tester);
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add to favourites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();
    expect(docs.metaCalls, ['fav=true pin=null']);
  });

  test('compress levels describe themselves', () {
    for (final level in CompressLevel.values) {
      expect(level.label, isNotEmpty);
      expect(level.maxSide, greaterThan(0));
    }
  });
}

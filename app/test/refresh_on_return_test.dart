import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/app/router_observer.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/bloc/documents_cubit.dart';
import 'package:doculoom/features/documents/presentation/widgets/refresh_on_return.dart';

class _Repo implements DocumentRepository, FolderRepository {
  final List<ScannedDocument> docs = [];
  int lists = 0;

  @override
  Future<Result<List<ScannedDocument>>> listDocuments() async {
    lists++;
    return Ok([...docs]);
  }

  @override
  Future<Result<List<Folder>>> listFolders() async => const Ok([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

DocumentsCubit _cubit(_Repo r) => DocumentsCubit(
  listDocuments: ListDocuments(r),
  listFolders: ListFolders(r),
  deleteDocument: DeleteDocument(r),
  renameDocument: RenameDocument(r),
  moveDocument: MoveDocument(r),
  mergeDocuments: MergeDocuments(r),
  createFolder: CreateFolder(r),
  renameFolder: RenameFolder(r),
  updateFolderMeta: UpdateFolderMeta(r),
  deleteFolder: DeleteFolder(r),
);

ScannedDocument _doc(String title) => ScannedDocument(id: title, title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []);

void main() {
  testWidgets('the list shows a document saved or deleted on a screen opened above it as soon as that screen closes', (tester) async {
    final repo = _Repo();
    final cubit = _cubit(repo);
    await tester.runAsync(cubit.load);

    final router = GoRouter(
      observers: [routeObserver],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => RefreshOnReturn(
            child: Scaffold(
              body: BlocBuilder<DocumentsCubit, DocumentsState>(
                builder: (context, state) => Column(
                  children: [
                    for (final d in state.documents) Text(d.title),
                    TextButton(onPressed: () => context.push('/detail'), child: const Text('OPEN')),
                  ],
                ),
              ),
            ),
          ),
          routes: [
            GoRoute(
              path: 'detail',
              builder: (_, _) => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(onPressed: () => context.pop(), child: const Text('BACK')),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scan 1'), findsNothing);
    final before = repo.lists;

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    // A document is created while the other screen is open (for example, after the ad).
    repo.docs.add(_doc('Scan 1'));
    await tester.tap(find.text('BACK'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(repo.lists, greaterThan(before));
    expect(find.text('Scan 1'), findsOneWidget, reason: 'no manual refresh or restart needed');

    // And a deletion shows up the same way.
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    repo.docs.clear();
    await tester.tap(find.text('BACK'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Scan 1'), findsNothing);
  });

  testWidgets('opening a screen on top does not reload by itself', (tester) async {
    final repo = _Repo();
    final cubit = _cubit(repo);
    await tester.runAsync(cubit.load);
    final router = GoRouter(
      observers: [routeObserver],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => RefreshOnReturn(
            child: Scaffold(
              body: TextButton(onPressed: () => context.push('/detail'), child: const Text('OPEN')),
            ),
          ),
          routes: [
            GoRoute(
              path: 'detail',
              builder: (_, _) => const Scaffold(body: Text('DETAIL')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final before = repo.lists;
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(repo.lists, before);
  });
}

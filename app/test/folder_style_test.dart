import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/presentation/widgets/folder_editor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('a folder keeps its icon and colour, and they can be changed or cleared', () async {
    final root = Directory.systemTemp.createTempSync('sv_fstyle');
    addTearDown(() => root.deleteSync(recursive: true));
    final repo = DocumentRepositoryImpl(DocumentLocalDataSource(rootDir: root));

    final car = (await repo.createFolder('Vehicle', style: const FolderStyle(icon: 'car', color: 0xFF16A34A))).valueOrNull!;
    final plain = (await repo.createFolder('Plain')).valueOrNull!;
    var folders = (await repo.listFolders()).valueOrNull!;
    expect(folders.firstWhere((f) => f.id == car.id).icon, 'car');
    expect(folders.firstWhere((f) => f.id == car.id).color, 0xFF16A34A);
    expect(folders.firstWhere((f) => f.id == plain.id).icon, isNull);

    await repo.updateFolderMeta(plain.id, style: const FolderStyle(icon: FolderStyle.textOnly, color: 0xFFDB2777));
    await repo.updateFolderMeta(plain.id, favorite: true);
    folders = (await repo.listFolders()).valueOrNull!;
    final saved = folders.firstWhere((f) => f.id == plain.id);
    expect(saved.icon, FolderStyle.textOnly);
    expect(saved.color, 0xFFDB2777);
    expect(saved.favorite, isTrue, reason: 'flags and style are saved separately');

    await repo.updateFolderMeta(plain.id, style: const FolderStyle());
    expect((await repo.listFolders()).valueOrNull!.firstWhere((f) => f.id == plain.id).icon, isNull);
  });

  testWidgets('the folder editor returns the name, icon and colour that were chosen', (tester) async {
    FolderEdit? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showFolderEditor(context, title: 'New folder'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('New folder'), findsOneWidget, reason: 'an empty name is not accepted');

    await tester.enterText(find.byKey(const ValueKey('folder-name')), 'Bank');
    await tester.tap(find.byKey(const ValueKey('icon-bank')));
    await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('color-ffdb2777')));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.name, 'Bank');
    expect(result!.style.icon, 'bank');
    expect(result!.style.color, 0xFFDB2777);
  });

  testWidgets('choosing Aa makes a text-only folder and editing keeps the current look', (tester) async {
    final folder = Folder(id: '1', name: 'Invoices', createdAt: DateTime(2026), icon: 'invoice', color: 0xFFEA580C);
    FolderEdit? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showFolderEditor(context, title: 'Edit folder', folder: folder),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Invoices'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.style, const FolderStyle(icon: 'invoice', color: 0xFFEA580C));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('icon-text')));
    await tester.pump();
    expect(find.text('I'), findsOneWidget, reason: 'the badge shows the first letter');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result!.style.icon, FolderStyle.textOnly);
  });
}

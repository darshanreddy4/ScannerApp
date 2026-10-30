import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/export/data/share_packager.dart';
import 'package:doculoom/features/export/domain/entities/export_options.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_protector.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/export/domain/usecases/export_usecases.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/ocr/domain/recognize_document_text.dart';
import 'package:doculoom/features/ocr/domain/text_repository.dart';
import 'package:doculoom/features/scanner/domain/entities/scan_mode.dart';
import 'package:doculoom/features/scanner/presentation/mode_followup.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';

import 'support/coins_fakes.dart';
import 'support/folder_fakes.dart';

var _settings = const AppSettings();

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => _settings;
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Docs implements DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  List<String>? tags;
  DateTime? expires;
  String? renamed;

  /// What the saved document is called and where it is, so the copy returned after a change keeps them.
  String title = 'Scan';
  String? folderId;

  @override
  Future<Result<ScannedDocument>> updateMeta(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  }) async {
    if (tags != null) this.tags = tags;
    if (expires != null) this.expires = expires;
    return Ok(_doc(title: title, tags: tags ?? const [], expiresAt: expires, folderId: folderId));
  }

  @override
  Future<Result<ScannedDocument>> renameDocument(String id, String title) async {
    renamed = title;
    this.title = title;
    return Ok(_doc(title: title, folderId: folderId));
  }
}

ScannedDocument _doc({String title = 'Scan', List<String> tags = const [], DateTime? expiresAt, int pages = 1, String? folderId}) => ScannedDocument(
  id: 'd1',
  folderId: folderId,
  title: title,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  pages: [for (var i = 0; i < pages; i++) DocumentPage(id: 'p$i', position: i, imagePath: '/p$i.jpg', rawPath: '/p$i.jpg', width: 10, height: 10)],
  tags: tags,
  expiresAt: expiresAt,
);

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Export implements ExportRepository {
  final exported = <ScannedDocument>[];
  @override
  Future<Result<String>> export({required ScannedDocument document, required ExportFormat format, required ExportQuality quality}) async {
    exported.add(document);
    return const Ok('/tmp/receipt.pdf');
  }
}

class _NoProtector implements PdfProtector {
  const _NoProtector();
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Share implements ShareService {
  final shared = <({String path, String mime, String? subject})>[];
  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    shared.add((path: path, mime: mimeType, subject: subject));
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Engine implements OcrEngine {
  _Engine(this.text, {this.fail = false});
  final String text;
  final bool fail;
  int reads = 0;

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async {
    reads++;
    if (fail) return const Err(OcrFailure('no text engine'));
    return Ok(
      OcrPageResult(
        width: 10,
        height: 10,
        blocks: [
          OcrBlock(lines: [for (final l in text.split('\n')) OcrLine(text: l, left: 0, top: 0, right: 1, bottom: 1)]),
        ],
      ),
    );
  }
}

class _Texts implements TextRepository {
  int saved = 0;
  @override
  Future<Result<void>> saveText(String documentId, List<PageText> pages) async {
    saved++;
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Docs docs;
  late _Texts texts;
  ModeNext? returned;
  late _Export export;
  late _Share share;
  late _Engine engine;
  late FakeFolders folders;
  late FakeMover mover;
  var finished = false;

  setUp(() async {
    await sl.reset();
    docs = _Docs();
    texts = _Texts();
    returned = null;
    finished = false;
    _settings = const AppSettings();
    sl
      ..registerSingleton(UpdateDocumentMeta(docs))
      ..registerSingleton(RenameDocument(docs))
      ..registerSingleton<AdService>(ScriptedAds())
      ..registerSingleton(ExportDocument(export = _Export()))
      ..registerSingleton(ShareFile(share = _Share()))
      ..registerSingleton<ShareService>(share)
      ..registerSingleton(const SharePackager(_NoProtector()));
    final fakes = registerFolderFakes();
    folders = fakes.folders;
    mover = fakes.mover;
  });

  Future<void> run(WidgetTester tester, ScanMode mode, {String text = '', bool failOcr = false, int pages = 1, String title = 'Scan', String? folderId}) async {
    docs
      ..title = title
      ..folderId = folderId;
    engine = _Engine(text, fail: failOcr);
    sl
      ..registerSingleton<OcrEngine>(engine)
      ..registerSingleton(RecognizeDocumentText(engine, texts));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(lazy: false, create: (_) => SettingsCubit(_Prefs())..load()),
          BlocProvider(create: (_) => PlanCubit(_Plans())),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('go'),
                onPressed: () async {
                  returned = await runModeFollowUp(context, mode, _doc(pages: pages, title: title, folderId: folderId));
                  finished = true;
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('a plain document is left alone: no tag, no reading, no questions', (tester) async {
    await run(tester, ScanMode.document);
    expect(finished, isTrue);
    expect(docs.tags, isNull);
    expect(docs.renamed, isNull);
    expect(returned, isNull);
    expect(texts.saved, 0);
  });

  testWidgets('a receipt is read on the device, renamed from its shop, total and date, and tagged', (tester) async {
    await run(tester, ScanMode.receipt, text: 'FRESH MART\n31/01/2026\nTOTAL 4.94');
    await tester.pumpAndSettle();
    expect(docs.tags, ['Receipt']);
    expect(docs.renamed, 'Receipt - FRESH MART - 4.94 - 2026-01-31');
    expect(texts.saved, 1, reason: 'the text is kept so the receipt can be found by its words');
    expect(find.text('Receipt saved'), findsOneWidget);
    expect(find.text('Receipt - FRESH MART - 4.94 - 2026-01-31'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receipt-done')));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(share.shared, isEmpty, reason: 'Done shares nothing');
    expect(returned, isNull);
  });

  testWidgets('Share PDF on a saved receipt builds the PDF of the renamed receipt and opens the share sheet', (tester) async {
    await run(tester, ScanMode.receipt, text: 'FRESH MART\nTOTAL 4.94');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-go')));
    await tester.pumpAndSettle();
    expect(export.exported.single.title, startsWith('Receipt - FRESH MART - 4.94'));
    expect(share.shared.single.path, '/tmp/receipt.pdf');
    expect(share.shared.single.mime, 'application/pdf');
    expect(share.shared.single.subject, startsWith('Receipt - FRESH MART'));
    expect(finished, isTrue);
  });

  testWidgets('a receipt with nothing readable keeps its name and says so', (tester) async {
    await run(tester, ScanMode.receipt, text: '');
    await tester.pumpAndSettle();
    expect(docs.renamed, isNull);
    expect(find.textContaining('name was left as it is'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receipt-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('share-go')));
    await tester.pumpAndSettle();
    expect(export.exported.single.title, 'Scan', reason: 'it can still be shared under its old name');
  });

  testWidgets('a receipt whose text cannot be read still saves, with the failure shown', (tester) async {
    await run(tester, ScanMode.receipt, failOcr: true);
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(docs.renamed, isNull);
    expect(find.textContaining('no text engine'), findsOneWidget);
  });

  testWidgets('a business card hands its text over for the contact screen', (tester) async {
    await run(tester, ScanMode.card, text: 'Jane Doe\nDesigner\n+44 20 7946 0958');
    await tester.pumpAndSettle();
    expect(docs.tags, ['Card']);
    expect(returned!.contactText, 'Jane Doe\nDesigner\n+44 20 7946 0958');
    expect(returned!.idPhotos, isNull);
    expect(docs.renamed, isNull);
  });

  testWidgets('an ID asks for the expiry date and stores it', (tester) async {
    await run(tester, ScanMode.id);
    expect(find.text('When does this ID expire?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('id-expiry-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(docs.tags, ['ID']);
    expect(docs.expires, isNotNull);
    expect(docs.expires!.year, DateTime.now().year + 1);
    expect(finished, isTrue);
  });

  testWidgets('skipping the ID date, or closing the calendar, saves no date', (tester) async {
    await run(tester, ScanMode.id);
    await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
    await tester.pumpAndSettle();
    expect(docs.expires, isNull);
    expect(finished, isTrue);

    finished = false;
    await tester.tap(find.byKey(const ValueKey('go')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('id-expiry-pick')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(docs.expires, isNull);
    expect(finished, isTrue);
  });

  testWidgets('an ID with a front and a back offers one page for both, and hands over both photos in order', (tester) async {
    await run(tester, ScanMode.id, pages: 2);
    await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Put front and back on one page?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('id-combine-yes')));
    await tester.pumpAndSettle();
    expect(returned!.idPhotos, ['/p0.jpg', '/p1.jpg']);
    expect(returned!.contactText, isNull);
  });

  testWidgets('saying not now to the one-page copy leaves it at that', (tester) async {
    await run(tester, ScanMode.id, pages: 2);
    await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('id-combine-skip')));
    await tester.pumpAndSettle();
    expect(returned, isNull);
    expect(finished, isTrue);
  });

  testWidgets('an ID with a single photo does not offer the one-page copy', (tester) async {
    await run(tester, ScanMode.id, pages: 1);
    await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Put front and back on one page?'), findsNothing);
    expect(returned, isNull);
  });

  testWidgets('an ID with more than two photos does not offer the one-page copy either', (tester) async {
    await run(tester, ScanMode.id, pages: 3);
    await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Put front and back on one page?'), findsNothing);
    expect(returned, isNull);
  });

  testWidgets('Book and Whiteboard only add their tag', (tester) async {
    await run(tester, ScanMode.book);
    await tester.pumpAndSettle();
    expect(docs.tags, ['Book']);
    expect(returned, isNull);
    expect(docs.renamed, isNull);
  });

  group('naming and filing a new scan', () {
    const fresh = 'Scan 2026-10-25 14.07';

    testWidgets('a plain document with the app\'s own name is named from the heading on its first page, and stays where it is', (tester) async {
      await run(tester, ScanMode.document, text: 'Rental Agreement\nThis agreement is made between the parties', title: fresh);
      await tester.pumpAndSettle();
      expect(docs.renamed, 'Rental Agreement');
      expect(engine.reads, 1, reason: 'only the first page is read for a name');
      expect(folders.created, isEmpty);
      expect(mover.moves, isEmpty);
      expect(docs.tags, isNull, reason: 'a plain document gets no tag');
      expect(finished, isTrue);
    });

    testWidgets('only the first page is read, however long the scan is', (tester) async {
      await run(tester, ScanMode.document, text: 'Invoice 4411\nrows', title: fresh, pages: 6);
      await tester.pumpAndSettle();
      expect(engine.reads, 1);
      expect(docs.renamed, 'Invoice 4411');
    });

    testWidgets('a name the person chose is never touched, and nothing is read', (tester) async {
      await run(tester, ScanMode.document, text: 'Rental Agreement', title: 'My lease');
      await tester.pumpAndSettle();
      expect(docs.renamed, isNull);
      expect(engine.reads, 0);
    });

    testWidgets('with naming turned off nothing is read or renamed', (tester) async {
      _settings = const AppSettings(autoName: false);
      await run(tester, ScanMode.document, text: 'Rental Agreement', title: fresh);
      await tester.pumpAndSettle();
      expect(docs.renamed, isNull);
      expect(engine.reads, 0);
    });

    testWidgets('a page with a date but no heading is named from the date', (tester) async {
      await run(tester, ScanMode.document, text: '12/03/2026\n55', title: fresh);
      await tester.pumpAndSettle();
      expect(docs.renamed, 'Scan 12 Mar 2026');
    });

    testWidgets('a page that cannot be read, or has nothing to name it by, keeps its default name', (tester) async {
      await run(tester, ScanMode.document, failOcr: true, title: fresh);
      await tester.pumpAndSettle();
      expect(docs.renamed, isNull);
      expect(finished, isTrue);
      expect(find.byType(AlertDialog), findsNothing);

      finished = false;
      await sl.reset();
      docs = _Docs();
      sl
        ..registerSingleton(UpdateDocumentMeta(docs))
        ..registerSingleton(RenameDocument(docs))
        ..registerSingleton<AdService>(ScriptedAds());
      registerFolderFakes();
      await run(tester, ScanMode.document, text: '1234 5678\n42', title: fresh);
      await tester.pumpAndSettle();
      expect(docs.renamed, isNull);
      expect(finished, isTrue);
    });

    testWidgets('a whiteboard is named from its writing and filed into Whiteboards, which is made once', (tester) async {
      await run(tester, ScanMode.whiteboard, text: 'Sprint planning\nGoals', title: fresh);
      await tester.pumpAndSettle();
      expect(docs.tags, ['Whiteboard']);
      expect(docs.renamed, 'Sprint planning');
      expect(folders.created.single.name, 'Whiteboards');
      expect(folders.created.single.style.icon, 'office');
      expect(mover.moves.single, (id: 'd1', folderId: 'f1'));

      finished = false;
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(folders.created, hasLength(1), reason: 'the second scan uses the folder that is there');
      expect(mover.moves, hasLength(2));
      expect(mover.moves.last.folderId, 'f1');
    });

    testWidgets('a folder the person already has with that name is used, whatever its letter case', (tester) async {
      folders.folders.add(Folder(id: 'mine', name: ' receipts ', createdAt: DateTime(2025)));
      await run(tester, ScanMode.receipt, text: 'FRESH MART\nTOTAL 4.94');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-done')));
      await tester.pumpAndSettle();
      expect(folders.created, isEmpty);
      expect(mover.moves.single.folderId, 'mine');
    });

    testWidgets('a scan started inside a folder stays in it', (tester) async {
      await run(tester, ScanMode.receipt, text: 'FRESH MART\nTOTAL 4.94', folderId: 'invoices');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('receipt-done')));
      await tester.pumpAndSettle();
      expect(mover.moves, isEmpty);
      expect(folders.created, isEmpty);
    });

    testWidgets('with filing turned off no folder is made and nothing is moved', (tester) async {
      _settings = const AppSettings(smartFolders: false);
      await run(tester, ScanMode.id);
      await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
      await tester.pumpAndSettle();
      expect(folders.created, isEmpty);
      expect(mover.moves, isEmpty);
      expect(finished, isTrue);
    });

    testWidgets('an ID is filed into IDs and is never read for a name', (tester) async {
      await run(tester, ScanMode.id, text: 'REPUBLIC OF NOWHERE\nPASSPORT', title: fresh);
      await tester.tap(find.byKey(const ValueKey('id-expiry-skip')));
      await tester.pumpAndSettle();
      expect(engine.reads, 0, reason: 'what is on an ID is not read unless the person asks');
      expect(docs.renamed, isNull);
      expect(folders.created.single.name, 'IDs');
      expect(mover.moves.single.folderId, 'f1');
    });

    testWidgets('a business card is named after the person and filed into Business cards', (tester) async {
      await run(tester, ScanMode.card, text: 'Jane Doe\nDesigner\n+44 20 7946 0958', title: fresh);
      await tester.pumpAndSettle();
      expect(docs.renamed, 'Jane Doe');
      expect(returned!.contactText, contains('Jane Doe'));
      expect(folders.created.single.name, 'Business cards');
      expect(mover.moves, hasLength(1));
    });

    testWidgets('a card with a name the person chose keeps it, and is still filed', (tester) async {
      await run(tester, ScanMode.card, text: 'Jane Doe\nDesigner\n+44 20 7946 0958', title: 'Jane at the fair');
      await tester.pumpAndSettle();
      expect(docs.renamed, isNull);
      expect(mover.moves, hasLength(1));
    });

    testWidgets('a table is tagged, filed into Tables, not read yet, and hands its page pictures over for the spreadsheet', (tester) async {
      await run(tester, ScanMode.table, text: 'Item  Qty', title: fresh, pages: 2);
      await tester.pumpAndSettle();
      expect(docs.tags, ['Table']);
      expect(returned!.tablePages, ['/p0.jpg', '/p1.jpg']);
      expect(returned!.contactText, isNull);
      expect(returned!.idPhotos, isNull);
      expect(engine.reads, 0, reason: 'the table screen reads the pictures, with its own progress');
      expect(docs.renamed, isNull);
      expect(folders.created.single.name, 'Tables');
      expect(mover.moves.single.folderId, 'f1');
    });

    testWidgets('a book is filed into Books and not named', (tester) async {
      await run(tester, ScanMode.book, text: 'Chapter One', title: fresh);
      await tester.pumpAndSettle();
      expect(engine.reads, 0);
      expect(docs.renamed, isNull);
      expect(folders.created.single.name, 'Books');
    });

    testWidgets('a folder that cannot be listed, made or moved into never stops the scan from finishing', (tester) async {
      folders.failList = true;
      await run(tester, ScanMode.card, text: 'Jane Doe\n+44 20 7946 0958', title: fresh);
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(returned!.contactText, isNotNull);
      expect(mover.moves, isEmpty);

      folders.failList = false;
      folders.failCreate = true;
      finished = false;
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
      expect(mover.moves, isEmpty);

      folders.failCreate = false;
      mover.fail = true;
      finished = false;
      await tester.tap(find.byKey(const ValueKey('go')));
      await tester.pumpAndSettle();
      expect(finished, isTrue);
    });
  });
}

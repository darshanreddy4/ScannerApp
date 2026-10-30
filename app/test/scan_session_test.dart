import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/prepared_image.dart';
import 'package:doculoom/features/scanner/domain/entities/quad.dart';
import 'package:doculoom/features/scanner/domain/entities/scan_mode.dart';
import 'package:doculoom/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:doculoom/features/scanner/domain/usecases/scanner_usecases.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';

class _FakeScanner implements ScannerRepository {
  int counter = 0;
  final Set<String> failing = {};
  bool detects = true;

  String _next() => '/tmp/fake_${counter++}.jpg';

  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) async {
    if (failing.contains(sourcePath)) return const Err(ImageProcessingFailure('bad image'));
    return Ok(PreparedImage(path: _next(), width: 100, height: 200, detectedQuad: detects ? Quad.defaultInset : null));
  }

  @override
  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad}) async => Ok(ImageFileInfo(path: _next(), width: 80, height: 160));

  @override
  Future<Result<ImageFileInfo>> imageInfo(String imagePath) async => Ok(ImageFileInfo(path: imagePath, width: 100, height: 200));

  @override
  Future<Result<ImageFileInfo>> rotate90(String imagePath) async => Ok(ImageFileInfo(path: _next(), width: 160, height: 80));

  @override
  Future<Result<Uint8List>> previewFilter({required String imagePath, required FilterSettings settings}) async => Ok(Uint8List.fromList([1, 2, 3]));

  @override
  Future<Result<List<Uint8List>>> previewFilterBatch({required String imagePath, required List<FilterSettings> variants, int maxSide = 180}) async => Ok([
    for (final _ in variants) Uint8List.fromList([9]),
  ]);

  @override
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) async =>
      Ok(ImageFileInfo(path: _next(), width: 80, height: 160));
}

class _FakeImporter implements DocumentImporter {
  bool fail = false;

  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) async {
    if (fail) return const Err(ImportFailure('password protected'));
    onProgress?.call(1, 2);
    onProgress?.call(2, 2);
    return const Ok(ImportedDocument(title: 'Contract', imagePaths: ['/p1.jpg', '/p2.jpg']));
  }
}

class _FakeDocs implements DocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  List<NewPage>? savedPages;
  String? savedTitle;
  String? savedFolder;
  String? updatedId;

  @override
  Future<Result<ScannedDocument>> updateDocument({required String id, required String title, required List<NewPage> pages}) async {
    updatedId = id;
    savedTitle = title;
    savedPages = pages;
    return Ok(ScannedDocument(id: id, title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []));
  }

  @override
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages, String? folderId}) async {
    savedPages = pages;
    savedTitle = title;
    savedFolder = folderId;
    return Ok(ScannedDocument(id: 'd1', title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const [], folderId: folderId));
  }

  @override
  Future<Result<void>> deleteDocument(String id) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> getDocument(String id) => throw UnimplementedError();
  @override
  Future<Result<List<ScannedDocument>>> listDocuments() => throw UnimplementedError();
  @override
  Future<Result<void>> moveDocument(String id, String? folderId) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> renameDocument(String id, String title) => throw UnimplementedError();
  @override
  Future<Result<ScannedDocument>> mergeDocuments({required List<String> ids, required String title, String? folderId, required bool deleteOriginals}) =>
      throw UnimplementedError();
}

ScanSessionCubit _cubit(_FakeScanner scanner, _FakeDocs docs, [DocumentImporter? importer]) => ScanSessionCubit(
  prepareImage: PrepareImage(scanner),
  inspectImage: InspectImage(scanner),
  cropDocument: CropDocument(scanner),
  rotateImage: RotateImage(scanner),
  previewFilter: PreviewFilter(scanner),
  previewFilterBatch: PreviewFilterBatch(scanner),
  applyFilter: ApplyFilter(scanner),
  saveDocument: SaveDocument(docs),
  updateDocument: UpdateDocument(docs),
  importDocumentFile: ImportDocumentFile(importer ?? _FakeImporter()),
);

void main() {
  importTests();
  late _FakeScanner scanner;
  late _FakeDocs docs;
  late ScanSessionCubit cubit;

  setUp(() {
    scanner = _FakeScanner();
    docs = _FakeDocs();
    cubit = _cubit(scanner, docs)..start(defaultFilter: ScanFilter.magicColor, folderId: 'f1');
  });

  tearDown(() => cubit.close());

  test('capturing several pages in a row keeps adding to the same session', () async {
    for (var i = 0; i < 3; i++) {
      expect(await cubit.beginDraft('/img$i.jpg'), isTrue);
      expect(cubit.state.draft!.settings.filter, ScanFilter.magicColor);
      expect(await cubit.commitDraft(), CropOutcome.finished);
    }
    expect(cubit.state.pages.length, 3);
    expect(cubit.state.draft, isNull);
    expect(cubit.state.selected, 2);
  });

  test('importing many images walks the queue and ends finished', () async {
    expect(await cubit.importMany(['/a.jpg', '/b.jpg', '/c.jpg']), isTrue);
    expect(cubit.state.pending.length, 2);
    expect(await cubit.commitDraft(), CropOutcome.nextImage);
    expect(await cubit.commitDraft(), CropOutcome.nextImage);
    expect(await cubit.commitDraft(), CropOutcome.finished);
    expect(cubit.state.pages.length, 3);
  });

  test('commitAll adds every queued image without UI', () async {
    await cubit.importMany(['/a.jpg', '/b.jpg', '/c.jpg', '/d.jpg']);
    expect(await cubit.commitAll(), isTrue);
    expect(cubit.state.pages.length, 4);
  });

  test('retake on a queued import skips to the next image', () async {
    await cubit.importMany(['/a.jpg', '/b.jpg']);
    expect(await cubit.discardDraft(), CropOutcome.nextImage);
    expect(await cubit.commitDraft(), CropOutcome.finished);
    expect(cubit.state.pages.length, 1);
  });

  test('an unreadable image in the queue is skipped, not fatal', () async {
    scanner.failing.add('/bad.jpg');
    await cubit.importMany(['/a.jpg', '/bad.jpg', '/c.jpg']);
    expect(await cubit.commitDraft(), CropOutcome.nextImage); // a -> c
    expect(await cubit.commitDraft(), CropOutcome.finished);
    expect(cubit.state.pages.length, 2);
  });

  test('current filter chosen on the crop screen applies to the next captures', () async {
    await cubit.beginDraft('/a.jpg');
    cubit.setCurrentFilter(ScanFilter.documentBw);
    await cubit.commitDraft();
    await cubit.beginDraft('/b.jpg');
    expect(cubit.state.draft!.settings.filter, ScanFilter.documentBw);
  });

  group('scan modes', () {
    test('a mode renames a fresh scan and never changes the look of the photos', () async {
      cubit.start(defaultFilter: ScanFilter.original);
      for (final mode in ScanMode.values) {
        cubit.setMode(mode);
        expect(cubit.state.currentFilter, ScanFilter.original, reason: mode.name);
        await cubit.beginDraft('/a.jpg');
        expect(cubit.state.draft!.settings, const FilterSettings(), reason: '${mode.name}: original colours, no contrast change');
        await cubit.discardDraft();
      }
      cubit.setMode(ScanMode.whiteboard);
      expect(cubit.state.title, startsWith('Whiteboard '));
    });

    test('the filter picked in Settings still applies in every mode', () async {
      cubit.start(defaultFilter: ScanFilter.grayscale);
      cubit.setMode(ScanMode.receipt);
      await cubit.beginDraft('/a.jpg');
      expect(cubit.state.draft!.settings.filter, ScanFilter.grayscale);
    });

    test('switching mode after pages exist keeps the name the user may rely on', () async {
      await cubit.beginDraft('/a.jpg');
      await cubit.commitDraft();
      final title = cubit.state.title;
      cubit.setMode(ScanMode.receipt);
      expect(cubit.state.title, title);
    });

    test('a card mode crops to the viewfinder frame when no outline is found', () async {
      scanner.detects = false;
      cubit.setMode(ScanMode.id);
      await cubit.beginDraft('/a.jpg'); // fake image is 100 x 200
      final quad = cubit.state.draft!.quad;
      expect(quad, ScanMode.id.guideQuad(0.5));
      expect((quad.tl.x + quad.br.x) / 2, closeTo(0.5, 1e-9));
      expect((quad.tl.y + quad.br.y) / 2, closeTo(0.5, 1e-9));
      final pixelsW = (quad.br.x - quad.tl.x) * 100;
      final pixelsH = (quad.br.y - quad.tl.y) * 200;
      expect(pixelsW / pixelsH, closeTo(1.586, 1e-6));
    });

    test('an outline that is not card-shaped is ignored in a card mode, in favour of the frame', () async {
      cubit.setMode(ScanMode.id);
      await cubit.beginDraft('/a.jpg'); // the fake finds the 0.08..0.92 inset, far bigger than a card on a 100 x 200 picture
      expect(cubit.state.draft!.quad, ScanMode.id.guideQuad(0.5));
    });

    test('without an outline a plain scan starts with the whole picture, not a trimmed edge', () async {
      scanner.detects = false;
      cubit.setMode(ScanMode.document);
      await cubit.beginDraft('/b.jpg');
      expect(cubit.state.draft!.quad, Quad.fullFrame);
    });

    test('the frame stays inside the picture in any shape', () {
      for (final aspect in [0.3, 0.5625, 0.75, 1.0, 1.78, 3.0]) {
        for (final mode in [ScanMode.card, ScanMode.id]) {
          final q = mode.guideQuad(aspect)!;
          expect(q.tl.x, greaterThanOrEqualTo(0));
          expect(q.tl.y, greaterThanOrEqualTo(0));
          expect(q.br.x, lessThanOrEqualTo(1));
          expect(q.br.y, lessThanOrEqualTo(1));
          expect((q.br.x - q.tl.x) * aspect / (q.br.y - q.tl.y), closeTo(mode.cardAspect!, 1e-6));
        }
      }
      expect(ScanMode.document.guideQuad(0.5), isNull);
      expect(ScanMode.book.guideQuad(0.5), isNull);
    });

    test('Book splits a spread into a left and a right page; one crop each', () async {
      cubit.setMode(ScanMode.book);
      await cubit.beginDraft('/a.jpg');
      expect(await cubit.commitDraft(), CropOutcome.finished);
      expect(cubit.state.pages.length, 2);
      expect(cubit.state.pages[0].id, isNot(cubit.state.pages[1].id));
      expect(cubit.state.pages[0].quad.tr.x, closeTo((Quad.defaultInset.tl.x + Quad.defaultInset.tr.x) / 2, 1e-9));
      expect(cubit.state.pages[1].quad.tl, cubit.state.pages[0].quad.tr);
      expect(cubit.state.selected, 0);
    });

    test('recropping one page of a book does not split it again', () async {
      cubit.setMode(ScanMode.book);
      await cubit.beginDraft('/a.jpg');
      await cubit.commitDraft();
      cubit.editPageCrop(1);
      await cubit.commitDraft();
      expect(cubit.state.pages.length, 2);
    });

    test('saving goes back to Document mode and the Settings filter', () async {
      cubit.setMode(ScanMode.receipt);
      await cubit.beginDraft('/a.jpg');
      await cubit.commitDraft();
      await cubit.save();
      expect(cubit.state.mode, ScanMode.document);
      expect(cubit.state.currentFilter, ScanFilter.magicColor);
    });
  });

  test('crop screen shows the filtered preview and clears it for Original', () async {
    await cubit.beginDraft('/a.jpg');
    cubit.setCurrentFilter(ScanFilter.documentBw);
    await cubit.refreshDraftPreview();
    expect(cubit.state.draftPreview, isNotNull);

    cubit.setCurrentFilter(ScanFilter.original);
    await cubit.refreshDraftPreview();
    expect(cubit.state.draftPreview, isNull);
  });

  test('apply to all pages changes every page, otherwise only the selected one', () async {
    await cubit.commitAllFor(['/a.jpg', '/b.jpg', '/c.jpg']);
    cubit.selectPage(1);
    cubit.updateSettings(const FilterSettings(filter: ScanFilter.grayscale));
    expect(cubit.state.pages.map((p) => p.settings.filter), [ScanFilter.magicColor, ScanFilter.grayscale, ScanFilter.magicColor]);

    cubit.setApplyToAll(true);
    cubit.updateSettings(const FilterSettings(filter: ScanFilter.documentBw, brightness: 10));
    expect(cubit.state.pages.every((p) => p.settings.filter == ScanFilter.documentBw && p.settings.brightness == 10), isTrue);
  });

  test('re-cropping a page replaces it instead of appending', () async {
    await cubit.commitAllFor(['/a.jpg', '/b.jpg']);
    final before = cubit.state.pages[0].croppedPath;
    cubit.editPageCrop(0);
    expect(cubit.state.flow, ScanFlow.recrop);
    expect(await cubit.commitDraft(), CropOutcome.finished);
    expect(cubit.state.pages.length, 2);
    expect(cubit.state.pages[0].croppedPath, isNot(before));
  });

  test('reorder and remove keep the selection valid', () async {
    await cubit.commitAllFor(['/a.jpg', '/b.jpg', '/c.jpg']);
    final ids = cubit.state.pages.map((p) => p.id).toList();
    cubit.reorderPages(0, 2);
    expect(cubit.state.pages.map((p) => p.id), [ids[1], ids[2], ids[0]]);
    cubit.removePage(2);
    expect(cubit.state.pages.length, 2);
    expect(cubit.state.selected, lessThan(2));
  });

  test('a removed page can be restored in place (Undo)', () async {
    await cubit.commitAllFor(['/a.jpg', '/b.jpg', '/c.jpg']);
    final ids = cubit.state.pages.map((p) => p.id).toList();
    final removed = cubit.state.pages[1];
    cubit.removePage(1);
    expect(cubit.state.pages.length, 2);
    cubit.restorePage(1, removed);
    expect(cubit.state.pages.map((p) => p.id), ids);
    expect(cubit.state.selected, 1);
  });

  test('loading a saved document restores crops and filters, and save updates it in place', () async {
    final saved = ScannedDocument(
      id: 'doc-9',
      title: 'Saved one',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      folderId: 'f9',
      pages: const [
        DocumentPage(
          id: 'p1',
          position: 0,
          imagePath: '/docs/page_0.jpg',
          rawPath: '/docs/raw_0.jpg',
          width: 800,
          height: 1200,
          edit: PageEditInfo(
            croppedPath: '/docs/cropped_0.jpg',
            quad: [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9],
            filter: 'grayscale',
            brightness: 20,
            contrast: 5,
            rawWidth: 4000,
            rawHeight: 3000,
          ),
        ),
        DocumentPage(id: 'p2', position: 1, imagePath: '/docs/page_1.jpg', rawPath: '/docs/raw_1.jpg', width: 500, height: 700),
      ],
    );

    cubit.loadDocument(saved, defaultFilter: ScanFilter.magicColor);
    final first = cubit.state.pages[0];
    expect(first.settings.filter, ScanFilter.grayscale);
    expect(first.settings.brightness, 20);
    expect(first.croppedPath, '/docs/cropped_0.jpg');
    expect(first.rawWidth, 4000);
    expect(first.quad.tl.x, 0.1);

    final legacy = cubit.state.pages[1];
    expect(legacy.rawPath, '/docs/page_1.jpg'); // old pages use the finished image as the source
    expect(legacy.settings.filter, ScanFilter.original);

    cubit.removePage(1);
    final doc = await cubit.save();
    expect(doc, isNotNull);
    expect(docs.updatedId, 'doc-9');
    expect(docs.savedPages!.length, 1);
    expect(docs.savedPages!.single.edit!.filter, 'grayscale');
    expect(docs.savedFolder, isNull); // no new document was created
  });

  test('save renders pages, files into the target folder and resets the session', () async {
    await cubit.commitAllFor(['/a.jpg', '/b.jpg']);
    cubit.setTitle('Invoices');
    final doc = await cubit.save();
    expect(doc, isNotNull);
    expect(docs.savedTitle, 'Invoices');
    expect(docs.savedFolder, 'f1');
    expect(docs.savedPages!.length, 2);
    expect(cubit.state.pages, isEmpty);
  });
}

extension on ScanSessionCubit {
  Future<void> commitAllFor(List<String> paths) async {
    await importMany(paths);
    await commitAll();
  }
}

void importTests() {
  group('importing PDF/Word files', () {
    test('adds every converted page without a crop step and uses the file name', () async {
      final scanner = _FakeScanner();
      final cubit = _cubit(scanner, _FakeDocs())..start(defaultFilter: ScanFilter.magicColor);
      expect(await cubit.importDocumentFile(ImportKind.pdf, '/contract.pdf'), isTrue);
      expect(cubit.state.pages.length, 2);
      expect(cubit.state.title, 'Contract');
      expect(cubit.state.draft, isNull);
      expect(cubit.state.pages.every((p) => p.croppedPath != null && p.settings.filter == ScanFilter.original), isTrue);
      await cubit.close();
    });

    test('importing more files into an open session appends pages and keeps the title', () async {
      final cubit = _cubit(_FakeScanner(), _FakeDocs())..start(defaultFilter: ScanFilter.magicColor);
      await cubit.beginDraft('/photo.jpg');
      await cubit.commitDraft();
      cubit.setTitle('My bundle');

      expect(await cubit.importDocumentFile(ImportKind.pdf, '/a.pdf'), isTrue);
      expect(await cubit.importDocumentFile(ImportKind.docx, '/b.docx'), isTrue);

      expect(cubit.state.pages.length, 5); // 1 photo + 2 + 2
      expect(cubit.state.title, 'My bundle');
      expect(cubit.state.selected, 3); // first page of the last import
      await cubit.close();
    });

    test('a failed import reports the error and adds nothing', () async {
      final importer = _FakeImporter()..fail = true;
      final cubit = _cubit(_FakeScanner(), _FakeDocs(), importer)..start(defaultFilter: ScanFilter.magicColor);
      expect(await cubit.importDocumentFile(ImportKind.docx, '/x.docx'), isFalse);
      expect(cubit.state.pages, isEmpty);
      expect(cubit.state.error, isA<ImportFailure>());
      expect(cubit.state.busy, isFalse);
      await cubit.close();
    });
  });
}

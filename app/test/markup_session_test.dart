import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/markup/domain/markup.dart';
import 'package:doculoom/features/markup/domain/markup_renderer.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/scanner/domain/entities/prepared_image.dart';
import 'package:doculoom/features/scanner/domain/entities/quad.dart';
import 'package:doculoom/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:doculoom/features/scanner/domain/usecases/scanner_usecases.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';

class _Scanner implements ScannerRepository {
  var n = 0;
  var filtered = 0;
  String _next() => '/tmp/fake_${n++}.jpg';

  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) async =>
      Ok(PreparedImage(path: _next(), width: 100, height: 200, detectedQuad: Quad.defaultInset));

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
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) async {
    filtered++;
    return Ok(ImageFileInfo(path: _next(), width: 80, height: 160));
  }
}

class _Docs implements DocumentRepository {
  List<NewPage>? saved;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<Result<ScannedDocument>> saveDocument({required String title, required List<NewPage> pages, String? folderId}) async {
    saved = pages;
    return Ok(ScannedDocument(id: 'd1', title: title, createdAt: DateTime(2026), updatedAt: DateTime(2026), pages: const []));
  }
}

class _Importer implements DocumentImporter {
  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) async =>
      const Ok(ImportedDocument(title: 't', imagePaths: []));
}

class _Renderer implements MarkupRenderer {
  Failure? failure;
  var calls = 0;
  String? lastImage;
  FilterSettings? lastSettings;
  List<MarkupItem> lastItems = const [];

  @override
  Future<Result<ImageFileInfo>> render({required String imagePath, required FilterSettings settings, required List<MarkupItem> items}) async {
    calls++;
    lastImage = imagePath;
    lastSettings = settings;
    lastItems = items;
    if (failure != null) return Err(failure!);
    return Ok(ImageFileInfo(path: '/tmp/marked_$calls.jpg', width: 80, height: 160));
  }
}

const _items = [MarkupSticker(id: 1, text: '✅', center: Offset(0.5, 0.5), size: 0.1)];

void main() {
  late _Scanner scanner;
  late _Docs docs;
  late _Renderer renderer;
  late ScanSessionCubit cubit;

  setUp(() async {
    scanner = _Scanner();
    docs = _Docs();
    renderer = _Renderer();
    cubit = ScanSessionCubit(
      prepareImage: PrepareImage(scanner),
      inspectImage: InspectImage(scanner),
      cropDocument: CropDocument(scanner),
      rotateImage: RotateImage(scanner),
      previewFilter: PreviewFilter(scanner),
      previewFilterBatch: PreviewFilterBatch(scanner),
      applyFilter: ApplyFilter(scanner),
      saveDocument: SaveDocument(docs),
      updateDocument: UpdateDocument(docs),
      importDocumentFile: ImportDocumentFile(_Importer()),
      markupRenderer: renderer,
    )..start(defaultFilter: ScanFilter.original);
    await cubit.beginDraft('/a.jpg');
    await cubit.commitDraft();
  });

  tearDown(() => cubit.close());

  test('marks become part of the page picture and the colour filter is baked in', () async {
    cubit.updateSettings(const FilterSettings(filter: ScanFilter.documentBw, brightness: 10), immediate: true);
    final before = cubit.state.pages.first;
    expect(await cubit.applyMarkup(0, _items), isTrue);
    final page = cubit.state.pages.first;
    expect(renderer.lastImage, before.croppedPath);
    expect(renderer.lastSettings!.filter, ScanFilter.documentBw, reason: 'drawn on top of the filtered page');
    expect(renderer.lastItems, _items);
    expect(page.croppedPath, '/tmp/marked_1.jpg');
    expect((page.croppedWidth, page.croppedHeight), (80, 160));
    expect(page.settings, const FilterSettings(), reason: 'the filter is already in the picture');
    expect(page.preMarkup!.croppedPath, before.croppedPath);
    expect(page.preMarkup!.settings.filter, ScanFilter.documentBw);
    expect(cubit.state.busy, isFalse);
  });

  test('marks can be taken off again, bringing back the earlier picture and filter', () async {
    cubit.updateSettings(const FilterSettings(filter: ScanFilter.grayscale), immediate: true);
    final before = cubit.state.pages.first;
    await cubit.applyMarkup(0, _items);
    await cubit.removeMarkup(0);
    final page = cubit.state.pages.first;
    expect(page.croppedPath, before.croppedPath);
    expect(page.settings.filter, ScanFilter.grayscale);
    expect(page.preMarkup, isNull);
  });

  test('marking twice still goes back to the picture before any marks', () async {
    final before = cubit.state.pages.first;
    await cubit.applyMarkup(0, _items);
    await cubit.applyMarkup(0, _items);
    expect(cubit.state.pages.first.croppedPath, '/tmp/marked_2.jpg');
    await cubit.removeMarkup(0);
    expect(cubit.state.pages.first.croppedPath, before.croppedPath);
  });

  test('nothing to draw means nothing happens', () async {
    expect(await cubit.applyMarkup(0, const []), isFalse);
    expect(renderer.calls, 0);
    expect(await cubit.applyMarkup(5, _items), isFalse);
  });

  test('a failure is reported and the page is left as it was', () async {
    renderer.failure = const ImageProcessingFailure('The markup could not be added to this page.');
    final before = cubit.state.pages.first;
    expect(await cubit.applyMarkup(0, _items), isFalse);
    expect(cubit.state.error!.message, contains('markup could not be added'));
    expect(cubit.state.pages.first.croppedPath, before.croppedPath);
    expect(cubit.state.pages.first.preMarkup, isNull);
    expect(cubit.state.busy, isFalse);
  });

  test('turning the page keeps the marks in the picture and drops the way back', () async {
    await cubit.applyMarkup(0, _items);
    await cubit.rotatePage(0);
    expect(cubit.state.pages.first.preMarkup, isNull);
  });

  test('cropping again starts from the original photo and drops the marks', () async {
    await cubit.applyMarkup(0, _items);
    cubit.editPageCrop(0);
    await cubit.commitDraft();
    expect(cubit.state.pages.first.preMarkup, isNull);
    expect(cubit.state.pages.first.croppedPath, isNot('/tmp/marked_1.jpg'));
  });

  test('saving keeps the marked picture as it is and remembers it as the page', () async {
    await cubit.applyMarkup(0, _items);
    final filteredBefore = scanner.filtered;
    final doc = await cubit.save();
    expect(doc, isNotNull);
    final page = docs.saved!.single;
    expect(page.imagePath, '/tmp/marked_1.jpg');
    expect(scanner.filtered, filteredBefore, reason: 'no second filter pass over the marks');
    expect(page.edit!.croppedPath, '/tmp/marked_1.jpg');
    expect(page.edit!.filter, ScanFilter.original.name);
  });

  test('a session without a renderer ignores markup', () async {
    final plain = ScanSessionCubit(
      prepareImage: PrepareImage(scanner),
      inspectImage: InspectImage(scanner),
      cropDocument: CropDocument(scanner),
      rotateImage: RotateImage(scanner),
      previewFilter: PreviewFilter(scanner),
      previewFilterBatch: PreviewFilterBatch(scanner),
      applyFilter: ApplyFilter(scanner),
      saveDocument: SaveDocument(docs),
      updateDocument: UpdateDocument(docs),
      importDocumentFile: ImportDocumentFile(_Importer()),
    )..start(defaultFilter: ScanFilter.original);
    await plain.beginDraft('/a.jpg');
    await plain.commitDraft();
    expect(await plain.applyMarkup(0, _items), isFalse);
    await plain.close();
  });
}

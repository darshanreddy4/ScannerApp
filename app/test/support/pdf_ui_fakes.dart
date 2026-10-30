import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_picture_pages.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_forms.dart';
import 'package:doculoom/features/pdf_tools/domain/pdf_redact.dart';
import 'package:doculoom/features/text_edit/pdf/pdf_page_renderer.dart';

Uint8List samplePage({int w = 60, int h = 80, bool png = false}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(250, 250, 250));
  return Uint8List.fromList(png ? img.encodePng(image) : img.encodeJpg(image));
}

class FakeRenderer implements PdfPageRenderer {
  FakeRenderer(this.pageCount);
  @override
  final int pageCount;
  var disposed = false;

  @override
  Future<Uint8List> render(int page, {required int width}) async => samplePage();

  @override
  Future<void> dispose() async => disposed = true;
}

class FakePicturePages implements PdfPicturePages {
  FakePicturePages(this.count, {this.failOpen = false});
  final int count;
  final bool failOpen;
  final rendered = <({int page, int width, bool png})>[];
  var closed = false;

  @override
  Future<int> open(String path) async {
    if (failOpen) throw StateError('cannot open');
    return count;
  }

  @override
  Future<Uint8List> render(int page, {required int width, required bool png}) async {
    rendered.add((page: page, width: width, png: png));
    return samplePage(png: png);
  }

  @override
  Future<void> close() async => closed = true;
}

class FakeShare implements ShareService {
  final shared = <({List<String> paths, String mime})>[];

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async {
    shared.add((paths: paths, mime: mimeType));
    return const Ok(null);
  }

  final single = <({String path, String mime, String? subject})>[];

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    single.add((path: path, mime: mimeType, subject: subject));
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeSave implements SaveService {
  final gallery = <List<String>>[];
  final files = <String>[];

  @override
  Future<Result<int>> saveImagesToGallery(List<String> paths) async {
    gallery.add(paths);
    return Ok(paths.length);
  }

  @override
  Future<Result<bool>> saveToFiles({required String sourcePath, required String fileName, required String mimeType}) async {
    files.add(fileName);
    return const Ok(true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeFormService implements PdfFormService {
  FakeFormService(this.info);
  PdfFormInfo info;
  Failure? inspectFailure;
  Failure? saveFailure;
  final plans = <PdfFormPlan>[];

  @override
  Future<Result<PdfFormInfo>> inspect(String path) async => inspectFailure != null ? Err(inspectFailure!) : Ok(info);

  @override
  Future<Result<FilledPdf>> save({required String sourcePath, required String outputPath, required PdfFormPlan plan}) async {
    plans.add(plan);
    if (saveFailure != null) return Err(saveFailure!);
    return Ok(FilledPdf(path: outputPath, bytes: 1234));
  }
}

class FakeToolsService implements PdfPageToolsService {
  Failure? failure;
  ExtractionResult extraction = const ExtractionResult(images: [], skipped: 0);
  final crops = <Map<int, CropInsets>>[];
  final extractions = <String>[];

  @override
  Future<Result<FilledPdf>> crop({required String sourcePath, required String outputPath, required Map<int, CropInsets> insets}) async {
    crops.add(insets);
    return failure != null ? Err(failure!) : Ok(FilledPdf(path: outputPath, bytes: 999));
  }

  @override
  Future<Result<ExtractionResult>> extractImages({required String sourcePath, required String outputDir}) async {
    extractions.add(outputDir);
    return failure != null ? Err(failure!) : Ok(extraction);
  }
}

class FakeRedactService implements PdfRedactService {
  Failure? failure;
  final calls = <({List<RedactBox> boxes, bool high})>[];

  @override
  Future<Result<FilledPdf>> redact({required String sourcePath, required String outputPath, required List<RedactBox> boxes, bool highDetail = false}) async {
    calls.add((boxes: boxes, high: highDetail));
    return failure != null ? Err(failure!) : Ok(FilledPdf(path: outputPath, bytes: 777));
  }
}

Directory tempDir() => Directory.systemTemp.createTempSync('sv_pdf_ui');

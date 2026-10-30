import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/pdf_forms.dart';
import 'forms/pdf_forms_engine.dart';
import 'pdf_page_tools.dart';
import 'security/pdf_model.dart';
import 'security/pdf_security.dart';

const _maxBytes = 150 * 1024 * 1024;

Future<Uint8List> _read(String path) async {
  final file = File(path);
  if (!await file.exists()) throw const ExportFailure('The file could not be found.');
  if (await file.length() > _maxBytes) throw const ExportFailure('This PDF is larger than 150 MB. Compress it first.');
  return file.readAsBytes();
}

/// Errors cross the isolate boundary as plain text so they arrive intact.
typedef _Outcome<T> = ({T? value, String? message});

_Outcome<T> _run<T>(T Function() body) {
  try {
    return (value: body(), message: null);
  } on PdfFormException catch (e) {
    return (value: null, message: e.message);
  } on WrongPasswordException {
    return (value: null, message: 'This PDF is protected with a password. Unlock it first with Tools > Lock or unlock PDF.');
  } on UnsupportedProtectionException catch (e) {
    return (value: null, message: e.message);
  } on PdfFormatException {
    return (value: null, message: 'This file is not a readable PDF. It may be damaged.');
  } on FormatException {
    return (value: null, message: 'This file is not a readable PDF. It may be damaged.');
  }
}

Future<T> _inBackground<T>(T Function() body) async {
  final r = await Isolate.run(() => _run(body));
  final message = r.message;
  if (message != null) throw ExportFailure(message);
  return r.value as T;
}

Failure _unexpected(Object e) => e is Failure ? e : ExportFailure('The PDF could not be processed.', cause: e);

class PdfFormProcessor implements PdfFormService {
  const PdfFormProcessor();

  @override
  Future<Result<PdfFormInfo>> inspect(String path) => guard(() async {
    final bytes = await _read(path);
    return _inBackground(() => readPdfForm(bytes));
  }, onError: _unexpected);

  @override
  Future<Result<FilledPdf>> save({required String sourcePath, required String outputPath, required PdfFormPlan plan}) => guard(() async {
    final bytes = await _read(sourcePath);
    final out = await _inBackground(() => applyPdfFormPlan(bytes, plan));
    await File(outputPath).writeAsBytes(out, flush: true);
    return FilledPdf(path: outputPath, bytes: out.length);
  }, onError: _unexpected);
}

class PdfPageToolsProcessor implements PdfPageToolsService {
  const PdfPageToolsProcessor();

  @override
  Future<Result<FilledPdf>> crop({required String sourcePath, required String outputPath, required Map<int, CropInsets> insets}) => guard(() async {
    final bytes = await _read(sourcePath);
    final out = await _inBackground(() => cropPdfPages(bytes, insets));
    await File(outputPath).writeAsBytes(out, flush: true);
    return FilledPdf(path: outputPath, bytes: out.length);
  }, onError: _unexpected);

  @override
  Future<Result<ExtractionResult>> extractImages({required String sourcePath, required String outputDir}) => guard(() async {
    final bytes = await _read(sourcePath);
    final found = await _inBackground(() => extractPdfPictures(bytes));
    final dir = await Directory(outputDir).create(recursive: true);
    final base = p.basenameWithoutExtension(sourcePath);
    final images = <ExtractedImage>[];
    for (var i = 0; i < found.pictures.length; i++) {
      final pic = found.pictures[i];
      final path = p.join(dir.path, '${base}_picture_${(i + 1).toString().padLeft(2, '0')}.${pic.extension}');
      await File(path).writeAsBytes(pic.bytes, flush: true);
      images.add(ExtractedImage(path: path, page: pic.page, width: pic.width, height: pic.height, bytes: pic.bytes.length));
    }
    return ExtractionResult(images: images, skipped: found.skipped);
  }, onError: _unexpected);
}

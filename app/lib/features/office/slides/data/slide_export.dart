import 'dart:io';
import '../../../../core/utils/region.dart';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../core/error/failures.dart';
import '../../../export/data/document_builders.dart';
import '../../../export/domain/entities/export_options.dart';
import '../../../importer/domain/importer.dart';
import '../../convert/office_converter.dart';
import 'deck_editor.dart';
import 'pptx_package.dart';
import 'pptx_template.dart';
import 'pptx_writer.dart';
import 'slide_painter.dart';

/// Draws slides to pictures and builds the files made from them.
class SlideExporter {
  SlideExporter(this.deck) : editor = DeckEditor(deck);

  final PptxDeck deck;
  final DeckEditor editor;
  final Map<String, ui.Image> _images = {};

  void dispose() {
    for (final i in _images.values) {
      i.dispose();
    }
    _images.clear();
  }

  /// One slide as JPEG bytes, [width] pixels wide.
  Future<Uint8List> renderJpeg(int index, {int width = 1600, int quality = 88}) async {
    final slide = deck.slides[index];
    final view = editor.view(slide);
    await loadSlideImages(mediaOf(view), deck.files, _images);
    final image = await renderSlideImage(view, _images, deck.width, deck.height, width);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = image.width, h = image.height;
    image.dispose();
    if (data == null) throw const ImageProcessingFailure('A slide could not be drawn.');
    final rgba = TransferableTypedData.fromList([data.buffer.asUint8List()]);
    return Isolate.run(() {
      final raw = rgba.materialize().asUint8List();
      final rgb = img.Image.fromBytes(width: w, height: h, bytes: raw.buffer, numChannels: 4).convert(numChannels: 3);
      return Uint8List.fromList(img.encodeJpg(rgb, quality: quality));
    });
  }

  /// Every slide as a JPEG file in [dir].
  Future<List<File>> renderFiles(Directory dir, String baseName, {int width = 1600, void Function(int done, int total)? onProgress}) async {
    await dir.create(recursive: true);
    final files = <File>[];
    final digits = '${deck.slides.length}'.length;
    for (var i = 0; i < deck.slides.length; i++) {
      final bytes = await renderJpeg(i, width: width);
      final f = File(p.join(dir.path, '${baseName}_slide_${'${i + 1}'.padLeft(digits, '0')}.jpg'));
      await f.writeAsBytes(bytes, flush: true);
      files.add(f);
      onProgress?.call(i + 1, deck.slides.length);
    }
    return files;
  }

  /// Every slide as a page of one PDF.
  Future<void> exportPdf(String outputPath, Directory workDir, {void Function(int done, int total)? onProgress}) async {
    final files = await renderFiles(Directory(p.join(workDir.path, 'slides_${DateTime.now().microsecondsSinceEpoch}')), 'page', onProgress: onProgress);
    try {
      final pages = <PageSource>[];
      for (final f in files) {
        final size = imageInfo(await f.readAsBytes());
        pages.add(PageSource(path: f.path, width: size?.width ?? 1600, height: size?.height ?? 900));
      }
      await buildPdf(pages, ExportQuality.high, outputPath, letter: Region.letter);
    } finally {
      for (final f in files) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }
}

/// A new presentation with one picture per slide, each fitted on its slide.
Future<Uint8List> buildPictureDeck(List<String> imagePaths, {void Function(int done, int total)? onProgress}) async {
  final infos = <({Uint8List bytes, int width, int height, String ext})>[];
  for (final path in imagePaths) {
    final bytes = await File(path).readAsBytes();
    final info = imageInfo(bytes);
    if (info == null) throw const ImportFailure('Only JPG and PNG pictures can be put on slides.');
    infos.add((bytes: bytes, width: info.width, height: info.height, ext: info.ext));
  }
  final landscape = infos.first.width >= infos.first.height;
  final deck = PptxDeck.fromFiles(newPresentationFiles(widthEmu: landscape ? 12192000 : 6858000, heightEmu: landscape ? 6858000 : 9144000));
  final editor = DeckEditor(deck);
  for (var i = 0; i < infos.length; i++) {
    final slide = editor.addSlide(blank: true);
    final inf = infos[i];
    editor.addPicture(slide, inf.bytes, inf.ext, inf.width, inf.height, areaW: deck.width * 0.96, areaH: deck.height * 0.96);
    onProgress?.call(i + 1, infos.length);
  }
  editor.deleteSlide(0);
  return writePptx(deck);
}

/// The slide conversions of the Office tools.
class SlideConverter {
  SlideConverter({required this.importer});

  final DocumentImporter importer;

  Future<List<ConvertedFile>> convert(OfficeConversion kind, List<String> inputs, Directory out, void Function(String) progress) async {
    switch (kind) {
      case OfficeConversion.pptxToPdf:
        final deck = await _open(inputs.first);
        final exporter = SlideExporter(deck);
        try {
          final target = p.join(out.path, '${p.basenameWithoutExtension(inputs.first)}.pdf');
          await exporter.exportPdf(target, out, onProgress: (d, t) => progress('Drawing slide $d of $t'));
          return [ConvertedFile(path: target, name: p.basename(target), mimeType: 'application/pdf')];
        } finally {
          exporter.dispose();
        }
      case OfficeConversion.pptxToImages:
        final deck = await _open(inputs.first);
        final exporter = SlideExporter(deck);
        try {
          final files = await exporter.renderFiles(out, p.basenameWithoutExtension(inputs.first), onProgress: (d, t) => progress('Drawing slide $d of $t'));
          return [for (final f in files) ConvertedFile(path: f.path, name: p.basename(f.path), mimeType: 'image/jpeg')];
        } finally {
          exporter.dispose();
        }
      case OfficeConversion.imagesToPptx:
        final bytes = await buildPictureDeck(inputs, onProgress: (d, t) => progress('Placing picture $d of $t'));
        final name = inputs.length == 1 ? '${p.basenameWithoutExtension(inputs.first)}.pptx' : 'Pictures.pptx';
        final path = p.join(out.path, name);
        await File(path).writeAsBytes(bytes, flush: true);
        return [ConvertedFile(path: path, name: name, mimeType: _pptxMime, openAs: 'slides')];
      case OfficeConversion.pdfToPptx:
        progress('Reading the PDF');
        final result = await importer.import(kind: ImportKind.pdf, path: inputs.first, onProgress: (d, t) => progress('Reading page $d of $t'));
        final failure = result.failureOrNull;
        if (failure != null) throw failure;
        final doc = result.valueOrNull!;
        final bytes = await buildPictureDeck(doc.imagePaths, onProgress: (d, t) => progress('Placing page $d of $t'));
        final name = '${p.basenameWithoutExtension(inputs.first)}.pptx';
        final path = p.join(out.path, name);
        await File(path).writeAsBytes(bytes, flush: true);
        return [ConvertedFile(path: path, name: name, mimeType: _pptxMime, openAs: 'slides')];
      default:
        throw const ExportFailure('This conversion is not available.');
    }
  }

  Future<PptxDeck> _open(String path) async {
    try {
      return await PptxDeck.open(await File(path).readAsBytes());
    } on PptxFormatException catch (e) {
      throw ImportFailure(e.message);
    }
  }
}

const _pptxMime = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';

import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/passport_maker.dart';
import '../domain/photo_compressor.dart';
import '../domain/photo_specs.dart';
import '../domain/sheet_layout.dart';
import 'background_cleaner.dart';

class PassportProcessor implements PassportMaker {
  const PassportProcessor();

  static const workingSide = 3000;

  @override
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false}) => guard(
    () => Isolate.run(() => prepareSync(sourcePath, outputPath, rotateRight)),
    onError: (e) => ExportFailure('This photo could not be opened. It may be damaged or in an unsupported format.', cause: e),
  );

  @override
  Future<Result<RenderedPhoto>> render(RenderRequest request) =>
      guard(() => Isolate.run(() => renderSync(request)), onError: (e) => ExportFailure('The photo could not be created.', cause: e));

  @override
  Future<Result<SheetFiles>> sheet({required String photoPath, required PhotoSpec spec, required SheetPaper paper, int? copies, required String outputBase}) =>
      guard(
        () => Isolate.run(
          () => buildSheet(photoPath: photoPath, widthMm: spec.widthMm, heightMm: spec.heightMm, paper: paper, copies: copies, outputBase: outputBase),
        ),
        onError: (e) => ExportFailure('The print sheet could not be created.', cause: e),
      );
}

WorkingPhoto prepareSync(String sourcePath, String outputPath, bool rotateRight) {
  var image = img.decodeImage(File(sourcePath).readAsBytesSync());
  if (image == null) throw const FormatException('Unsupported or damaged image');
  image = img.bakeOrientation(image);
  if (rotateRight) image = img.copyRotate(image, angle: 90);
  if (math.max(image.width, image.height) > PassportProcessor.workingSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: PassportProcessor.workingSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: PassportProcessor.workingSide, interpolation: img.Interpolation.average);
  }
  if (image.hasAlpha) {
    final flat = img.Image(width: image.width, height: image.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, image);
    image = flat;
  }
  File(outputPath).writeAsBytesSync(img.encodeJpg(image, quality: 92), flush: true);
  return WorkingPhoto(path: outputPath, width: image.width, height: image.height);
}

RenderedPhoto renderSync(RenderRequest r) {
  final source = img.decodeImage(File(r.sourcePath).readAsBytesSync());
  if (source == null) throw const FormatException('Unsupported or damaged image');

  final x = r.left.round().clamp(0, source.width - 1);
  final y = r.top.round().clamp(0, source.height - 1);
  final w = r.width.round().clamp(1, source.width - x);
  final h = r.height.round().clamp(1, source.height - y);
  var out = img.copyCrop(source, x: x, y: y, width: w, height: h);
  out = img.copyResize(out, width: r.outWidth, height: r.outHeight, interpolation: img.Interpolation.cubic);

  final background = r.backgroundArgb;
  if (background != null) out = cleanBackground(out, backgroundArgb: background, strength: r.cleanStrength);

  final bytes = r.format == PhotoFormat.png ? img.encodePng(out) : img.encodeJpg(out, quality: 95);
  File(r.outputPath).writeAsBytesSync(bytes, flush: true);
  return RenderedPhoto(path: r.outputPath, bytes: bytes.length, width: out.width, height: out.height);
}

Future<SheetFiles> buildSheet({
  required String photoPath,
  required double widthMm,
  required double heightMm,
  required SheetPaper paper,
  int? copies,
  required String outputBase,
}) async {
  final layout = SheetLayout.fit(paperWidthMm: paper.widthMm, paperHeightMm: paper.heightMm, photoWidthMm: widthMm, photoHeightMm: heightMm, copies: copies);
  if (layout.slots.isEmpty) throw const FormatException('The photo is bigger than the paper');

  const dpi = 300;
  int px(double mm) => (mm / 25.4 * dpi).round();
  final photoBytes = File(photoPath).readAsBytesSync();
  final photo = img.decodeImage(photoBytes);
  if (photo == null) throw const FormatException('Unsupported or damaged image');

  // JPG sheet at 300 dpi.
  final canvas = img.Image(width: px(layout.paperWidthMm), height: px(layout.paperHeightMm), numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  final sized = img.copyResize(photo, width: px(widthMm), height: px(heightMm), interpolation: img.Interpolation.cubic);
  final guide = img.ColorRgb8(190, 190, 190);
  for (final s in layout.slots) {
    final left = px(s.xMm), top = px(s.yMm);
    img.compositeImage(canvas, sized, dstX: left, dstY: top);
    img.drawRect(canvas, x1: left - 1, y1: top - 1, x2: left + sized.width, y2: top + sized.height, color: guide);
  }
  final jpgPath = '$outputBase.jpg';
  File(jpgPath).writeAsBytesSync(img.encodeJpg(canvas, quality: 95), flush: true);

  // PDF at the exact paper size, so a print shop or printer needs no scaling.
  double pt(double mm) => mm / 25.4 * 72;
  final doc = pw.Document();
  final image = pw.MemoryImage(photoBytes);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(pt(layout.paperWidthMm), pt(layout.paperHeightMm)),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          for (final s in layout.slots)
            pw.Positioned(
              left: pt(s.xMm),
              top: pt(s.yMm),
              child: pw.Container(
                width: pt(widthMm),
                height: pt(heightMm),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: const PdfColor(0.75, 0.75, 0.75), width: 0.3)),
                child: pw.Image(image, width: pt(widthMm), height: pt(heightMm), fit: pw.BoxFit.fill),
              ),
            ),
        ],
      ),
    ),
  );
  final pdfPath = '$outputBase.pdf';
  File(pdfPath).writeAsBytesSync(await doc.save(), flush: true);
  return SheetFiles(jpgPath: jpgPath, pdfPath: pdfPath, copies: layout.slots.length, columns: layout.columns, rows: layout.rows);
}

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../photo_tools/data/passport_processor.dart' show prepareSync;
import '../../photo_tools/domain/passport_maker.dart';
import '../domain/id_card.dart';

class IdCardProcessor implements IdCardMaker {
  const IdCardProcessor();

  static const dpi = 300;

  @override
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false}) => guard(
    () => Isolate.run(() => prepareSync(sourcePath, outputPath, rotateRight)),
    onError: (e) => ExportFailure('This photo could not be opened. It may be damaged or in an unsupported format.', cause: e),
  );

  @override
  Future<Result<CardSheetFiles>> sheet({required List<CardCrop> sides, required IdCardOptions options, required String outputBase}) => guard(() async {
    if (sides.isEmpty) throw const ExportFailure('Add the front of the card first.');
    return Isolate.run(() => buildCardSheet(sides, options, outputBase));
  }, onError: (e) => e is Failure ? e : ExportFailure('The page could not be created. A photo may be damaged.', cause: e));
}

/// Draws the cards on a sheet of paper. Runs in a background isolate.
Future<CardSheetFiles> buildCardSheet(List<CardCrop> sides, IdCardOptions options, String outputBase) async {
  const dpi = IdCardProcessor.dpi;
  int px(double mm) => (mm / 25.4 * dpi).round();
  double pt(double mm) => mm / 25.4 * 72;

  final layout = CardLayout.place(paper: options.paper, size: options.size, count: sides.length, scale: options.scale);
  final canvas = img.Image(width: px(layout.paperWidthMm), height: px(layout.paperHeightMm), numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  final cards = <Uint8List>[];

  for (var i = 0; i < sides.length; i++) {
    final side = sides[i];
    final slot = layout.slots[i];
    final source = img.decodeImage(File(side.path).readAsBytesSync());
    if (source == null) throw const FormatException('Unsupported or damaged image');
    final x = side.left.round().clamp(0, source.width - 1);
    final y = side.top.round().clamp(0, source.height - 1);
    final w = side.width.round().clamp(1, source.width - x);
    final h = side.height.round().clamp(1, source.height - y);
    var card = img.copyCrop(source, x: x, y: y, width: w, height: h);
    card = img.copyResize(card, width: px(slot.widthMm), height: px(slot.heightMm), interpolation: img.Interpolation.cubic);
    if (options.blackAndWhite) card = img.grayscale(card);
    if (card.numChannels != 3) {
      final flat = img.Image(width: card.width, height: card.height, numChannels: 3);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, card);
      card = flat;
    }
    cards.add(Uint8List.fromList(img.encodeJpg(card, quality: 93)));
    img.compositeImage(canvas, card, dstX: px(slot.xMm), dstY: px(slot.yMm));
    if (options.border) {
      final left = px(slot.xMm), top = px(slot.yMm);
      img.drawRect(canvas, x1: left - 1, y1: top - 1, x2: left + card.width, y2: top + card.height, color: img.ColorRgb8(150, 150, 150));
    }
  }

  final jpgPath = '$outputBase.jpg';
  File(jpgPath).writeAsBytesSync(img.encodeJpg(canvas, quality: 92), flush: true);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(pt(layout.paperWidthMm), pt(layout.paperHeightMm)),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Stack(
        children: [
          for (var i = 0; i < cards.length; i++)
            pw.Positioned(
              left: pt(layout.slots[i].xMm),
              top: pt(layout.slots[i].yMm),
              child: pw.Container(
                width: pt(layout.slots[i].widthMm),
                height: pt(layout.slots[i].heightMm),
                decoration: options.border ? pw.BoxDecoration(border: pw.Border.all(color: const PdfColor(0.6, 0.6, 0.6), width: 0.3)) : null,
                child: pw.Image(pw.MemoryImage(cards[i]), fit: pw.BoxFit.fill),
              ),
            ),
        ],
      ),
    ),
  );
  final pdfPath = '$outputBase.pdf';
  File(pdfPath).writeAsBytesSync(await doc.save(), flush: true);
  return CardSheetFiles(jpgPath: jpgPath, pdfPath: pdfPath, cards: cards.length, scale: layout.scale, shrunk: layout.shrunk);
}

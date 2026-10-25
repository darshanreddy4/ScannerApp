import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../../export/data/document_builders.dart';
import '../domain/print_options.dart';
import '../domain/print_service.dart';
import 'print_pdf_builder.dart';

class PrintServiceImpl implements PrintService {
  @override
  Future<Result<Uint8List>> buildPdf({required ScannedDocument document, required PrintOptions options, bool preview = false}) => guard(() async {
    if (document.pages.isEmpty) throw const ExportFailure('This document has no pages to print.');
    final sources = [for (final p in document.pages) PageSource(path: p.imagePath, width: p.width, height: p.height)];
    final maxSide = preview ? 1400 : 3508;
    try {
      return await Isolate.run(() => buildPrintPdf(pages: sources, options: options, maxSide: maxSide));
    } on PrintOptionsException catch (e) {
      throw ExportFailure(e.message);
    }
  }, onError: (e) => ExportFailure('The print file could not be prepared. Try fewer pages or a lower quality.', cause: e));

  @override
  Future<Result<bool>> print({required Uint8List pdf, required String jobName, required PrintOptions options}) => guard(() {
    return Printing.layoutPdf(
      onLayout: (_) async => pdf,
      name: jobName,
      format: PdfPageFormat(options.paper.widthMm * PdfPageFormat.mm, options.paper.heightMm * PdfPageFormat.mm),
      dynamicLayout: false,
    );
  }, onError: (e) => ExportFailure('Printing is not available on this device.', cause: e));
}

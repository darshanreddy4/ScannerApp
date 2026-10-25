import 'dart:typed_data';

import '../../../core/error/result.dart';
import '../../documents/domain/entities/scanned_document.dart';
import 'print_options.dart';

abstract interface class PrintService {
  /// Builds the print-ready PDF. [preview] renders at lower resolution for the on-screen preview.
  Future<Result<Uint8List>> buildPdf({required ScannedDocument document, required PrintOptions options, bool preview = false});

  /// Opens the system print sheet (printer, copies, two-sided, tray...) with [pdf]. True when sent to a printer.
  Future<Result<bool>> print({required Uint8List pdf, required String jobName, required PrintOptions options});
}

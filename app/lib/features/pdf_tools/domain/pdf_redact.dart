import 'package:equatable/equatable.dart';

import '../../../core/error/result.dart';
import 'pdf_forms.dart' show FilledPdf;

/// An area to cover, as shares of the page (0 to 1) measured from the top left.
class RedactBox extends Equatable {
  const RedactBox({required this.page, required this.left, required this.top, required this.right, required this.bottom});
  final int page;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  @override
  List<Object?> get props => [page, left, top, right, bottom];
}

abstract interface class PdfRedactService {
  /// Writes a new PDF in which every page is a picture and the [boxes] are painted solid black before the file is made,
  /// so what was under them is not in the file at all.
  Future<Result<FilledPdf>> redact({required String sourcePath, required String outputPath, required List<RedactBox> boxes, bool highDetail = false});
}

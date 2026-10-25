import '../../../core/error/result.dart';
import 'photo_compressor.dart';
import 'photo_specs.dart';

/// A copy of the picked photo with its rotation applied and a sensible size, so the screen and the crop agree.
class WorkingPhoto {
  const WorkingPhoto({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;
}

class RenderedPhoto {
  const RenderedPhoto({required this.path, required this.bytes, required this.width, required this.height});
  final String path;
  final int bytes;
  final int width;
  final int height;
}

class SheetFiles {
  const SheetFiles({required this.jpgPath, required this.pdfPath, required this.copies, required this.columns, required this.rows});
  final String jpgPath;
  final String pdfPath;
  final int copies;
  final int columns;
  final int rows;
}

class RenderRequest {
  const RenderRequest({
    required this.sourcePath,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.outWidth,
    required this.outHeight,
    required this.outputPath,
    this.backgroundArgb,
    this.cleanStrength = 50,
    this.format = PhotoFormat.jpg,
  });

  final String sourcePath;

  /// The part of the working photo to keep, in its pixels.
  final double left;
  final double top;
  final double width;
  final double height;
  final int outWidth;
  final int outHeight;
  final String outputPath;

  /// When set, the plain background around the person is replaced with this colour.
  final int? backgroundArgb;

  /// 0 to 100: how much of the background colour range is treated as background.
  final int cleanStrength;
  final PhotoFormat format;
}

abstract interface class PassportMaker {
  /// Applies the rotation flag, limits the size and saves a copy that the crop works on.
  Future<Result<WorkingPhoto>> prepare({required String sourcePath, required String outputPath, bool rotateRight = false});

  Future<Result<RenderedPhoto>> render(RenderRequest request);

  /// Repeats the finished photo on a sheet of paper, as a JPG for photo shops and a PDF for printing.
  Future<Result<SheetFiles>> sheet({required String photoPath, required PhotoSpec spec, required SheetPaper paper, int? copies, required String outputBase});
}

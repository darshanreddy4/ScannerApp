import '../../../core/error/result.dart';

/// Colours a signature can be turned into.
enum InkColor {
  black('Black', 0xFF111111),
  blue('Blue', 0xFF1B3FA0),
  darkBlue('Dark blue', 0xFF0B1F5C);

  const InkColor(this.label, this.argb);
  final String label;
  final int argb;
}

/// A line drawn with a finger, in the pad's own units.
class Stroke {
  const Stroke(this.points);
  final List<({double x, double y})> points;
}

/// A transparent PNG of a signature, cut to the ink.
class SignaturePng {
  const SignaturePng({required this.path, required this.width, required this.height});
  final String path;
  final int width;
  final int height;

  double get aspect => width / height;
}

class SavedSignature {
  const SavedSignature({required this.id, required this.path, required this.width, required this.height});
  final String id;
  final String path;
  final int width;
  final int height;

  double get aspect => width / height;
}

abstract interface class SignatureStore {
  static const maxSaved = 5;

  Future<List<SavedSignature>> list();

  /// Keeps a copy of the PNG. Fails when [maxSaved] signatures are already kept.
  Future<Result<SavedSignature>> save(String pngPath);

  Future<void> delete(String id);

  /// Removes every saved signature.
  Future<void> deleteAll();
}

abstract interface class SignatureMaker {
  /// Draws the strokes with round pen tips and cuts the result to the ink.
  /// [padWidth] and [padHeight] are the size of the area the strokes were drawn in.
  Future<Result<SignaturePng>> fromStrokes({
    required List<Stroke> strokes,
    required double padWidth,
    required double padHeight,
    required double penWidth,
    required InkColor ink,
    required String outputPath,
  });

  /// Lifts dark ink off a photo of a signature on white paper. [sensitivity] from 0 (only the darkest ink) to 1 (also faint ink).
  /// A null [ink] keeps the colour of the pen in the photo.
  Future<Result<SignaturePng>> fromPhoto({required String sourcePath, required String outputPath, required double sensitivity, InkColor? ink});
}

/// Where a signature sits on a page, as shares of the page so it fits pages of any size.
class SignPlacement {
  const SignPlacement({this.centerX = 0.72, this.centerY = 0.85, this.width = 0.28});

  /// Middle of the signature as a share of the page width and height (0 to 1).
  final double centerX;
  final double centerY;

  /// Signature width as a share of the page width.
  final double width;

  static const minWidth = 0.08;
  static const maxWidth = 0.8;

  /// Keeps the signature on the page. [aspect] is signature width / height; [pageAspect] is page width / height.
  SignPlacement clamped({required double aspect, required double pageAspect}) {
    final w = width.clamp(minWidth, maxWidth);
    final h = w / aspect * pageAspect;
    final hh = h > 1 ? 1.0 : h;
    return SignPlacement(centerX: centerX.clamp(w / 2, 1 - w / 2), centerY: centerY.clamp(hh / 2, 1 - hh / 2), width: w);
  }

  SignPlacement copyWith({double? centerX, double? centerY, double? width}) =>
      SignPlacement(centerX: centerX ?? this.centerX, centerY: centerY ?? this.centerY, width: width ?? this.width);

  @override
  bool operator ==(Object other) => other is SignPlacement && other.centerX == centerX && other.centerY == centerY && other.width == width;

  @override
  int get hashCode => Object.hash(centerX, centerY, width);
}

enum SignPages {
  thisPage('This page'),
  lastPage('Last page'),
  allPages('Every page');

  const SignPages(this.label);
  final String label;

  /// Zero-based pages that get the signature.
  List<int> resolve({required int current, required int count}) => switch (this) {
    SignPages.thisPage => [current.clamp(0, count - 1)],
    SignPages.lastPage => [count - 1],
    SignPages.allPages => [for (var i = 0; i < count; i++) i],
  };
}

/// A document opened for signing: one picture per page.
class SignDocument {
  const SignDocument({required this.name, required this.pages, required this.sizes, required this.isPdf});
  final String name;
  final List<String> pages;

  /// Pixel size of every page as it is shown (width and height), same order as [pages].
  final List<({int width, int height})> sizes;
  final bool isPdf;

  double aspectOf(int page) => sizes[page].width / sizes[page].height;
}

class SignedFile {
  const SignedFile({required this.path, required this.name, required this.mimeType, required this.pages, required this.signedPages});
  final String path;
  final String name;
  final String mimeType;
  final int pages;
  final int signedPages;
}

abstract interface class DocumentSigner {
  /// Opens a PDF (one picture per page) or a photo.
  Future<Result<SignDocument>> open(String path);

  /// Puts the signature on the chosen pages and saves a PDF (or, for a photo, a JPG).
  Future<Result<SignedFile>> sign({
    required SignDocument document,
    required String signaturePath,
    required SignPlacement placement,
    required List<int> pages,
    required String outputDir,
    void Function(int done, int total)? onProgress,
  });
}

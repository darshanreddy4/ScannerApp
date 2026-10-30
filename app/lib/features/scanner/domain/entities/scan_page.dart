import 'dart:typed_data';

import 'filter_settings.dart';
import 'quad.dart';

/// How a page looked before marks were drawn on it, so the marks can be taken off again.
class PageSnapshot {
  const PageSnapshot({required this.croppedPath, required this.width, required this.height, required this.settings});
  final String croppedPath;
  final int width;
  final int height;
  final FilterSettings settings;
}

/// A page being worked on in the scan session. Heavy renders happen only on save.
class ScanPage {
  const ScanPage({
    required this.id,
    required this.rawPath,
    required this.rawWidth,
    required this.rawHeight,
    required this.quad,
    required this.detectedQuad,
    this.croppedPath,
    this.croppedWidth,
    this.croppedHeight,
    this.settings = const FilterSettings(),
    this.preMarkup,
  });

  final String id;
  final String rawPath;
  final int rawWidth;
  final int rawHeight;
  final Quad quad;
  final Quad detectedQuad;
  final String? croppedPath;
  final int? croppedWidth;
  final int? croppedHeight;
  final FilterSettings settings;

  /// Set while the page carries marks drawn in this session.
  final PageSnapshot? preMarkup;

  ScanPage copyWith({
    String? id,
    String? rawPath,
    int? rawWidth,
    int? rawHeight,
    Quad? quad,
    Quad? detectedQuad,
    String? croppedPath,
    int? croppedWidth,
    int? croppedHeight,
    FilterSettings? settings,
    PageSnapshot? preMarkup,
    bool clearPreMarkup = false,
  }) => ScanPage(
    id: id ?? this.id,
    rawPath: rawPath ?? this.rawPath,
    rawWidth: rawWidth ?? this.rawWidth,
    rawHeight: rawHeight ?? this.rawHeight,
    quad: quad ?? this.quad,
    detectedQuad: detectedQuad ?? this.detectedQuad,
    croppedPath: croppedPath ?? this.croppedPath,
    croppedWidth: croppedWidth ?? this.croppedWidth,
    croppedHeight: croppedHeight ?? this.croppedHeight,
    settings: settings ?? this.settings,
    preMarkup: clearPreMarkup ? null : (preMarkup ?? this.preMarkup),
  );
}

/// Cached JPEG preview of a page rendered with specific [settings].
class PagePreview {
  const PagePreview(this.settings, this.bytes);
  final FilterSettings settings;
  final Uint8List bytes;
}

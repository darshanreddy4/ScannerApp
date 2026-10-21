import 'package:equatable/equatable.dart';

import 'quad.dart';

/// A normalized working copy of a source image (EXIF baked, size capped).
class PreparedImage extends Equatable {
  const PreparedImage({required this.path, required this.width, required this.height, required this.detectedQuad});

  final String path;
  final int width;
  final int height;
  final Quad? detectedQuad;

  @override
  List<Object?> get props => [path, width, height, detectedQuad];
}

class ImageFileInfo extends Equatable {
  const ImageFileInfo({required this.path, required this.width, required this.height});

  final String path;
  final int width;
  final int height;

  @override
  List<Object?> get props => [path, width, height];
}

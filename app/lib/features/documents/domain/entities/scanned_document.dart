import 'package:equatable/equatable.dart';

class DocumentPage extends Equatable {
  const DocumentPage({
    required this.id,
    required this.position,
    required this.imagePath,
    required this.rawPath,
    required this.width,
    required this.height,
  });

  final String id;
  final int position;

  /// Absolute path of the processed (cropped + filtered) image.
  final String imagePath;

  /// Absolute path of the uncropped working copy, kept for future re-editing.
  final String rawPath;
  final int width;
  final int height;

  @override
  List<Object?> get props => [id, position, imagePath, rawPath, width, height];
}

class ScannedDocument extends Equatable {
  const ScannedDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DocumentPage> pages;

  int get pageCount => pages.length;
  DocumentPage? get cover => pages.isEmpty ? null : pages.first;

  @override
  List<Object?> get props => [id, title, createdAt, updatedAt, pages];
}

/// Page produced by the scan flow, not yet persisted.
class NewPage extends Equatable {
  const NewPage({required this.imagePath, required this.rawPath, required this.width, required this.height});

  final String imagePath;
  final String rawPath;
  final int width;
  final int height;

  @override
  List<Object?> get props => [imagePath, rawPath, width, height];
}

import 'package:equatable/equatable.dart';

/// Everything needed to re-open a page in the editor exactly as it was left.
class PageEditInfo extends Equatable {
  const PageEditInfo({
    required this.croppedPath,
    required this.quad,
    required this.filter,
    required this.brightness,
    required this.contrast,
    required this.rawWidth,
    required this.rawHeight,
  });

  /// Cropped image before filters (same file as the processed image when no filter was applied).
  final String croppedPath;

  /// Crop corners as 8 normalized numbers: tl, tr, br, bl (x, y each).
  final List<double> quad;
  final String filter;
  final double brightness;
  final double contrast;
  final int rawWidth;
  final int rawHeight;

  @override
  List<Object?> get props => [croppedPath, quad, filter, brightness, contrast, rawWidth, rawHeight];
}

class DocumentPage extends Equatable {
  const DocumentPage({
    required this.id,
    required this.position,
    required this.imagePath,
    required this.rawPath,
    required this.width,
    required this.height,
    this.edit,
  });

  final String id;
  final int position;

  /// Absolute path of the processed (cropped + filtered) image.
  final String imagePath;

  /// Absolute path of the uncropped working copy, kept for re-editing.
  final String rawPath;
  final int width;
  final int height;

  /// Null for pages saved before editing was supported.
  final PageEditInfo? edit;

  @override
  List<Object?> get props => [id, position, imagePath, rawPath, width, height, edit];
}

class ScannedDocument extends Equatable {
  const ScannedDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
    this.folderId,
    this.favorite = false,
    this.pinned = false,
    this.locked = false,
    this.tags = const [],
    this.expiresAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DocumentPage> pages;
  final String? folderId;
  final bool favorite;
  final bool pinned;

  /// Requires the device screen lock or biometrics to open.
  final bool locked;
  final List<String> tags;

  /// When the document stops being valid (a passport, a policy); null when it does not expire.
  final DateTime? expiresAt;

  int get pageCount => pages.length;
  DocumentPage? get cover => pages.isEmpty ? null : pages.first;

  @override
  List<Object?> get props => [id, title, createdAt, updatedAt, pages, folderId, favorite, pinned, locked, tags, expiresAt];
}

/// How a folder looks: an icon from the app's set (or [textOnly] for just its name) and an accent colour.
class FolderStyle extends Equatable {
  const FolderStyle({this.icon, this.color});

  /// Shown in place of an icon when the folder should be just text.
  static const textOnly = 'text';

  /// Null is the default folder icon.
  final String? icon;

  /// ARGB, or null for the default colour.
  final int? color;

  @override
  List<Object?> get props => [icon, color];
}

class Folder extends Equatable {
  const Folder({required this.id, required this.name, required this.createdAt, this.favorite = false, this.locked = false, this.icon, this.color});

  final String id;
  final String name;
  final DateTime createdAt;
  final bool favorite;
  final bool locked;
  final String? icon;
  final int? color;

  FolderStyle get style => FolderStyle(icon: icon, color: color);

  @override
  List<Object?> get props => [id, name, createdAt, favorite, locked, icon, color];
}

/// Page produced by the scan flow, not yet persisted.
class NewPage extends Equatable {
  const NewPage({required this.imagePath, required this.rawPath, required this.width, required this.height, this.edit});

  final String imagePath;
  final String rawPath;
  final int width;
  final int height;
  final PageEditInfo? edit;

  @override
  List<Object?> get props => [imagePath, rawPath, width, height, edit];
}

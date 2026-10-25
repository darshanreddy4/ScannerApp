import 'dart:typed_data';

import '../../../../core/error/result.dart';
import '../entities/filter_settings.dart';
import '../entities/prepared_image.dart';
import '../entities/quad.dart';

abstract interface class ScannerRepository {
  /// Normalizes [sourcePath] (JPEG/PNG), writes a working copy and detects the document outline.
  Future<Result<PreparedImage>> prepareImage(String sourcePath);

  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad});

  Future<Result<ImageFileInfo>> rotate90(String imagePath);

  /// Reads dimensions from the file header only (no full decode, no re-encode).
  Future<Result<ImageFileInfo>> imageInfo(String imagePath);

  /// Low-resolution filtered preview as JPEG bytes.
  Future<Result<Uint8List>> previewFilter({required String imagePath, required FilterSettings settings});

  /// Small previews of one image under several filter settings (decodes once).
  Future<Result<List<Uint8List>>> previewFilterBatch({required String imagePath, required List<FilterSettings> variants, int maxSide = 180});

  /// Full-resolution filtered output written to a new working file.
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings});
}

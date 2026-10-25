import 'dart:typed_data';

import '../../../../core/error/result.dart';
import '../entities/filter_settings.dart';
import '../entities/prepared_image.dart';
import '../entities/quad.dart';
import '../repositories/scanner_repository.dart';

class PrepareImage {
  const PrepareImage(this._repo);
  final ScannerRepository _repo;
  Future<Result<PreparedImage>> call(String sourcePath) => _repo.prepareImage(sourcePath);
}

class CropDocument {
  const CropDocument(this._repo);
  final ScannerRepository _repo;
  Future<Result<ImageFileInfo>> call({required String imagePath, required Quad quad}) => _repo.cropToQuad(imagePath: imagePath, quad: quad);
}

class RotateImage {
  const RotateImage(this._repo);
  final ScannerRepository _repo;
  Future<Result<ImageFileInfo>> call(String imagePath) => _repo.rotate90(imagePath);
}

class InspectImage {
  const InspectImage(this._repo);
  final ScannerRepository _repo;
  Future<Result<ImageFileInfo>> call(String imagePath) => _repo.imageInfo(imagePath);
}

class PreviewFilter {
  const PreviewFilter(this._repo);
  final ScannerRepository _repo;
  Future<Result<Uint8List>> call({required String imagePath, required FilterSettings settings}) =>
      _repo.previewFilter(imagePath: imagePath, settings: settings);
}

class PreviewFilterBatch {
  const PreviewFilterBatch(this._repo);
  final ScannerRepository _repo;
  Future<Result<List<Uint8List>>> call({required String imagePath, required List<FilterSettings> variants}) =>
      _repo.previewFilterBatch(imagePath: imagePath, variants: variants);
}

class ApplyFilter {
  const ApplyFilter(this._repo);
  final ScannerRepository _repo;
  Future<Result<ImageFileInfo>> call({required String imagePath, required FilterSettings settings}) =>
      _repo.applyFilter(imagePath: imagePath, settings: settings);
}

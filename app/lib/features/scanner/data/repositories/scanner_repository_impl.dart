import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/filter_settings.dart';
import '../../domain/entities/prepared_image.dart';
import '../../domain/entities/quad.dart';
import '../../domain/repositories/scanner_repository.dart';
import '../datasources/image_processing_service.dart';

class ScannerRepositoryImpl implements ScannerRepository {
  ScannerRepositoryImpl(this._service);

  final ImageProcessingService _service;
  final _uuid = const Uuid();
  Directory? _workDir;

  Future<String> _newPath() async {
    _workDir ??= await Directory(p.join((await getTemporaryDirectory()).path, 'scan_work')).create(recursive: true);
    return p.join(_workDir!.path, '${_uuid.v4()}.jpg');
  }

  Failure _processingError(Object e) => switch (e) {
    FormatException() => ImageProcessingFailure('This image format is not supported.', cause: e),
    _ => ImageProcessingFailure('The image could not be processed.', cause: e),
  };

  @override
  Future<Result<PreparedImage>> prepareImage(String sourcePath) => guard(() async {
    final lower = sourcePath.toLowerCase();
    if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))) {
      throw const ImageProcessingFailure('Only JPEG and PNG images can be imported.');
    }
    final out = await _newPath();
    final r = await _service.prepare(sourcePath, out);
    final q = r.quad;
    return PreparedImage(
      path: out,
      width: r.width,
      height: r.height,
      detectedQuad: q == null ? null : Quad(NormPoint(q[0], q[1]), NormPoint(q[2], q[3]), NormPoint(q[4], q[5]), NormPoint(q[6], q[7])),
    );
  }, onError: _processingError);

  @override
  Future<Result<ImageFileInfo>> cropToQuad({required String imagePath, required Quad quad}) => guard(() async {
    if (!quad.isConvex || quad.area < 0.01) {
      throw const ImageProcessingFailure('The selected area is too small or invalid.');
    }
    final out = await _newPath();
    final r = await _service.crop(imagePath, [
      for (final pt in quad.points) ...[pt.x, pt.y],
    ], out);
    return ImageFileInfo(path: out, width: r.width, height: r.height);
  }, onError: _processingError);

  @override
  Future<Result<ImageFileInfo>> imageInfo(String imagePath) => guard(() async {
    final r = await _service.inspect(imagePath);
    return ImageFileInfo(path: imagePath, width: r.width, height: r.height);
  }, onError: _processingError);

  @override
  Future<Result<ImageFileInfo>> rotate90(String imagePath) => guard(() async {
    final out = await _newPath();
    final r = await _service.rotate(imagePath, out);
    return ImageFileInfo(path: out, width: r.width, height: r.height);
  }, onError: _processingError);

  @override
  Future<Result<Uint8List>> previewFilter({required String imagePath, required FilterSettings settings}) =>
      guard(() => _service.preview(imagePath, settings), onError: _processingError);

  @override
  Future<Result<List<Uint8List>>> previewFilterBatch({required String imagePath, required List<FilterSettings> variants, int maxSide = 180}) =>
      guard(() => _service.previewBatch(imagePath, variants, maxSide), onError: _processingError);

  @override
  Future<Result<ImageFileInfo>> applyFilter({required String imagePath, required FilterSettings settings}) => guard(() async {
    final out = await _newPath();
    final r = await _service.applyFilter(imagePath, settings, out);
    return ImageFileInfo(path: out, width: r.width, height: r.height);
  }, onError: _processingError);
}

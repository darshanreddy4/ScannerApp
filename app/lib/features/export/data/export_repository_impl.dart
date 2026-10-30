import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../domain/entities/export_options.dart';
import '../domain/repositories/export_repository.dart';
import '../../../core/utils/region.dart';
import 'document_builders.dart';

class ExportRepositoryImpl implements ExportRepository {
  @override
  Future<Result<String>> export({required ScannedDocument document, required ExportFormat format, required ExportQuality quality}) => guard(
    () async {
      if (document.pages.isEmpty) throw const ExportFailure('This document has no pages to export.');

      final dir = await Directory(p.join((await getTemporaryDirectory()).path, 'exports')).create(recursive: true);
      final out = p.join(dir.path, '${_safeName(document.title)}.${format.extension}');
      final sources = [for (final pg in document.pages) PageSource(path: pg.imagePath, width: pg.width, height: pg.height)];

      try {
        switch (format) {
          case ExportFormat.pdf:
            await buildPdfInBackground(sources, quality, out);
          case ExportFormat.docx:
            final letter = Region.letter;
            await Isolate.run(() => buildDocx(sources, quality, out, letter: letter));
        }
      } catch (_) {
        final partial = File(out);
        if (await partial.exists()) await partial.delete();
        rethrow;
      }
      return out;
    },
    onError: (e) {
      final lowMemory = e is OutOfMemoryError || e.toString().contains('memory');
      return ExportFailure(
        lowMemory ? 'Not enough memory to export this many pages at this quality. Try a lower quality.' : 'The file could not be created.',
        cause: e,
      );
    },
  );

  String _safeName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'document' : cleaned;
  }
}

class SharePlusService implements ShareService {
  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) =>
      shareFiles(paths: [path], mimeType: mimeType, subject: subject);

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) => guard(() async {
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final p in paths) XFile(p, mimeType: mimeType)],
        subject: subject,
      ),
    );
  }, onError: (e) => ExportFailure('The share sheet could not be opened.', cause: e));

  @override
  Future<Result<void>> shareText({required String text, String? subject}) => guard(() async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }, onError: (e) => ExportFailure('The share sheet could not be opened.', cause: e));
}

class DeviceSaveService implements SaveService {
  @override
  Future<Result<bool>> saveToFiles({required String sourcePath, required String fileName, required String mimeType}) => guard(() async {
    final bytes = await File(sourcePath).readAsBytes();
    final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    return saved != null;
  }, onError: (e) => StorageFailure('The file could not be saved.', cause: e));

  @override
  Future<Result<int>> saveImagesToGallery(List<String> paths) => guard(() async {
    if (!await Gal.hasAccess(toAlbum: true) && !await Gal.requestAccess(toAlbum: true)) {
      throw const PermissionFailure('Allow photo access in Settings to save images to your gallery.');
    }
    for (final path in paths) {
      await Gal.putImage(path, album: 'Doculoom');
    }
    return paths.length;
  }, onError: (e) => StorageFailure('The images could not be saved to your gallery.', cause: e));
}

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../domain/entities/export_options.dart';
import '../domain/repositories/export_repository.dart';
import 'document_builders.dart';

class ExportRepositoryImpl implements ExportRepository {
  @override
  Future<Result<String>> export({
    required ScannedDocument document,
    required ExportFormat format,
    required ExportQuality quality,
  }) =>
      guard(() async {
        if (document.pages.isEmpty) throw const ExportFailure('This document has no pages to export.');

        final dir = await Directory(p.join((await getTemporaryDirectory()).path, 'exports')).create(recursive: true);
        final out = p.join(dir.path, '${_safeName(document.title)}.${format.extension}');
        final sources = [
          for (final pg in document.pages) PageSource(path: pg.imagePath, width: pg.width, height: pg.height),
        ];

        try {
          switch (format) {
            case ExportFormat.pdf:
              await Isolate.run(() => buildPdf(sources, quality, out));
            case ExportFormat.docx:
              await Isolate.run(() => buildDocx(sources, quality, out));
          }
        } catch (_) {
          final partial = File(out);
          if (await partial.exists()) await partial.delete();
          rethrow;
        }
        return out;
      }, onError: (e) {
        final lowMemory = e is OutOfMemoryError || e.toString().contains('memory');
        return ExportFailure(
          lowMemory
              ? 'Not enough memory to export this many pages at this quality. Try a lower quality.'
              : 'The file could not be created.',
          cause: e,
        );
      });

  String _safeName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^\w\- ]+'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'document' : cleaned;
  }
}

class SharePlusService implements ShareService {
  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) => guard(() async {
        await SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: mimeType)], subject: subject));
      }, onError: (e) => ExportFailure('The share sheet could not be opened.', cause: e));
}

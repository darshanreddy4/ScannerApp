import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/importer.dart';
import 'docx_parser.dart';
import 'pdf_importer.dart';
import 'text_page_renderer.dart';

class DocumentImporterImpl implements DocumentImporter {
  final _pdf = PdfImporter();
  final _text = TextPageRenderer();
  final _uuid = const Uuid();

  Future<Directory> _workDir() async => Directory(p.join((await getTemporaryDirectory()).path, 'scan_work')).create(recursive: true);

  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) => guard(
    () async {
      if (!await File(path).exists()) throw const ImportFailure('The selected file could not be found.');
      final dir = (await _workDir()).path;
      final prefix = _uuid.v4();
      final title = p.basenameWithoutExtension(path);

      final images = switch (kind) {
        ImportKind.pdf => await _pdf.toImages(path: path, outDir: dir, prefix: prefix, onProgress: onProgress),
        ImportKind.docx => await _docx(path, dir, prefix, onProgress),
      };
      if (images.isEmpty) throw const ImportFailure('Nothing could be imported from this file.');
      return ImportedDocument(title: title, imagePaths: images);
    },
    onError: (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password') || msg.contains('encrypt')) {
        return ImportFailure('This file is password protected. Remove the password first with Tools > Lock or unlock PDF.', cause: e);
      }
      return ImportFailure('The file could not be imported. It may be damaged or unsupported.', cause: e);
    },
  );

  Future<List<String>> _docx(String path, String dir, String prefix, ImportProgress? onProgress) async {
    final blocks = await Isolate.run(() => parseDocx(path: path, outDir: dir, prefix: prefix));
    if (blocks.isEmpty) throw const ImportFailure('This Word document is empty.');

    final out = <String>[];
    var textRun = 0;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.isImage) {
        out.add(b.value);
      } else {
        out.addAll(await _text.render(text: b.value, outDir: dir, prefix: '$prefix-${textRun++}'));
      }
      onProgress?.call(i + 1, blocks.length);
    }
    return out;
  }
}

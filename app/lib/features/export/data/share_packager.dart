import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../pdf_tools/domain/pdf_protector.dart';

class PackedShare {
  const PackedShare({required this.path, required this.mimeType});
  final String path;
  final String mimeType;
}

/// Turns an exported PDF into the exact file to send: optionally with a password, optionally inside a ZIP.
/// It only writes new files in a temporary folder; the PDF it is given and the saved document are never changed.
class SharePackager {
  const SharePackager(this._protector, {Future<Directory> Function() tempDir = getTemporaryDirectory}) : _tempDir = tempDir;

  final PdfProtector _protector;
  final Future<Directory> Function() _tempDir;

  static const minPasswordLength = 4;

  Future<Result<PackedShare>> pack({required String pdfPath, String? password, bool zip = false}) => guard(() async {
    if (password != null && password.length < minPasswordLength) throw const PasswordFailure('Use at least $minPasswordLength characters.');
    var path = pdfPath;
    var mime = 'application/pdf';
    if (password == null && !zip) return PackedShare(path: path, mimeType: mime);

    // A fresh folder per call, so the name the receiver sees stays clean and an earlier file is never reused.
    final root = Directory(p.join((await _tempDir()).path, 'share_out'));
    if (await root.exists()) await root.delete(recursive: true);
    final dir = await Directory(p.join(root.path, '${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);

    if (password != null) {
      final locked = p.join(dir.path, p.basename(path));
      final result = await _protector.lock(sourcePath: path, outputPath: locked, password: password);
      final failure = result.failureOrNull;
      if (failure != null) throw failure;
      path = locked;
    }
    if (zip) {
      final out = p.join(dir.path, '${p.basenameWithoutExtension(path)}.zip');
      final name = p.basename(path);
      final source = path;
      await Isolate.run(() async {
        final bytes = await File(source).readAsBytes();
        final archive = Archive()..addFile(ArchiveFile.bytes(name, bytes));
        await File(out).writeAsBytes(Uint8List.fromList(ZipEncoder().encode(archive)), flush: true);
      });
      path = out;
      mime = 'application/zip';
    }
    return PackedShare(path: path, mimeType: mime);
  }, onError: (e) => e is Failure ? e : ExportFailure('The file could not be prepared for sharing.', cause: e));
}

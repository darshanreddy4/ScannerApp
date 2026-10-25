import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/signature.dart';

/// Keeps signatures as PNG files inside the app's private storage.
class SignatureStoreImpl implements SignatureStore {
  SignatureStoreImpl({required Future<Directory> Function() appDir}) : _appDir = appDir;

  final Future<Directory> Function() _appDir;
  int _counter = 0;

  Future<Directory> _dir() async => Directory(p.join((await _appDir()).path, 'signatures'));

  @override
  Future<List<SavedSignature>> list() async {
    final dir = await _dir();
    if (!await dir.exists()) return const [];
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final out = <SavedSignature>[];
    for (final file in files) {
      try {
        final bytes = file.readAsBytesSync();
        final info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info == null) continue;
        out.add(SavedSignature(id: p.basenameWithoutExtension(file.path), path: file.path, width: info.width, height: info.height));
      } on Object {
        // An unreadable file is skipped rather than breaking the list.
      }
    }
    return out;
  }

  @override
  Future<Result<SavedSignature>> save(String pngPath) => guard(() async {
    final existing = await list();
    if (existing.length >= SignatureStore.maxSaved) {
      throw const ExportFailure('You can keep up to ${SignatureStore.maxSaved} signatures. Delete one to add another.');
    }
    final dir = await (await _dir()).create(recursive: true);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';
    final target = await File(pngPath).copy(p.join(dir.path, '$id.png'));
    final bytes = await target.readAsBytes();
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    if (info == null) {
      await target.delete();
      throw const ExportFailure('The signature could not be saved.');
    }
    return SavedSignature(id: id, path: target.path, width: info.width, height: info.height);
  }, onError: (e) => e is Failure ? e : ExportFailure('The signature could not be saved.', cause: e));

  @override
  Future<void> delete(String id) async {
    final file = File(p.join((await _dir()).path, '$id.png'));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

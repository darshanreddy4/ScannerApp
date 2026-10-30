import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../domain/signature.dart';
import 'signature_ink.dart';

/// Keeps signatures as PNG files inside the app's private storage, with a small index file for their names, kinds, order and defaults.
class SignatureStoreImpl implements SignatureStore {
  SignatureStoreImpl({required Future<Directory> Function() appDir}) : _appDir = appDir;

  final Future<Directory> Function() _appDir;
  int _counter = 0;

  static const _maxName = 40;

  Future<Directory> _dir() async => Directory(p.join((await _appDir()).path, 'signatures'));

  Future<File> _indexFile() async => File(p.join((await _dir()).path, 'library.json'));

  Future<_Index> _readIndex() async {
    try {
      final f = await _indexFile();
      if (await f.exists()) return _Index.fromJson(jsonDecode(await f.readAsString()));
    } on Object {
      // A damaged index only loses the names and the order; the pictures are still there.
    }
    return _Index();
  }

  Future<void> _writeIndex(_Index index) async {
    final dir = await (await _dir()).create(recursive: true);
    final tmp = File(p.join(dir.path, 'library.json.tmp'));
    await tmp.writeAsString(jsonEncode(index.toJson()), flush: true);
    await tmp.rename(p.join(dir.path, 'library.json'));
  }

  @override
  Future<List<SavedSignature>> list() async {
    final dir = await _dir();
    if (!await dir.exists()) return const [];
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.png')).toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final byId = <String, SavedSignature>{};
    final index = await _readIndex();
    for (final file in files) {
      try {
        final bytes = file.readAsBytesSync();
        final info = img.findDecoderForData(bytes)?.startDecode(bytes);
        if (info == null) continue;
        final id = p.basenameWithoutExtension(file.path);
        final meta = index.items[id];
        byId[id] = SavedSignature(
          id: id,
          path: file.path,
          width: info.width,
          height: info.height,
          name: meta?.name ?? '',
          kind: meta?.kind ?? SignatureKind.signature,
          isDefault: meta?.isDefault ?? false,
        );
      } on Object {
        // An unreadable file is skipped rather than breaking the list.
      }
    }
    final ordered = [
      for (final id in index.order)
        if (byId.containsKey(id)) byId.remove(id)!,
      ...byId.values,
    ];
    // Every kind has a default as long as it has any picture.
    final out = <SavedSignature>[];
    for (final kind in SignatureKind.values) {
      final ofKind = ordered.where((s) => s.kind == kind).toList();
      final hasDefault = ofKind.any((s) => s.isDefault);
      for (final s in ofKind) {
        out.add(hasDefault || s.id != ofKind.first.id ? s : s.copyWith(isDefault: true));
      }
    }
    final position = {for (final (i, s) in ordered.indexed) s.id: i};
    out.sort((a, b) => position[a.id]!.compareTo(position[b.id]!));
    return out;
  }

  @override
  Future<Result<SavedSignature>> save(String pngPath, {SignatureKind kind = SignatureKind.signature, String name = ''}) => guard(() async {
    final existing = await list();
    _checkRoom(existing);
    final saved = await _copyIn(pngPath);
    final index = await _readIndex();
    index.order
      ..clear()
      ..addAll([for (final s in existing) s.id, saved.id]);
    index.items[saved.id] = _Meta(name: _cleanName(name), kind: kind, isDefault: !existing.any((s) => s.kind == kind));
    await _writeIndex(index);
    return saved.copyWith(name: _cleanName(name), kind: kind, isDefault: index.items[saved.id]!.isDefault);
  }, onError: (e) => e is Failure ? e : ExportFailure('The signature could not be saved.', cause: e));

  void _checkRoom(List<SavedSignature> existing) {
    if (existing.length >= SignatureStore.maxSaved) {
      throw const ExportFailure('You can keep up to ${SignatureStore.maxSaved} signatures. Delete one to add another.');
    }
  }

  Future<SavedSignature> _copyIn(String pngPath) async {
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
  }

  static String _cleanName(String name) {
    final t = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length > _maxName ? t.substring(0, _maxName).trim() : t;
  }

  /// The index as it is now, with the pictures that exist (in their shown order) written into it.
  Future<_Index> _current() async {
    final index = await _readIndex();
    final all = await list();
    index.order
      ..clear()
      ..addAll([for (final s in all) s.id]);
    for (final s in all) {
      index.items[s.id] = _Meta(name: s.name, kind: s.kind, isDefault: s.isDefault);
    }
    return index;
  }

  @override
  Future<void> update(String id, {String? name, SignatureKind? kind}) async {
    final index = await _current();
    final meta = index.items[id];
    if (meta == null) return;
    final oldKind = meta.kind;
    if (name != null) meta.name = _cleanName(name);
    if (kind != null && kind != oldKind) {
      meta.kind = kind;
      meta.isDefault = !index.items.entries.any((e) => e.key != id && e.value.kind == kind && e.value.isDefault);
      if (!index.items.entries.any((e) => e.key != id && e.value.kind == kind)) meta.isDefault = true;
    }
    await _writeIndex(index);
  }

  @override
  Future<void> setDefault(String id) async {
    final index = await _current();
    final kind = index.items[id]?.kind;
    if (kind == null) return;
    for (final e in index.items.entries) {
      if (e.value.kind == kind) e.value.isDefault = e.key == id;
    }
    await _writeIndex(index);
  }

  @override
  Future<void> move(String id, int newIndex) async {
    final index = await _current();
    if (!index.order.remove(id)) return;
    index.order.insert(newIndex.clamp(0, index.order.length), id);
    await _writeIndex(index);
  }

  @override
  Future<Result<SavedSignature>> recolor(String id, InkColor ink) => guard(() async {
    final all = await list();
    final s = all.firstWhere((e) => e.id == id, orElse: () => throw const ExportFailure('That signature is no longer there.'));
    final file = File(s.path);
    await file.writeAsBytes(recolorPng(await file.readAsBytes(), ink.argb), flush: true);
    return s;
  }, onError: (e) => e is Failure ? e : ExportFailure('The colour could not be changed.', cause: e));

  @override
  Future<Result<SavedSignature>> duplicate(String id) => guard(() async {
    final all = await list();
    _checkRoom(all);
    final s = all.firstWhere((e) => e.id == id, orElse: () => throw const ExportFailure('That signature is no longer there.'));
    final copy = await _copyIn(s.path);
    final index = await _current();
    final name = s.name.isEmpty ? '' : _cleanName('${s.name} copy');
    index.items[copy.id] = _Meta(name: name, kind: s.kind, isDefault: false);
    index.order.insert(index.order.indexOf(id) + 1, copy.id);
    await _writeIndex(index);
    return copy.copyWith(name: name, kind: s.kind);
  }, onError: (e) => e is Failure ? e : ExportFailure('The signature could not be copied.', cause: e));

  @override
  Future<void> delete(String id) async {
    final dir = await _dir();
    final file = File(p.join(dir.path, '$id.png'));
    if (await file.exists()) await file.delete();
    if (!await dir.exists()) return;
    final index = await _current();
    final gone = index.items.remove(id);
    index.order.remove(id);
    if (gone != null && gone.isDefault) {
      for (final e in index.items.entries) {
        if (e.value.kind == gone.kind) {
          e.value.isDefault = true;
          break;
        }
      }
    }
    await _writeIndex(index);
  }

  @override
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

class _Meta {
  _Meta({this.name = '', this.kind = SignatureKind.signature, this.isDefault = false});
  String name;
  SignatureKind kind;
  bool isDefault;
}

class _Index {
  _Index();
  final order = <String>[];
  final items = <String, _Meta>{};

  factory _Index.fromJson(Object? json) {
    final out = _Index();
    if (json is! Map) return out;
    final order = json['order'];
    if (order is List) out.order.addAll(order.whereType<String>());
    final items = json['items'];
    if (items is Map) {
      items.forEach((k, v) {
        if (k is String && v is Map) {
          out.items[k] = _Meta(
            name: v['name'] is String ? v['name'] as String : '',
            kind: SignatureKind.values.asNameMap()[v['kind']] ?? SignatureKind.signature,
            isDefault: v['default'] == true,
          );
        }
      });
    }
    return out;
  }

  Map<String, Object?> toJson() => {
    'order': order,
    'items': {
      for (final e in items.entries) e.key: {'name': e.value.name, 'kind': e.value.kind.name, 'default': e.value.isDefault},
    },
  };
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

enum BackupProblem { notABackup, wrongPassword, damaged, newerVersion }

class BackupException implements Exception {
  const BackupException(this.problem, this.message);
  final BackupProblem problem;
  final String message;

  @override
  String toString() => message;
}

/// A backup file is a sequence of encrypted chunks (ChaCha20-Poly1305, key from the password with PBKDF2). Each chunk
/// authenticates its position and whether it is the last one, so reordering, cutting off or altering it is detected.
///
///     "SVBK" version(1) salt(16) iterations(4) noncePrefix(4)
///     then repeated: length(4) last(1) ciphertext+tag
///
/// The decrypted bytes are records: nameLength(2) name size(8) data.
const _magic = [0x53, 0x56, 0x42, 0x4B];
const _version = 1;
const _chunkSize = 1 << 20;
const _headerLength = 4 + 1 + 16 + 4 + 4;
const _macLength = 16;
const defaultBackupIterations = 200000;

final _cipher = Chacha20.poly1305Aead();

Future<SecretKey> _deriveKey(String password, List<int> salt, int iterations) =>
    Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256).deriveKeyFromPassword(password: password, nonce: salt);

List<int> _nonce(List<int> prefix, int counter) {
  final b = ByteData(12);
  for (var i = 0; i < 4; i++) {
    b.setUint8(i, prefix[i]);
  }
  b.setUint64(4, counter);
  return b.buffer.asUint8List();
}

List<int> _aad(Uint8List header, bool last) => [...header, last ? 1 : 0];

/// Writes records into an encrypted backup file.
class BackupWriter {
  BackupWriter._(this._file, this._key, this._header, this._prefix);

  final RandomAccessFile _file;
  final SecretKey _key;
  final Uint8List _header;
  final List<int> _prefix;
  final _buffer = BytesBuilder(copy: false);
  var _counter = 0;
  var _closed = false;

  static Future<BackupWriter> open(String path, String password, {int iterations = defaultBackupIterations}) async {
    final random = Random.secure();
    List<int> bytes(int n) => List.generate(n, (_) => random.nextInt(256));
    final salt = bytes(16);
    final prefix = bytes(4);
    final header = BytesBuilder()
      ..add(_magic)
      ..addByte(_version)
      ..add(salt)
      ..add((ByteData(4)..setUint32(0, iterations)).buffer.asUint8List())
      ..add(prefix);
    final headerBytes = header.takeBytes();
    final key = await _deriveKey(password, salt, iterations);
    final file = await File(path).open(mode: FileMode.write);
    await file.writeFrom(headerBytes);
    return BackupWriter._(file, key, headerBytes, prefix);
  }

  Future<void> addBytes(String name, List<int> data) async {
    final nameBytes = utf8.encode(name);
    final head = ByteData(2 + nameBytes.length + 8)..setUint16(0, nameBytes.length);
    final raw = head.buffer.asUint8List();
    raw.setRange(2, 2 + nameBytes.length, nameBytes);
    head.setUint64(2 + nameBytes.length, data.length);
    await _push(raw);
    await _push(data);
  }

  Future<void> addFile(String name, String path) async {
    final file = File(path);
    final size = await file.length();
    final nameBytes = utf8.encode(name);
    final head = ByteData(2 + nameBytes.length + 8)..setUint16(0, nameBytes.length);
    head.buffer.asUint8List().setRange(2, 2 + nameBytes.length, nameBytes);
    head.setUint64(2 + nameBytes.length, size);
    await _push(head.buffer.asUint8List());
    var sent = 0;
    await for (final part in file.openRead()) {
      sent += part.length;
      await _push(part);
    }
    if (sent != size) throw const BackupException(BackupProblem.damaged, 'A file changed while the backup was being made.');
  }

  Future<void> _push(List<int> data) async {
    _buffer.add(data);
    while (_buffer.length >= _chunkSize + 1) {
      final all = _buffer.takeBytes();
      await _emit(Uint8List.sublistView(all, 0, _chunkSize), last: false);
      _buffer.add(Uint8List.sublistView(all, _chunkSize));
    }
  }

  Future<void> _emit(List<int> plain, {required bool last}) async {
    final box = await _cipher.encrypt(plain, secretKey: _key, nonce: _nonce(_prefix, _counter++), aad: _aad(_header, last));
    final frame = BytesBuilder(copy: false)
      ..add(
        (ByteData(5)
              ..setUint32(0, box.cipherText.length + _macLength)
              ..setUint8(4, last ? 1 : 0))
            .buffer
            .asUint8List(),
      )
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    await _file.writeFrom(frame.takeBytes());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _emit(_buffer.takeBytes(), last: true);
    await _file.close();
  }

  Future<void> abort() async {
    _closed = true;
    await _file.close();
  }
}

/// True when [path] starts like a backup file.
Future<bool> looksLikeBackup(String path) async {
  try {
    final f = await File(path).open();
    try {
      final head = await f.read(_magic.length);
      return head.length == _magic.length && List.generate(_magic.length, (i) => head[i] == _magic[i]).every((e) => e);
    } finally {
      await f.close();
    }
  } catch (_) {
    return false;
  }
}

/// Decrypts a backup and writes every record into [outDir]. Names that would leave the folder are refused.
Future<void> readBackup(String path, String password, Directory outDir) async {
  final raf = await File(path).open();
  try {
    final header = await raf.read(_headerLength);
    if (header.length < _headerLength || !List.generate(_magic.length, (i) => header[i] == _magic[i]).every((e) => e)) {
      throw const BackupException(BackupProblem.notABackup, 'This file is not a Doculoom backup.');
    }
    if (header[4] > _version) {
      throw const BackupException(BackupProblem.newerVersion, 'This backup was made by a newer version of Doculoom. Update the app to open it.');
    }
    final iterations = ByteData.sublistView(header, 21, 25).getUint32(0);
    if (iterations < 1000 || iterations > 5000000) throw const BackupException(BackupProblem.damaged, 'This backup file is damaged.');
    final prefix = header.sublist(25, 29);
    final key = await _deriveKey(password, header.sublist(5, 21), iterations);

    final parser = _RecordParser(outDir);
    var counter = 0;
    var sawLast = false;
    while (!sawLast) {
      final frameHead = await raf.read(5);
      if (frameHead.length < 5) throw const BackupException(BackupProblem.damaged, 'This backup is incomplete. The file may have been cut off.');
      final length = ByteData.sublistView(frameHead, 0, 4).getUint32(0);
      final last = frameHead[4] == 1;
      if (length < _macLength || length > _chunkSize + _macLength) throw const BackupException(BackupProblem.damaged, 'This backup file is damaged.');
      final body = await raf.read(length);
      if (body.length < length) throw const BackupException(BackupProblem.damaged, 'This backup is incomplete. The file may have been cut off.');
      List<int> plain;
      try {
        plain = await _cipher.decrypt(
          SecretBox(body.sublist(0, length - _macLength), nonce: _nonce(prefix, counter), mac: Mac(body.sublist(length - _macLength))),
          secretKey: key,
          aad: _aad(header, last),
        );
      } on SecretBoxAuthenticationError {
        throw BackupException(
          counter == 0 ? BackupProblem.wrongPassword : BackupProblem.damaged,
          counter == 0 ? 'The password is not correct.' : 'This backup file is damaged.',
        );
      }
      counter++;
      await parser.add(plain);
      sawLast = last;
    }
    if (await raf.position() != await raf.length()) throw const BackupException(BackupProblem.damaged, 'This backup file is damaged.');
    await parser.finish();
  } finally {
    await raf.close();
  }
}

class _RecordParser {
  _RecordParser(this._dir);

  final Directory _dir;
  final _pending = BytesBuilder(copy: false);
  IOSink? _out;
  var _remaining = 0;
  final _seen = <String>{};

  Future<void> add(List<int> data) async {
    var bytes = Uint8List.fromList(data);
    while (bytes.isNotEmpty) {
      if (_remaining > 0) {
        final take = min(_remaining, bytes.length);
        _out!.add(Uint8List.sublistView(bytes, 0, take));
        _remaining -= take;
        bytes = Uint8List.sublistView(bytes, take);
        if (_remaining == 0) await _closeRecord();
        continue;
      }
      _pending.add(bytes);
      bytes = Uint8List(0);
      await _startRecords();
    }
  }

  /// Reads record headers while enough bytes are buffered.
  Future<void> _startRecords() async {
    while (true) {
      final all = _pending.toBytes();
      if (all.length < 2) return;
      final nameLength = ByteData.sublistView(all, 0, 2).getUint16(0);
      final headerLength = 2 + nameLength + 8;
      if (all.length < headerLength) return;
      final name = utf8.decode(all.sublist(2, 2 + nameLength), allowMalformed: false);
      final size = ByteData.sublistView(all, 2 + nameLength, headerLength).getUint64(0);
      _pending.clear();
      final file = _target(name);
      _out = file.openWrite();
      _remaining = size;
      final rest = Uint8List.sublistView(all, headerLength);
      if (size == 0) {
        await _closeRecord();
        if (rest.isEmpty) return;
        _pending.add(rest);
        continue;
      }
      if (rest.isEmpty) return;
      final take = min(size, rest.length);
      _out!.add(Uint8List.sublistView(rest, 0, take));
      _remaining -= take;
      if (_remaining == 0) await _closeRecord();
      final extra = Uint8List.sublistView(rest, take);
      if (extra.isEmpty) return;
      _pending.add(extra);
    }
  }

  File _target(String name) {
    final parts = name.split('/');
    final unsafe = name.isEmpty || name.startsWith('/') || name.contains('\\') || parts.any((p) => p.isEmpty || p == '.' || p == '..');
    if (unsafe || !_seen.add(name)) throw const BackupException(BackupProblem.damaged, 'This backup file is damaged.');
    final file = File('${_dir.path}/$name');
    file.parent.createSync(recursive: true);
    return file;
  }

  Future<void> _closeRecord() async {
    await _out?.close();
    _out = null;
  }

  Future<void> finish() async {
    if (_remaining != 0 || _pending.length != 0) {
      await _out?.close();
      throw const BackupException(BackupProblem.damaged, 'This backup is incomplete. The file may have been cut off.');
    }
  }
}

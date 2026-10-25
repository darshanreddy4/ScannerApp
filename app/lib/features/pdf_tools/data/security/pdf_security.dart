import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ciphers.dart';
import 'pdf_model.dart';

enum CryptMethod { none, rc4, aesV2, aesV3 }

class WrongPasswordException implements Exception {
  const WrongPasswordException();
}

class UnsupportedProtectionException implements Exception {
  const UnsupportedProtectionException(this.message);
  final String message;
}

final _padding = Uint8List.fromList([
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
]);

Uint8List _md5(List<int> data) => Uint8List.fromList(md5.convert(data).bytes);

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.takeBytes();
}

Uint8List _int32le(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

bool _same(List<int> a, List<int> b, [int? n]) {
  final len = n ?? a.length;
  if (a.length < len || b.length < len) return false;
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _legacyPassword(String password) {
  final units = password.codeUnits;
  final bytes = units.every((u) => u < 256) ? Uint8List.fromList(units) : Uint8List.fromList(utf8.encode(password));
  return bytes;
}

Uint8List _padded(Uint8List password) {
  final out = Uint8List(32);
  final n = password.length < 32 ? password.length : 32;
  out.setRange(0, n, password);
  out.setRange(n, 32, _padding);
  return out;
}

Uint8List _modernPassword(String password) {
  final bytes = utf8.encode(password);
  return Uint8List.fromList(bytes.length > 127 ? bytes.sublist(0, 127) : bytes);
}

/// The hash of the AES-256 protection: plain SHA-256 for revision 5, the longer "hardened" hash for revision 6.
Uint8List pdfHashR56(int revision, Uint8List password, Uint8List salt, Uint8List userData) {
  var k = Uint8List.fromList(sha256.convert(_concat([password, salt, userData])).bytes);
  if (revision < 6) return k;
  var round = 0;
  while (true) {
    round++;
    final k1 = _concat([password, k, userData]);
    final repeated = Uint8List(k1.length * 64);
    for (var i = 0; i < 64; i++) {
      repeated.setRange(i * k1.length, (i + 1) * k1.length, k1);
    }
    final e = aesCbcEncrypt(Uint8List.sublistView(k, 0, 16), Uint8List.sublistView(k, 16, 32), repeated, pad: false);
    var sum = 0;
    for (var i = 0; i < 16; i++) {
      sum += e[i];
    }
    final hash = switch (sum % 3) {
      0 => sha256,
      1 => sha384,
      _ => sha512,
    };
    k = Uint8List.fromList(hash.convert(e).bytes);
    if (round >= 64 && e.last <= round - 32) break;
  }
  return Uint8List.sublistView(k, 0, 32);
}

/// Opens a PDF protected with the standard security handler (RC4 40 or 128 bit, AES 128 bit, AES 256 bit) and decrypts its parts.
class PdfSecurity {
  PdfSecurity._({required this.fileKey, required this.version, required this.stream, required this.string, required this.encryptMetadata});

  final Uint8List fileKey;
  final int version;
  final CryptMethod stream;
  final CryptMethod string;
  final bool encryptMetadata;

  /// Checks [password] as the user password and then as the owner password.
  static PdfSecurity open(PdfDict enc, Uint8List id0, String password) {
    final filter = enc.nameOf('Filter');
    if (filter != null && filter != 'Standard') {
      throw const UnsupportedProtectionException('This PDF uses a kind of protection this app cannot open.');
    }
    final v = enc.intOf('V') ?? 0;
    final r = enc.intOf('R') ?? 0;
    if (v < 1 || v > 5 || r < 2 || r > 6 || (v == 5 && r < 5)) {
      throw const UnsupportedProtectionException('This PDF uses a kind of protection this app cannot open.');
    }
    final encryptMetadata = enc.boolOf('EncryptMetadata') ?? true;
    var stm = CryptMethod.rc4, str = CryptMethod.rc4;
    if (v >= 4) {
      final cf = enc['CF'];
      CryptMethod methodFor(String? name) {
        if (name == null || name == 'Identity') return CryptMethod.none;
        final filterDict = cf is PdfDict ? cf[name] : null;
        final cfm = filterDict is PdfDict ? filterDict.nameOf('CFM') : null;
        return switch (cfm) {
          'V2' => CryptMethod.rc4,
          'AESV2' => CryptMethod.aesV2,
          'AESV3' => CryptMethod.aesV3,
          'None' => CryptMethod.none,
          _ => throw const UnsupportedProtectionException('This PDF uses a kind of protection this app cannot open.'),
        };
      }

      stm = methodFor(enc.nameOf('StmF'));
      str = methodFor(enc.nameOf('StrF'));
    }
    final o = enc.bytesOf('O'), u = enc.bytesOf('U');
    if (o == null || u == null) throw const UnsupportedProtectionException('The protection information of this PDF is damaged.');

    final Uint8List key;
    if (v == 5) {
      key = _openR56(enc, r, o, u, _modernPassword(password));
    } else {
      key = _openLegacy(enc, v, r, o, u, id0, password, encryptMetadata);
    }
    return PdfSecurity._(fileKey: key, version: v, stream: stm, string: str, encryptMetadata: encryptMetadata);
  }

  static Uint8List _openR56(PdfDict enc, int r, Uint8List o, Uint8List u, Uint8List pwd) {
    final ue = enc.bytesOf('UE'), oe = enc.bytesOf('OE');
    if (u.length < 48 || o.length < 48 || ue == null || oe == null || ue.length < 32 || oe.length < 32) {
      throw const UnsupportedProtectionException('The protection information of this PDF is damaged.');
    }
    final zeroIv = Uint8List(16);
    final u48 = Uint8List.sublistView(u, 0, 48);
    if (_same(pdfHashR56(r, pwd, Uint8List.sublistView(u, 32, 40), Uint8List(0)), u, 32)) {
      final k = pdfHashR56(r, pwd, Uint8List.sublistView(u, 40, 48), Uint8List(0));
      return aesCbcDecrypt(k, zeroIv, Uint8List.sublistView(ue, 0, 32), unpad: false);
    }
    if (_same(pdfHashR56(r, pwd, Uint8List.sublistView(o, 32, 40), u48), o, 32)) {
      final k = pdfHashR56(r, pwd, Uint8List.sublistView(o, 40, 48), u48);
      return aesCbcDecrypt(k, zeroIv, Uint8List.sublistView(oe, 0, 32), unpad: false);
    }
    throw const WrongPasswordException();
  }

  static Uint8List _openLegacy(PdfDict enc, int v, int r, Uint8List o, Uint8List u, Uint8List id0, String password, bool encryptMetadata) {
    final length = v == 1 || r == 2 ? 40 : (enc.intOf('Length') ?? (v == 4 ? 128 : 40));
    final n = (length ~/ 8).clamp(5, 16);
    final p = (enc.intOf('P') ?? 0) & 0xFFFFFFFF;
    final o32 = o.length >= 32 ? Uint8List.sublistView(o, 0, 32) : o;

    Uint8List fileKey(Uint8List paddedPassword) {
      final input = _concat([
        paddedPassword,
        o32,
        _int32le(p),
        id0,
        if (r >= 4 && !encryptMetadata) const [0xFF, 0xFF, 0xFF, 0xFF],
      ]);
      var h = _md5(input);
      if (r >= 3) {
        for (var i = 0; i < 50; i++) {
          h = _md5(Uint8List.sublistView(h, 0, n));
        }
      }
      return Uint8List.sublistView(h, 0, n);
    }

    bool userOk(Uint8List key) {
      if (r == 2) return _same(rc4(key, _padding), u, 32);
      var x = rc4(key, _md5(_concat([_padding, id0])));
      for (var i = 1; i <= 19; i++) {
        x = rc4(Uint8List.fromList([for (final b in key) b ^ i]), x);
      }
      return _same(x, u, 16);
    }

    final pwd = _padded(_legacyPassword(password));
    final userKey = fileKey(pwd);
    if (userOk(userKey)) return userKey;

    // The password may be the owner password: it unlocks the stored user password.
    var h = _md5(pwd);
    if (r >= 3) {
      for (var i = 0; i < 50; i++) {
        h = _md5(h);
      }
    }
    final ownerKey = Uint8List.sublistView(h, 0, n);
    Uint8List userPwd;
    if (r == 2) {
      userPwd = rc4(ownerKey, o32);
    } else {
      userPwd = Uint8List.fromList(o32);
      for (var i = 19; i >= 0; i--) {
        userPwd = rc4(Uint8List.fromList([for (final b in ownerKey) b ^ i]), userPwd);
      }
    }
    final viaOwner = fileKey(userPwd);
    if (userOk(viaOwner)) return viaOwner;
    throw const WrongPasswordException();
  }

  Uint8List _objectKey(int number, int generation, CryptMethod method) {
    if (version >= 5) return fileKey;
    final extra = [number & 0xFF, (number >> 8) & 0xFF, (number >> 16) & 0xFF, generation & 0xFF, (generation >> 8) & 0xFF];
    final input = _concat([
      fileKey,
      extra,
      if (method == CryptMethod.aesV2) const [0x73, 0x41, 0x6C, 0x54],
    ]);
    final h = _md5(input);
    final len = fileKey.length + 5 < 16 ? fileKey.length + 5 : 16;
    return Uint8List.sublistView(h, 0, len);
  }

  Uint8List decrypt(Uint8List data, int number, int generation, CryptMethod method) {
    switch (method) {
      case CryptMethod.none:
        return data;
      case CryptMethod.rc4:
        return rc4(_objectKey(number, generation, method), data);
      case CryptMethod.aesV2:
      case CryptMethod.aesV3:
        if (data.length < 32) return Uint8List(0);
        return aesCbcDecrypt(_objectKey(number, generation, method), Uint8List.sublistView(data, 0, 16), Uint8List.sublistView(data, 16));
    }
  }
}

/// Adds AES 256 bit protection (revision 6) with one password for opening.
class PdfAes256Writer {
  PdfAes256Writer._(this._fileKey, this.encryptDict, this._random);

  final Uint8List _fileKey;
  final PdfDict encryptDict;
  final Random _random;

  /// Everything is allowed once the document is open, so the single password is both user and owner password.
  static const permissions = -4;

  static PdfAes256Writer create(String password, {Random? random}) {
    final rnd = random ?? Random.secure();
    Uint8List bytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) rnd.nextInt(256)]);
    final pwd = _modernPassword(password);
    final fileKey = bytes(32);
    final zeroIv = Uint8List(16);
    final empty = Uint8List(0);

    final uvs = bytes(8), uks = bytes(8);
    final u = _concat([pdfHashR56(6, pwd, uvs, empty), uvs, uks]);
    final ue = aesCbcEncrypt(pdfHashR56(6, pwd, uks, empty), zeroIv, fileKey, pad: false);

    final ovs = bytes(8), oks = bytes(8);
    final o = _concat([pdfHashR56(6, pwd, ovs, u), ovs, oks]);
    final oe = aesCbcEncrypt(pdfHashR56(6, pwd, oks, u), zeroIv, fileKey, pad: false);

    final perms = Uint8List.fromList([..._int32le(permissions & 0xFFFFFFFF), 0xFF, 0xFF, 0xFF, 0xFF, 0x54, 0x61, 0x64, 0x62, ...bytes(4)]);
    final permsEncrypted = aesCbcEncrypt(fileKey, zeroIv, perms, pad: false);

    final dict = PdfDict({
      'Filter': const PdfName('Standard'),
      'V': const PdfInt(5),
      'R': const PdfInt(6),
      'Length': const PdfInt(256),
      'P': const PdfInt(permissions),
      'O': PdfString(o),
      'U': PdfString(u),
      'OE': PdfString(oe),
      'UE': PdfString(ue),
      'Perms': PdfString(permsEncrypted),
      'EncryptMetadata': const PdfBool(true),
      'CF': PdfDict({
        'StdCF': PdfDict({'AuthEvent': const PdfName('DocOpen'), 'CFM': const PdfName('AESV3'), 'Length': const PdfInt(32)}),
      }),
      'StmF': const PdfName('StdCF'),
      'StrF': const PdfName('StdCF'),
    });
    return PdfAes256Writer._(fileKey, dict, rnd);
  }

  Uint8List encrypt(Uint8List data) {
    final iv = Uint8List.fromList([for (var i = 0; i < 16; i++) _random.nextInt(256)]);
    return _concat([iv, aesCbcEncrypt(_fileKey, iv, data)]);
  }
}

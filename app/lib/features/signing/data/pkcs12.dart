import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'der.dart';
import 'x509.dart';

class Pkcs12Exception implements Exception {
  const Pkcs12Exception(this.message);
  final String message;

  @override
  String toString() => message;
}

class WrongCertificatePasswordException extends Pkcs12Exception {
  const WrongCertificatePasswordException() : super('The password is not right.');
}

/// What a certificate file holds for signing: the private key and the certificate that goes with it.
class SigningCredentials {
  const SigningCredentials({required this.key, required this.certificate, required this.chain});
  final PrivateKeyInfo key;
  final Certificate certificate;

  /// The other certificates of the file (intermediate and root), to be sent along with the signature.
  final List<Certificate> chain;
}

const _oidData = '1.2.840.113549.1.7.1';
const _oidEncryptedData = '1.2.840.113549.1.7.6';
const _oidKeyBag = '1.2.840.113549.1.12.10.1.1';
const _oidShroudedKeyBag = '1.2.840.113549.1.12.10.1.2';
const _oidCertBag = '1.2.840.113549.1.12.10.1.3';
const _oidX509Cert = '1.2.840.113549.1.9.22.1';
const _oidPbes2 = '1.2.840.113549.1.5.13';
const _oidPbkdf2 = '1.2.840.113549.1.5.12';

pc.Digest _digestFor(String oid) => switch (oid) {
  '1.3.14.3.2.26' => pc.SHA1Digest(),
  '2.16.840.1.101.3.4.2.4' => pc.SHA224Digest(),
  '2.16.840.1.101.3.4.2.1' => pc.SHA256Digest(),
  '2.16.840.1.101.3.4.2.2' => pc.SHA384Digest(),
  '2.16.840.1.101.3.4.2.3' => pc.SHA512Digest(),
  _ => throw Pkcs12Exception('This certificate file uses a hash that is not supported ($oid).'),
};

pc.Digest _prfDigest(String oid) => switch (oid) {
  '1.2.840.113549.2.7' => pc.SHA1Digest(),
  '1.2.840.113549.2.8' => pc.SHA224Digest(),
  '1.2.840.113549.2.9' => pc.SHA256Digest(),
  '1.2.840.113549.2.10' => pc.SHA384Digest(),
  '1.2.840.113549.2.11' => pc.SHA512Digest(),
  _ => throw Pkcs12Exception('This certificate file uses a key function that is not supported ($oid).'),
};

Uint8List _bmp(String password, {bool terminator = true}) {
  final out = <int>[];
  for (final u in password.codeUnits) {
    out
      ..add(u >> 8)
      ..add(u & 0xFF);
  }
  if (terminator) out.addAll([0, 0]);
  return Uint8List.fromList(out);
}

/// The key derivation of RFC 7292 appendix B: [id] 1 makes keys, 2 makes IVs and 3 makes the MAC key.
Uint8List pkcs12Kdf(pc.Digest digest, Uint8List password, Uint8List salt, int iterations, int id, int n) {
  final u = digest.digestSize, v = digest.byteLength;
  Uint8List fill(Uint8List src) {
    if (src.isEmpty) return Uint8List(0);
    final len = v * ((src.length + v - 1) ~/ v);
    return Uint8List.fromList([for (var i = 0; i < len; i++) src[i % src.length]]);
  }

  final d = Uint8List(v)..fillRange(0, v, id);
  final i = Uint8List.fromList([...fill(salt), ...fill(password)]);
  final out = BytesBuilder();
  final blocks = (n + u - 1) ~/ u;
  for (var b = 0; b < blocks; b++) {
    var a = Uint8List.fromList([...d, ...i]);
    for (var r = 0; r < iterations; r++) {
      digest.reset();
      a = Uint8List.fromList(digest.process(a));
    }
    out.add(a);
    if (b + 1 == blocks) break;
    final bb = Uint8List.fromList([for (var k = 0; k < v; k++) a[k % u]]);
    for (var j = 0; j < i.length; j += v) {
      var carry = 1;
      for (var k = v - 1; k >= 0; k--) {
        final sum = i[j + k] + bb[k] + carry;
        i[j + k] = sum & 0xFF;
        carry = sum >> 8;
      }
    }
  }
  return Uint8List.fromList(out.toBytes().sublist(0, n));
}

Uint8List _cbcDecrypt(pc.BlockCipher engine, pc.CipherParameters key, Uint8List iv, Uint8List data) {
  final bs = engine.blockSize;
  if (data.isEmpty || data.length % bs != 0) throw const WrongCertificatePasswordException();
  final cbc = pc.CBCBlockCipher(engine)..init(false, pc.ParametersWithIV(key, iv));
  final out = Uint8List(data.length);
  for (var o = 0; o < data.length; o += bs) {
    cbc.processBlock(data, o, out, o);
  }
  final pad = out.last;
  if (pad < 1 || pad > bs || pad > out.length) throw const WrongCertificatePasswordException();
  for (var k = out.length - pad; k < out.length; k++) {
    if (out[k] != pad) throw const WrongCertificatePasswordException();
  }
  return Uint8List.sublistView(out, 0, out.length - pad);
}

/// Decrypts data protected by a password-based algorithm of PKCS#12 or PKCS#5 (version 2).
Uint8List _decrypt(Der algorithm, Uint8List data, String password, {required bool bmpTerminator}) {
  final oid = algorithm[0].oid;
  final params = algorithm.children.length > 1 ? algorithm[1] : null;
  if (oid == _oidPbes2) {
    final kdf = params![0];
    final scheme = params[1];
    if (kdf[0].oid != _oidPbkdf2) throw const Pkcs12Exception('This certificate file uses a key function that is not supported.');
    final k = kdf[1].children;
    final salt = Uint8List.fromList(k[0].value);
    final iterations = k[1].intValue;
    var next = 2;
    int? keyLength;
    if (next < k.length && k[next].tag == Der.integer) keyLength = k[next++].intValue;
    final prf = next < k.length ? _prfDigest(k[next][0].oid) : pc.SHA1Digest();
    final (name, size) = switch (scheme[0].oid) {
      '2.16.840.1.101.3.4.1.42' => ('AES', 32),
      '2.16.840.1.101.3.4.1.22' => ('AES', 24),
      '2.16.840.1.101.3.4.1.2' => ('AES', 16),
      '1.2.840.113549.3.7' => ('3DES', 24),
      _ => throw const Pkcs12Exception('This certificate file uses an encryption that is not supported.'),
    };
    final derived = pc.PBKDF2KeyDerivator(pc.HMac(prf, prf.byteLength))..init(pc.Pbkdf2Parameters(salt, iterations, keyLength ?? size));
    final key = derived.process(Uint8List.fromList(utf8.encode(password)));
    final iv = Uint8List.fromList(scheme[1].value);
    return name == 'AES' ? _cbcDecrypt(pc.AESEngine(), pc.KeyParameter(key), iv, data) : _cbcDecrypt(pc.DESedeEngine(), pc.KeyParameter(key), iv, data);
  }
  final (int keyBytes, int rc2Bits, bool triple) = switch (oid) {
    '1.2.840.113549.1.12.1.3' => (24, 0, true),
    '1.2.840.113549.1.12.1.4' => (16, 0, true),
    '1.2.840.113549.1.12.1.5' => (16, 128, false),
    '1.2.840.113549.1.12.1.6' => (5, 40, false),
    _ => throw Pkcs12Exception('This certificate file uses an encryption that is not supported ($oid).'),
  };
  final salt = Uint8List.fromList(params![0].value);
  final iterations = params[1].intValue;
  final pw = _bmp(password, terminator: bmpTerminator);
  final sha1 = pc.SHA1Digest();
  var key = pkcs12Kdf(sha1, pw, salt, iterations, 1, keyBytes);
  final iv = pkcs12Kdf(sha1, pw, salt, iterations, 2, 8);
  if (triple) {
    if (keyBytes == 16) key = Uint8List.fromList([...key, ...key.sublist(0, 8)]);
    return _cbcDecrypt(pc.DESedeEngine(), pc.KeyParameter(key), iv, data);
  }
  return _cbcDecrypt(pc.RC2Engine(), pc.RC2Parameters(key, bits: rc2Bits), iv, data);
}

bool _macMatches(Der pfx, Uint8List content, String password) {
  final mac = pfx[2];
  final info = mac[0];
  final digest = _digestFor(info[0][0].oid);
  final expected = info[1].value;
  final salt = Uint8List.fromList(mac[1].value);
  final iterations = mac.children.length > 2 ? mac[2].intValue : 1;
  // Some tools write an empty password as nothing at all, others as the end marker alone.
  for (final pw in <Uint8List>[_bmp(password), if (password.isEmpty) _bmp(password, terminator: false)]) {
    final key = pkcs12Kdf(digest, pw, salt, iterations, 3, digest.digestSize);
    final hmac = pc.HMac(_digestFor(info[0][0].oid), digest.byteLength)..init(pc.KeyParameter(key));
    final out = Uint8List(hmac.macSize);
    hmac.update(content, 0, content.length);
    hmac.doFinal(out, 0);
    if (out.length == expected.length && Iterable<int>.generate(out.length).every((i) => out[i] == expected[i])) return true;
  }
  return false;
}

/// Opens a .p12 or .pfx file. Throws [WrongCertificatePasswordException] for a wrong password and [Pkcs12Exception] for what cannot be read.
SigningCredentials readPkcs12(Uint8List bytes, String password) {
  try {
    return _read(bytes, password);
  } on Pkcs12Exception {
    rethrow;
  } on FormatException {
    throw const Pkcs12Exception('This file is not a certificate file Doculoom can read.');
  } on RangeError {
    throw const Pkcs12Exception('This file is not a certificate file Doculoom can read.');
  } on StateError {
    throw const Pkcs12Exception('This file is not a certificate file Doculoom can read.');
  }
}

SigningCredentials _read(Uint8List bytes, String password) {
  final pfx = Der.parse(bytes);
  if (pfx.tag != Der.sequence || pfx.children.length < 2) throw const Pkcs12Exception('This file is not a certificate file Doculoom can read.');
  final authSafe = pfx[1];
  if (authSafe[0].oid != _oidData) throw const Pkcs12Exception('This certificate file is signed with a public key and not a password, which is not supported.');
  final contentHolder = authSafe[1][0];
  final content = contentHolder.constructed
      ? Uint8List.fromList([for (final c in contentHolder.children) ...c.value])
      : Uint8List.fromList(contentHolder.value);
  if (pfx.children.length > 2 && !_macMatches(pfx, content, password)) throw const WrongCertificatePasswordException();

  final bags = <Der>[];
  Uint8List? keyBytes;
  final certs = <Certificate>[];
  // Some old files write an empty password as nothing, others as the end marker; both are tried.
  final terminators = password.isEmpty ? [true, false] : [true];
  for (final terminator in terminators) {
    try {
      bags.clear();
      for (final info in Der.parse(content).children) {
        final type = info[0].oid;
        if (type == _oidData) {
          bags.addAll(Der.parse(Uint8List.fromList(info[1][0].value)).children);
        } else if (type == _oidEncryptedData) {
          final enc = info[1][0][1];
          final alg = enc[1];
          final cipherText = enc[2];
          final data = cipherText.constructed ? Uint8List.fromList([for (final c in cipherText.children) ...c.value]) : Uint8List.fromList(cipherText.value);
          bags.addAll(Der.parse(_decrypt(alg, data, password, bmpTerminator: terminator)).children);
        }
      }
      for (final bag in bags) {
        final id = bag[0].oid;
        final value = bag[1][0];
        if (id == _oidKeyBag) {
          keyBytes = Uint8List.fromList(value.encoded);
        } else if (id == _oidShroudedKeyBag) {
          keyBytes = _decrypt(value[0], Uint8List.fromList(value[1].value), password, bmpTerminator: terminator);
        } else if (id == _oidCertBag && value[0].oid == _oidX509Cert) {
          certs.add(Certificate.parse(Uint8List.fromList(value[1][0].value)));
        }
      }
      break;
    } on WrongCertificatePasswordException {
      if (terminator == terminators.last) rethrow;
      certs.clear();
      keyBytes = null;
    }
  }
  if (keyBytes == null) throw const Pkcs12Exception('This certificate file has no private key, so it cannot sign.');
  final key = PrivateKeyInfo.parsePkcs8(keyBytes);
  final leaf = certs.where(key.matches).firstOrNull;
  if (leaf == null) throw const Pkcs12Exception('The certificate in this file does not belong to its private key.');
  final others = [
    for (final c in certs)
      if (!_same(c.der, leaf.der)) c,
  ];
  return SigningCredentials(key: key, certificate: leaf, chain: others);
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

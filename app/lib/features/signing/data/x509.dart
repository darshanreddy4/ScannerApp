import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'der.dart';

const oidRsa = '1.2.840.113549.1.1.1';
const oidEcPublicKey = '1.2.840.10045.2.1';
const oidP256 = '1.2.840.10045.3.1.7';
const oidP384 = '1.3.132.0.34';

const _nameLabels = {
  '2.5.4.3': 'CN',
  '2.5.4.4': 'SN',
  '2.5.4.5': 'serialNumber',
  '2.5.4.6': 'C',
  '2.5.4.7': 'L',
  '2.5.4.8': 'ST',
  '2.5.4.10': 'O',
  '2.5.4.11': 'OU',
  '2.5.4.42': 'GN',
  '1.2.840.113549.1.9.1': 'E',
};

class DistinguishedName {
  const DistinguishedName(this.der, this.parts);
  final Uint8List der;
  final List<(String, String)> parts;

  String _first(String label) => parts.where((p) => p.$1 == label).map((p) => p.$2).firstOrNull ?? '';

  /// The name to show: the common name, else the organisation.
  String get display {
    final cn = _first('CN');
    if (cn.isNotEmpty) return cn;
    final o = _first('O');
    return o.isNotEmpty ? o : toString();
  }

  String get organisation => _first('O');
  String get country => _first('C');

  @override
  String toString() => parts.map((p) => '${p.$1}=${p.$2}').join(', ');
}

DistinguishedName parseName(Der name) {
  final parts = <(String, String)>[];
  for (final rdn in name.children) {
    for (final atv in rdn.children) {
      final oid = atv[0].oid;
      parts.add((_nameLabels[oid] ?? oid, atv[1].text));
    }
  }
  return DistinguishedName(Uint8List.fromList(name.encoded), parts);
}

/// A public key: RSA modulus and exponent, or a point on a named curve.
class PublicKeyInfo {
  const PublicKeyInfo.rsa(this.modulus, this.exponent) : curve = null, point = null;
  const PublicKeyInfo.ec(this.curve, this.point) : modulus = null, exponent = null;

  final BigInt? modulus;
  final BigInt? exponent;

  /// The curve's OID.
  final String? curve;

  /// The point in its uncompressed form (04 || x || y).
  final Uint8List? point;

  bool get isRsa => modulus != null;
  String get description => isRsa ? 'RSA ${modulus!.bitLength} bit' : (curve == oidP256 ? 'ECDSA P-256' : (curve == oidP384 ? 'ECDSA P-384' : 'ECDSA'));
}

/// The parts of an X.509 certificate that signing and checking need.
class Certificate {
  Certificate._({
    required this.der,
    required this.tbs,
    required this.serial,
    required this.issuer,
    required this.subject,
    required this.notBefore,
    required this.notAfter,
    required this.publicKey,
  });

  final Uint8List der;
  final Uint8List tbs;

  /// The serial number as the encoded INTEGER, ready to be copied into a signature.
  final Uint8List serial;
  final DistinguishedName issuer;
  final DistinguishedName subject;
  final DateTime notBefore;
  final DateTime notAfter;
  final PublicKeyInfo publicKey;

  bool get selfSigned => _bytesEqual(issuer.der, subject.der);

  bool validAt(DateTime t) => !t.toUtc().isBefore(notBefore) && !t.toUtc().isAfter(notAfter);

  static Certificate parse(Uint8List bytes) {
    final cert = Der.parse(bytes);
    final tbs = cert[0];
    var i = 0;
    final first = tbs[0];
    if (first.isContext(0)) i = 1;
    final c = tbs.children;
    final spki = c[i + 5];
    final alg = spki[0];
    final keyBits = spki[1].bits;
    final PublicKeyInfo key;
    if (alg[0].oid == oidRsa) {
      final seq = Der.parse(Uint8List.fromList(keyBits));
      key = PublicKeyInfo.rsa(seq[0].integerValue, seq[1].integerValue);
    } else if (alg[0].oid == oidEcPublicKey) {
      key = PublicKeyInfo.ec(alg.children.length > 1 ? alg[1].oid : '', Uint8List.fromList(keyBits));
    } else {
      throw FormatException('Unsupported key type ${alg[0].oid}');
    }
    return Certificate._(
      der: Uint8List.fromList(cert.encoded),
      tbs: Uint8List.fromList(tbs.encoded),
      serial: Uint8List.fromList(c[i].encoded),
      issuer: parseName(c[i + 2]),
      subject: parseName(c[i + 4]),
      notBefore: c[i + 3][0].time,
      notAfter: c[i + 3][1].time,
      publicKey: key,
    );
  }
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A private key with what is needed to sign: RSA, or ECDSA on P-256 or P-384.
class PrivateKeyInfo {
  const PrivateKeyInfo.rsa(this.rsa) : ecD = null, curve = null;
  const PrivateKeyInfo.ec(this.ecD, this.curve) : rsa = null;

  final pc.RSAPrivateKey? rsa;
  final BigInt? ecD;
  final String? curve;

  bool get isRsa => rsa != null;

  /// True when this key belongs to the public key of [cert].
  bool matches(Certificate cert) {
    final pub = cert.publicKey;
    if (isRsa) return pub.isRsa && pub.modulus == rsa!.modulus;
    if (pub.isRsa) return false;
    final params = pc.ECDomainParameters(curve == oidP384 ? 'secp384r1' : 'prime256v1');
    final q = params.G * ecD!;
    return q != null && _bytesEqual(q.getEncoded(false), pub.point!);
  }

  /// Reads a PKCS#8 PrivateKeyInfo.
  static PrivateKeyInfo parsePkcs8(Uint8List bytes) {
    final info = Der.parse(bytes);
    final alg = info[1];
    final inner = Der.parse(Uint8List.fromList(info[2].value));
    if (alg[0].oid == oidRsa) {
      final c = inner.children;
      return PrivateKeyInfo.rsa(pc.RSAPrivateKey(c[1].integerValue, c[3].integerValue, c[4].integerValue, c[5].integerValue));
    }
    if (alg[0].oid == oidEcPublicKey) {
      final d = bytesToBigInt(inner[1].value);
      return PrivateKeyInfo.ec(d, alg[1].oid);
    }
    throw FormatException('Unsupported key type ${alg[0].oid}');
  }
}

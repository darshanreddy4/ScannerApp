import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

import 'der.dart';
import 'pkcs12.dart';
import 'x509.dart';

const oidSha1 = '1.3.14.3.2.26';
const oidSha256 = '2.16.840.1.101.3.4.2.1';
const oidSha384 = '2.16.840.1.101.3.4.2.2';
const oidSha512 = '2.16.840.1.101.3.4.2.3';

const _oidData = '1.2.840.113549.1.7.1';
const _oidSignedData = '1.2.840.113549.1.7.2';
const _oidContentType = '1.2.840.113549.1.9.3';
const _oidMessageDigest = '1.2.840.113549.1.9.4';
const _oidSigningTime = '1.2.840.113549.1.9.5';
const _oidSigningCertV2 = '1.2.840.113549.1.9.16.2.47';

pc.Digest digestFor(String oid) => switch (oid) {
  oidSha1 => pc.SHA1Digest(),
  oidSha256 => pc.SHA256Digest(),
  oidSha384 => pc.SHA384Digest(),
  oidSha512 => pc.SHA512Digest(),
  _ => throw FormatException('Unsupported hash $oid'),
};

String hashName(String oid) => switch (oid) {
  oidSha1 => 'SHA-1',
  oidSha256 => 'SHA-256',
  oidSha384 => 'SHA-384',
  oidSha512 => 'SHA-512',
  _ => oid,
};

String _rsaDigestId(String hashOid) => switch (hashOid) {
  oidSha1 => '06052b0e03021a',
  oidSha256 => '0609608648016503040201',
  oidSha384 => '0609608648016503040202',
  _ => '0609608648016503040203',
};

/// The hash of the pieces joined one after the other.
Uint8List hashParts(String hashOid, Iterable<Uint8List> parts) {
  final d = digestFor(hashOid)..reset();
  for (final p in parts) {
    d.update(p, 0, p.length);
  }
  final out = Uint8List(d.digestSize);
  d.doFinal(out, 0);
  return out;
}

/// The hash that goes with a key: SHA-384 for a P-384 key, SHA-256 otherwise.
String hashOidFor(PrivateKeyInfo key) => !key.isRsa && key.curve == oidP384 ? oidSha384 : oidSha256;

pc.SecureRandom _random() {
  final rng = pc.FortunaRandom();
  final seed = Random.secure();
  rng.seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256)))));
  return rng;
}

pc.ECDomainParameters _curve(String oid) => pc.ECDomainParameters(oid == oidP384 ? 'secp384r1' : 'prime256v1');

Uint8List _signValue(PrivateKeyInfo key, String hashOid, Uint8List data) {
  if (key.isRsa) {
    final signer = pc.RSASigner(digestFor(hashOid), _rsaDigestId(hashOid))..init(true, pc.PrivateKeyParameter<pc.RSAPrivateKey>(key.rsa!));
    return signer.generateSignature(data).bytes;
  }
  final domain = _curve(key.curve!);
  final signer = pc.ECDSASigner(digestFor(hashOid))
    ..init(true, pc.ParametersWithRandom(pc.PrivateKeyParameter<pc.ECPrivateKey>(pc.ECPrivateKey(key.ecD, domain)), _random()));
  final sig = signer.generateSignature(data) as pc.ECSignature;
  return derSequence([derInteger(sig.r), derInteger(sig.s)]);
}

bool _verifyValue(PublicKeyInfo key, String hashOid, Uint8List data, Uint8List signature) {
  try {
    if (key.isRsa) {
      final signer = pc.RSASigner(digestFor(hashOid), _rsaDigestId(hashOid))
        ..init(false, pc.PublicKeyParameter<pc.RSAPublicKey>(pc.RSAPublicKey(key.modulus!, key.exponent!)));
      return signer.verifySignature(data, pc.RSASignature(signature));
    }
    final domain = _curve(key.curve!);
    final q = domain.curve.decodePoint(key.point!);
    final der = Der.parse(signature);
    final signer = pc.ECDSASigner(digestFor(hashOid))..init(false, pc.PublicKeyParameter<pc.ECPublicKey>(pc.ECPublicKey(q, domain)));
    return signer.verifySignature(data, pc.ECSignature(der[0].integerValue, der[1].integerValue));
  } on Object {
    return false;
  }
}

Uint8List _attribute(String oid, Uint8List value) => derSequence([
  derOid(oid),
  derSet([value]),
]);

/// A detached CMS signature (CAdES) over [content], the bytes of the signed ranges of a PDF, in the pieces they come in.
/// The certificate and its chain travel with it; the signing certificate is also named in a signed attribute, as PAdES asks.
Uint8List createCadesSignature(Iterable<Uint8List> content, SigningCredentials cred, {DateTime? time}) {
  final hashOid = hashOidFor(cred.key);
  final digest = hashParts(hashOid, content);
  final leaf = cred.certificate;
  final certHash = hashParts(oidSha256, [leaf.der]);
  final essCert = derSequence([
    derOctets(certHash),
    derSequence([
      derSequence([derContext(4, leaf.issuer.der)]),
      leaf.serial,
    ]),
  ]);
  final attrs = [
    _attribute(_oidContentType, derOid(_oidData)),
    _attribute(_oidSigningTime, derUtcTime(time ?? DateTime.now())),
    _attribute(_oidMessageDigest, derOctets(digest)),
    _attribute(
      _oidSigningCertV2,
      derSequence([
        derSequence([essCert]),
      ]),
    ),
  ];
  final signedAttrs = derSetOf(attrs);
  final signature = _signValue(cred.key, hashOid, signedAttrs);
  final sigAlg = cred.key.isRsa
      ? derAlgorithm('1.2.840.113549.1.1.11')
      : derAlgorithm(hashOid == oidSha384 ? '1.2.840.10045.4.3.3' : '1.2.840.10045.4.3.2', noParameters: true);
  final signerInfo = derSequence([
    derInt(1),
    derSequence([leaf.issuer.der, leaf.serial]),
    derAlgorithm(hashOid),
    // The attributes are signed as a SET OF and sent with the context tag [0].
    derContext(0, Der.parse(signedAttrs).value),
    sigAlg,
    derOctets(signature),
  ]);
  final signedData = derSequence([
    derInt(1),
    derSet([derAlgorithm(hashOid)]),
    derSequence([derOid(_oidData)]),
    derContext(0, [
      for (final c in [leaf, ...cred.chain]) ...c.der,
    ]),
    derSet([signerInfo]),
  ]);
  return derSequence([derOid(_oidSignedData), derContext(0, signedData)]);
}

class CmsSignature {
  CmsSignature._({
    required this.hashOid,
    required this.signatureAlgorithm,
    required this.signature,
    required this.certificates,
    required this.signerCandidates,
    required this.signedAttributes,
    required this.messageDigest,
    required this.signingTime,
    required this.length,
  });

  final String hashOid;
  final String signatureAlgorithm;
  final Uint8List signature;
  final List<Certificate> certificates;

  /// The certificates that could be the signer's: the one the signature names, or all of them.
  final List<Certificate> signerCandidates;

  /// The signed attributes as a SET OF (what the signature covers); null when the signature covers the content directly.
  final Uint8List? signedAttributes;
  final Uint8List? messageDigest;
  final DateTime? signingTime;

  /// How many bytes the structure takes, so zero padding after it can be ignored.
  final int length;

  static CmsSignature parse(Uint8List bytes) {
    final info = Der.parse(bytes);
    if (info[0].oid != _oidSignedData) throw const FormatException('Not a CMS signature');
    final sd = info[1][0];
    final children = sd.children;
    final certs = <Certificate>[];
    for (final c in children) {
      if (c.isContext(0)) {
        for (final cert in c.children) {
          try {
            certs.add(Certificate.parse(Uint8List.fromList(cert.encoded)));
          } on Object {
            // A certificate kind that is not understood is skipped.
          }
        }
      }
    }
    final signerInfo = children.lastWhere((c) => c.tag == Der.set)[0];
    final si = signerInfo.children;
    final sid = si[1];
    var i = 2;
    final hashOid = si[i++][0].oid;
    Der? attrs;
    if (si[i].isContext(0)) attrs = si[i++];
    final sigAlg = si[i++][0].oid;
    final signature = Uint8List.fromList(si[i].value);
    Uint8List? messageDigest;
    DateTime? signingTime;
    Uint8List? signedAttributes;
    if (attrs != null) {
      signedAttributes = der(Der.set, attrs.value);
      for (final a in attrs.children) {
        final value = a[1][0];
        if (a[0].oid == _oidMessageDigest) messageDigest = Uint8List.fromList(value.value);
        if (a[0].oid == _oidSigningTime) signingTime = value.time;
      }
    }
    var candidates = certs;
    if (sid.tag == Der.sequence) {
      final named = certs.where((c) => _same(c.issuer.der, sid[0].encoded) && _same(c.serial, sid[1].encoded)).toList();
      if (named.isNotEmpty) candidates = named;
    }
    return CmsSignature._(
      hashOid: hashOid,
      signatureAlgorithm: sigAlg,
      signature: signature,
      certificates: certs,
      signerCandidates: candidates,
      signedAttributes: signedAttributes,
      messageDigest: messageDigest,
      signingTime: signingTime,
      length: info.endOffset,
    );
  }

  /// Checks the signature against the signed bytes. [digestMatches] says whether the content is the one that was signed;
  /// [signatureValid] says whether the signature itself is genuine for the certificate; [signer] is the certificate that checked out.
  ({bool digestMatches, bool signatureValid, Certificate? signer}) verify(Iterable<Uint8List> content) {
    if (signatureAlgorithm == '1.2.840.113549.1.1.10') throw const FormatException('RSA-PSS is not supported');
    final digest = hashParts(hashOid, content);
    final attrs = signedAttributes;
    final digestMatches = attrs == null ? true : (messageDigest != null && _same(messageDigest!, digest));
    final parts = content.toList();
    final signed = attrs ?? Uint8List.fromList([for (final p in parts) ...p]);
    for (final cert in signerCandidates) {
      if (_verifyValue(cert.publicKey, hashOid, signed, signature)) return (digestMatches: digestMatches, signatureValid: true, signer: cert);
    }
    return (digestMatches: digestMatches, signatureValid: false, signer: signerCandidates.firstOrNull);
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../pdf_tools/data/security/pdf_model.dart';
import '../../pdf_tools/data/security/pdf_rewriter.dart';
import 'cms.dart';
import 'pkcs12.dart';
import 'x509.dart';

class SigningException implements Exception {
  const SigningException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Where the signature box goes on the page.
enum SignaturePosition { bottomRight, bottomLeft, bottomCenter, topRight, topLeft }

/// How the signature looks and what it says.
class PdfSignOptions {
  const PdfSignOptions({
    this.pageIndex = -1,
    this.visible = true,
    this.position = SignaturePosition.bottomRight,
    this.reason = '',
    this.location = '',
    this.signerName,
  });

  /// Zero-based; a negative number counts from the end (-1 is the last page).
  final int pageIndex;

  /// A box on the page showing who signed and when. Off: the signature is there but has no mark on the page.
  final bool visible;
  final SignaturePosition position;
  final String reason;
  final String location;

  /// The name written in the signature; the certificate's own name when null.
  final String? signerName;
}

/// How many bytes are kept free for the signature. A certificate with a long chain needs more.
const signatureReserve = 16384;

String _escapeName(String name) {
  final b = StringBuffer('/');
  for (final c in latin1.encode(name)) {
    final regular = c > 0x20 && c < 0x7F && c != 0x23 && !isPdfDelimiter(c);
    b.write(regular ? String.fromCharCode(c) : '#${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
  }
  return b.toString();
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String _serialize(PdfObj o) => switch (o) {
  PdfNull() => 'null',
  PdfBool(:final value) => value ? 'true' : 'false',
  PdfInt(:final value) => '$value',
  PdfReal(:final text) => text,
  PdfName(:final name) => _escapeName(name),
  PdfString(:final bytes) => '<${_hex(bytes)}>',
  PdfArray(:final items) => '[${items.map(_serialize).join(' ')}]',
  PdfDict(:final entries) => '<<${entries.entries.map((e) => '${_escapeName(e.key)} ${_serialize(e.value)}').join(' ')}>>',
  PdfRef(:final number, :final generation) => '$number $generation R',
  PdfStream() => throw const SigningException('This PDF has an object that cannot be updated in place.'),
};

/// A text string for a PDF: UTF-16 with a byte order mark, written in hex.
String _textString(String s) {
  final units = <int>[0xFE, 0xFF];
  for (final u in s.codeUnits) {
    units
      ..add(u >> 8)
      ..add(u & 0xFF);
  }
  return '<${_hex(units)}>';
}

String _pdfDate(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'D:${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// A text for the page content in WinAnsi: letters outside it become a question mark.
String _literal(String s) {
  final b = StringBuffer('(');
  for (final c in s.codeUnits) {
    final ch = c < 256 ? c : 0x3F;
    if (ch == 0x28 || ch == 0x29 || ch == 0x5C) {
      b.write('\\');
      b.writeCharCode(ch);
    } else if (ch < 0x20 || ch > 0x7E) {
      b.write('\\${ch.toRadixString(8).padLeft(3, '0')}');
    } else {
      b.writeCharCode(ch);
    }
  }
  b.write(')');
  return b.toString();
}

class _Page {
  _Page(this.number, this.dict, this.box);
  final int number;
  final PdfDict dict;
  final List<double> box;
}

double? _num(PdfObj? o) => switch (o) {
  PdfInt(:final value) => value.toDouble(),
  PdfReal(:final text) => double.tryParse(text),
  _ => null,
};

List<_Page> _pages(PdfDoc doc, PdfDict catalog) {
  PdfObj? resolve(PdfObj? o) => o is PdfRef ? doc.objects[o.number] : o;
  final out = <_Page>[];
  final seen = <int>{};
  void walk(PdfObj? ref, List<double>? inherited) {
    if (ref is! PdfRef || !seen.add(ref.number)) return;
    final node = doc.objects[ref.number];
    if (node is! PdfDict) return;
    var box = inherited;
    final mb = resolve(node['MediaBox']);
    if (mb is PdfArray && mb.items.length == 4) {
      final v = [for (final i in mb.items) _num(resolve(i)) ?? 0.0];
      box = [math.min(v[0], v[2]), math.min(v[1], v[3]), math.max(v[0], v[2]), math.max(v[1], v[3])];
    }
    final kids = resolve(node['Kids']);
    if (kids is PdfArray) {
      for (final k in kids.items) {
        walk(k, box);
      }
    } else {
      out.add(_Page(ref.number, node, box ?? const [0, 0, 612, 792]));
    }
  }

  walk(catalog['Pages'], null);
  return out;
}

/// How many pages the PDF has; 0 when it cannot be read or is password protected.
int pdfPageCount(Uint8List pdf) {
  try {
    if (inspectPdf(pdf).encrypted) return 0;
    final doc = readPdfDocument(pdf);
    final root = doc.trailer['Root'];
    if (root is! PdfRef) return 0;
    final catalog = doc.objects[root.number];
    return catalog is PdfDict ? _pages(doc, catalog).length : 0;
  } on Object {
    return 0;
  }
}

int _lastStartXref(Uint8List pdf) {
  final tail = latin1.decode(pdf.sublist(math.max(0, pdf.length - 2048)), allowInvalid: true);
  final i = tail.lastIndexOf('startxref');
  if (i < 0) throw const SigningException('This PDF has no cross-reference table and cannot be signed.');
  final m = RegExp(r'startxref\s+(\d+)').firstMatch(tail.substring(i));
  if (m == null) throw const SigningException('This PDF has no cross-reference table and cannot be signed.');
  return int.parse(m[1]!);
}

bool _xrefIsStream(Uint8List pdf, int offset) {
  var p = offset;
  while (p < pdf.length && isPdfWhitespace(pdf[p])) {
    p++;
  }
  return !(p + 4 <= pdf.length && latin1.decode(pdf.sublist(p, p + 4), allowInvalid: true) == 'xref');
}

/// Adds a certificate signature (PAdES, CAdES detached) to the PDF as an update at the end of the file, so what was there before is untouched.
/// Throws [SigningException] for a PDF that cannot be signed this way.
Uint8List signPdf(Uint8List pdf, SigningCredentials cred, {PdfSignOptions options = const PdfSignOptions(), DateTime? now}) {
  final PdfProtectionInfo prot;
  final PdfDoc doc;
  final PdfScan scan;
  try {
    prot = inspectPdf(pdf);
    if (prot.encrypted) throw const SigningException('This PDF is password protected. Unlock it first, then sign it.');
    doc = readPdfDocument(pdf);
    scan = scanPdf(pdf);
  } on PdfFormatException {
    throw const SigningException('This PDF could not be read.');
  }
  final time = now ?? DateTime.now();
  final rootRef = doc.trailer['Root'];
  if (rootRef is! PdfRef || doc.objects[rootRef.number] is! PdfDict) throw const SigningException('This PDF has no document catalog.');
  final catalog = doc.objects[rootRef.number]! as PdfDict;
  final pages = _pages(doc, catalog);
  if (pages.isEmpty) throw const SigningException('This PDF has no pages.');
  final index = options.pageIndex < 0 ? pages.length + options.pageIndex : options.pageIndex;
  if (index < 0 || index >= pages.length) throw const SigningException('That page is not in the PDF.');
  final page = pages[index];

  PdfObj? resolve(PdfObj? o) => o is PdfRef ? doc.objects[o.number] : o;
  var maxNumber = 0;
  for (final k in doc.objects.keys) {
    maxNumber = math.max(maxNumber, k);
  }
  for (final e in scan.entries) {
    maxNumber = math.max(maxNumber, e.number);
  }
  final prev = _lastStartXref(pdf);
  final streamXref = _xrefIsStream(pdf, prev);
  final sigNumber = ++maxNumber;
  final widgetNumber = ++maxNumber;
  final apNumber = options.visible ? ++maxNumber : 0;
  final xrefNumber = streamXref ? ++maxNumber : 0;

  // What is signed: how many signatures there already are, for a field name that is new.
  final existing = doc.objects.values.where((o) => o is PdfDict && o.nameOf('FT') == 'Sig').length;
  final fieldName = 'Signature${existing + 1}';

  final updates = <int, String>{};
  final widgetRef = PdfRef(widgetNumber, 0);

  // The page gets the signature box in its annotations.
  final pageDict = PdfDict(Map.of(page.dict.entries));
  final annots = pageDict['Annots'];
  if (annots is PdfRef) {
    final arr = resolve(annots);
    if (arr is! PdfArray) throw const SigningException('This PDF has page notes in an unusual form and cannot be signed.');
    updates[annots.number] = _serialize(PdfArray([...arr.items, widgetRef]));
  } else if (annots is PdfArray) {
    pageDict['Annots'] = PdfArray([...annots.items, widgetRef]);
  } else {
    pageDict['Annots'] = PdfArray([widgetRef]);
  }
  updates[page.number] = _serialize(pageDict);

  // The document gets a signature field in its form.
  final catalogCopy = PdfDict(Map.of(catalog.entries));
  final acro = catalogCopy['AcroForm'];
  final acroDict = resolve(acro);
  if (acroDict is PdfDict) {
    final copy = PdfDict(Map.of(acroDict.entries));
    final fields = copy['Fields'];
    if (fields is PdfRef) {
      final arr = resolve(fields);
      if (arr is! PdfArray) throw const SigningException('This PDF has a form in an unusual shape and cannot be signed.');
      updates[fields.number] = _serialize(PdfArray([...arr.items, widgetRef]));
    } else {
      copy['Fields'] = PdfArray([if (fields is PdfArray) ...fields.items, widgetRef]);
    }
    copy['SigFlags'] = PdfInt((acroDict.intOf('SigFlags') ?? 0) | 3);
    if (acro is PdfRef) {
      updates[acro.number] = _serialize(copy);
    } else {
      catalogCopy['AcroForm'] = copy;
    }
  } else {
    catalogCopy['AcroForm'] = PdfDict({
      'Fields': PdfArray([widgetRef]),
      'SigFlags': const PdfInt(3),
    });
  }
  updates[rootRef.number] = _serialize(catalogCopy);

  // The box on the page.
  final signerName = options.signerName ?? cred.certificate.subject.display;
  var rect = [0.0, 0.0, 0.0, 0.0];
  String? appearance;
  if (options.visible) {
    const w = 190.0, h = 56.0, margin = 36.0;
    final b = page.box;
    final left = switch (options.position) {
      SignaturePosition.bottomLeft || SignaturePosition.topLeft => b[0] + margin,
      SignaturePosition.bottomCenter => (b[0] + b[2] - w) / 2,
      _ => b[2] - margin - w,
    };
    final bottom = switch (options.position) {
      SignaturePosition.topLeft || SignaturePosition.topRight => b[3] - margin - h,
      _ => b[1] + margin,
    };
    rect = [left, bottom, left + w, bottom + h];
    final lines = [
      'Digitally signed by',
      signerName,
      'Date: ${time.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ')} UTC',
      if (options.reason.isNotEmpty) options.reason,
    ];
    final content = StringBuffer()
      ..writeln('q 0.95 0.97 1 rg 0 0 $w $h re f 0.11 0.31 0.85 RG 1 w 0.5 0.5 ${w - 1} ${h - 1} re S Q')
      ..writeln('BT /F1 8 Tf 0.1 g 5 ${h - 12} Td 10 TL');
    for (final (i, l) in lines.indexed) {
      content.writeln('${_literal(l.length > 44 ? l.substring(0, 44) : l)} ${i == 0 ? '' : "'"}${i == 0 ? 'Tj' : ''}'.trim());
    }
    content.writeln('ET');
    final data = latin1.encode(content.toString());
    appearance =
        '<</Type /XObject /Subtype /Form /BBox [0 0 $w $h] /Resources <</Font <</F1 <</Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding>>>>>> /Length ${data.length}>>\nstream\n${latin1.decode(data)}\nendstream';
  }
  updates[widgetNumber] = _serialize(
    PdfDict({
      'Type': const PdfName('Annot'),
      'Subtype': const PdfName('Widget'),
      'FT': const PdfName('Sig'),
      'T': PdfString(Uint8List.fromList(latin1.encode(fieldName))),
      'V': PdfRef(sigNumber, 0),
      'Rect': PdfArray([for (final v in rect) PdfReal(v.toStringAsFixed(2))]),
      'F': const PdfInt(132),
      'P': PdfRef(page.number, 0),
      if (apNumber != 0) 'AP': PdfDict({'N': PdfRef(apNumber, 0)}),
    }),
  );
  if (appearance != null) updates[apNumber] = appearance;

  // The file so far, then the changed objects, then the new cross-reference section.
  final out = BytesBuilder(copy: false)..add(pdf);
  if (pdf.isNotEmpty && pdf.last != 0x0A && pdf.last != 0x0D) out.addByte(0x0A);
  final offsets = <int, int>{};
  void write(String s) => out.add(latin1.encode(s));
  void writeObject(int number, String body) {
    offsets[number] = out.length;
    write('$number 0 obj\n$body\nendobj\n');
  }

  for (final e in updates.entries.where((e) => e.key != sigNumber)) {
    writeObject(e.key, e.value);
  }

  // The signature itself, with room for the signature and for the byte ranges that are filled in last.
  offsets[sigNumber] = out.length;
  final byteRangeMark = <int>[];
  final contentsMark = <int>[];
  write('$sigNumber 0 obj\n<</Type /Sig /Filter /Adobe.PPKLite /SubFilter /ETSI.CAdES.detached /ByteRange [');
  byteRangeMark.add(out.length);
  write('0 0000000000 0000000000 0000000000]');
  write(' /Contents ');
  contentsMark.add(out.length);
  write('<${'0' * (signatureReserve * 2)}>');
  write(' /M (${_pdfDate(time)}) /Name ${_textString(signerName)}');
  if (options.reason.isNotEmpty) write(' /Reason ${_textString(options.reason)}');
  if (options.location.isNotEmpty) write(' /Location ${_textString(options.location)}');
  write('>>\nendobj\n');

  final trailerExtra = StringBuffer();
  final info = doc.trailer['Info'];
  if (info != null) trailerExtra.write(' /Info ${_serialize(info)}');
  final id = doc.trailer['ID'];
  if (id != null) trailerExtra.write(' /ID ${_serialize(id)}');
  final size = maxNumber + 1;
  final numbers = (offsets.keys.toList()..sort());

  if (streamXref) {
    final xrefOffset = out.length;
    offsets[xrefNumber] = xrefOffset;
    final all = (offsets.keys.toList()..sort());
    final index = StringBuffer();
    for (var i = 0; i < all.length;) {
      var j = i;
      while (j + 1 < all.length && all[j + 1] == all[j] + 1) {
        j++;
      }
      index.write('${all[i]} ${j - i + 1} ');
      i = j + 1;
    }
    final data = BytesBuilder();
    for (final n in all) {
      final o = offsets[n]!;
      data
        ..addByte(1)
        ..add([o >> 24 & 0xFF, o >> 16 & 0xFF, o >> 8 & 0xFF, o & 0xFF])
        ..add([0, 0]);
    }
    final bytes = data.toBytes();
    write(
      '$xrefNumber 0 obj\n<</Type /XRef /Size $size /W [1 4 2] /Index [${index.toString().trim()}] /Root ${rootRef.number} ${rootRef.generation} R /Prev $prev$trailerExtra /Length ${bytes.length}>>\nstream\n',
    );
    out.add(bytes);
    write('\nendstream\nendobj\nstartxref\n$xrefOffset\n%%EOF\n');
  } else {
    final xrefOffset = out.length;
    write('xref\n');
    for (var i = 0; i < numbers.length;) {
      var j = i;
      while (j + 1 < numbers.length && numbers[j + 1] == numbers[j] + 1) {
        j++;
      }
      write('${numbers[i]} ${j - i + 1}\n');
      for (var k = i; k <= j; k++) {
        write('${offsets[numbers[k]]!.toString().padLeft(10, '0')} 00000 n \n');
      }
      i = j + 1;
    }
    write('trailer\n<</Size $size /Root ${rootRef.number} ${rootRef.generation} R /Prev $prev$trailerExtra>>\nstartxref\n$xrefOffset\n%%EOF\n');
  }

  final file = out.toBytes();
  final contentsStart = contentsMark.first; // at "<"
  final contentsEnd = contentsStart + 2 + signatureReserve * 2;
  final range =
      '0 ${contentsStart.toString().padLeft(10, '0')} ${contentsEnd.toString().padLeft(10, '0')} ${(file.length - contentsEnd).toString().padLeft(10, '0')}]';
  file.setRange(byteRangeMark.first, byteRangeMark.first + range.length, latin1.encode(range));
  final signature = createCadesSignature([Uint8List.sublistView(file, 0, contentsStart), Uint8List.sublistView(file, contentsEnd)], cred, time: time);
  if (signature.length > signatureReserve) throw const SigningException('The certificate and its chain are too large to fit in a signature.');
  file.setRange(contentsStart + 1, contentsStart + 1 + signature.length * 2, latin1.encode(_hex(signature)));
  return file;
}

enum SignatureState {
  /// The signature is genuine and the whole file is as it was signed.
  valid,

  /// The signature is genuine for what it covers, but the file was changed after it was signed.
  changedAfter,

  /// The signed part of the file does not match the signature: it was altered.
  altered,

  /// The signature does not match the certificate.
  invalid,

  /// A kind of signature Doculoom cannot check.
  unsupported,
}

class PdfSignatureReport {
  const PdfSignatureReport({
    required this.state,
    this.signer,
    this.issuer,
    this.signedAt,
    this.reason = '',
    this.location = '',
    this.format = '',
    this.hash = '',
    this.key = '',
    this.validFrom,
    this.validUntil,
    this.selfSigned = false,
    this.certificateValidWhenSigned,
    this.chainLength = 0,
    this.problem,
  });

  final SignatureState state;
  final String? signer;
  final String? issuer;
  final DateTime? signedAt;
  final String reason;
  final String location;
  final String format;
  final String hash;
  final String key;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final bool selfSigned;

  /// Whether the certificate was in its validity period at the time given in the signature; null when no time is given.
  final bool? certificateValidWhenSigned;
  final int chainLength;
  final String? problem;
}

String _pdfString(PdfObj? o) {
  if (o is! PdfString) return '';
  final b = o.bytes;
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1]]);
  }
  return utf8.decode(b, allowMalformed: true);
}

DateTime? _parsePdfDate(String s) {
  final m = RegExp(r"^D:(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?([Zz+\-])?(\d{2})?'?(\d{2})?").firstMatch(s);
  if (m == null) return null;
  int g(int i, int d) => m[i] == null ? d : int.parse(m[i]!);
  var t = DateTime.utc(int.parse(m[1]!), g(2, 1), g(3, 1), g(4, 0), g(5, 0), g(6, 0));
  final sign = m[7];
  if (sign == '+' || sign == '-') {
    final off = Duration(hours: g(8, 0), minutes: g(9, 0));
    t = sign == '+' ? t.subtract(off) : t.add(off);
  }
  return t;
}

/// Checks every signature in a PDF: that the signed bytes are unchanged, that the signature fits the certificate,
/// and whether the file changed afterwards. It does not check that the certificate is trusted by an authority.
List<PdfSignatureReport> checkPdfSignatures(Uint8List pdf) {
  final PdfScan scan;
  try {
    scan = scanPdf(pdf);
  } on PdfFormatException {
    throw const SigningException('This PDF could not be read.');
  }
  if (scan.trailer['Encrypt'] != null) throw const SigningException('This PDF is password protected. Unlock it first, then check it.');
  final latest = <int, PdfDict>{};
  for (final e in scan.entries) {
    final o = e.object;
    if (o is PdfDict && o['ByteRange'] is PdfArray && o['Contents'] is PdfString) latest[e.number] = o;
  }
  final reports = <PdfSignatureReport>[];
  for (final d in latest.values) {
    final subFilter = d.nameOf('SubFilter') ?? '';
    final reason = _pdfString(d['Reason']);
    final location = _pdfString(d['Location']);
    final markedAt = _parsePdfDate(_pdfString(d['M']));
    PdfSignatureReport bad(String why, {SignatureState state = SignatureState.unsupported}) =>
        PdfSignatureReport(state: state, format: subFilter, reason: reason, location: location, signedAt: markedAt, problem: why);
    final range = [
      for (final i in (d['ByteRange']! as PdfArray).items)
        if (i is PdfInt) i.value,
    ];
    if (subFilter == 'ETSI.RFC3161') {
      reports.add(bad('A document timestamp. Doculoom does not check these.'));
      continue;
    }
    if (range.length != 4 || range[0] != 0 || range[1] < 0 || range[2] < range[1] || range[2] + range[3] > pdf.length) {
      reports.add(bad('The signature points at the wrong part of the file.', state: SignatureState.invalid));
      continue;
    }
    final CmsSignature cms;
    try {
      cms = CmsSignature.parse((d['Contents']! as PdfString).bytes);
    } on Object {
      reports.add(bad('The signature is in a form Doculoom cannot read.'));
      continue;
    }
    final ({bool digestMatches, bool signatureValid, Certificate? signer}) result;
    try {
      result = cms.verify([Uint8List.sublistView(pdf, 0, range[1]), Uint8List.sublistView(pdf, range[2], range[2] + range[3])]);
    } on Object catch (e) {
      reports.add(bad(e is FormatException ? 'This kind of signature (${e.message}) cannot be checked.' : 'The signature could not be checked.'));
      continue;
    }
    final cert = result.signer;
    final signedAt = cms.signingTime ?? markedAt;
    final whole = range[2] + range[3] == pdf.length;
    final state = !result.signatureValid
        ? SignatureState.invalid
        : !result.digestMatches
        ? SignatureState.altered
        : whole
        ? SignatureState.valid
        : SignatureState.changedAfter;
    reports.add(
      PdfSignatureReport(
        state: state,
        signer: cert?.subject.display,
        issuer: cert?.issuer.display,
        signedAt: signedAt,
        reason: reason,
        location: location,
        format: subFilter,
        hash: hashName(cms.hashOid),
        key: cert?.publicKey.description ?? '',
        validFrom: cert?.notBefore,
        validUntil: cert?.notAfter,
        selfSigned: cert?.selfSigned ?? false,
        certificateValidWhenSigned: cert == null || signedAt == null ? null : cert.validAt(signedAt),
        chainLength: cms.certificates.length,
      ),
    );
  }
  reports.sort((a, b) => (a.signedAt ?? DateTime(0)).compareTo(b.signedAt ?? DateTime(0)));
  return reports;
}

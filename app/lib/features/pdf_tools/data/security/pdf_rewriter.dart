import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'pdf_model.dart';
import 'pdf_security.dart';

class NotProtectedException implements Exception {
  const NotProtectedException();
}

class AlreadyProtectedException implements Exception {
  const AlreadyProtectedException();
}

class PdfProtectionInfo {
  const PdfProtectionInfo({required this.encrypted, required this.needsPassword});
  final bool encrypted;

  /// False when the file is protected only against printing or copying and opens with an empty password.
  final bool needsPassword;
}

/// The objects of a PDF in readable form, numbered as in the file.
class PdfDoc {
  PdfDoc(this.objects, this.trailer);
  final Map<int, PdfObj> objects;
  final PdfDict trailer;
}

({PdfDict? dict, int? number, Uint8List id0}) _encryption(PdfScan scan) {
  final enc = scan.trailer['Encrypt'];
  PdfDict? dict;
  int? number;
  if (enc is PdfDict) {
    dict = enc;
  } else if (enc is PdfRef) {
    number = enc.number;
    for (final e in scan.entries.reversed) {
      if (e.number == enc.number && e.object is PdfDict) {
        dict = e.object as PdfDict;
        break;
      }
    }
  }
  final id = scan.trailer['ID'];
  Uint8List id0 = Uint8List(0);
  if (id is PdfArray && id.items.isNotEmpty && id.items.first is PdfString) id0 = (id.items.first as PdfString).bytes;
  return (dict: dict, number: number, id0: id0);
}

PdfProtectionInfo inspectPdf(Uint8List bytes) {
  final scan = scanPdf(bytes);
  final e = _encryption(scan);
  if (scan.trailer['Encrypt'] == null) return const PdfProtectionInfo(encrypted: false, needsPassword: false);
  if (e.dict == null) throw const PdfFormatException('The protection information is missing');
  try {
    PdfSecurity.open(e.dict!, e.id0, '');
    return const PdfProtectionInfo(encrypted: true, needsPassword: false);
  } on WrongPasswordException {
    return const PdfProtectionInfo(encrypted: true, needsPassword: true);
  }
}

/// The readable objects of a PDF. Files that only restrict printing or copying open with the empty password;
/// one that needs a password throws [WrongPasswordException].
PdfDoc readPdfDocument(Uint8List bytes, {String password = ''}) {
  final scan = scanPdf(bytes);
  if (scan.trailer['Encrypt'] == null) return _materialize(scan);
  final e = _encryption(scan);
  if (e.dict == null) throw const PdfFormatException('The protection information is missing');
  final security = PdfSecurity.open(e.dict!, e.id0, password);
  return _materialize(scan, security: security, skipNumber: e.number);
}

/// Writes the objects of [doc] as a new, unprotected PDF.
Uint8List writePdfDocument(PdfDoc doc) => _write(doc);

/// Removes the protection and keeps text, images and everything else of the file unchanged.
Uint8List unlockPdf(Uint8List bytes, {required String password}) {
  final scan = scanPdf(bytes);
  if (scan.trailer['Encrypt'] == null) throw const NotProtectedException();
  final e = _encryption(scan);
  if (e.dict == null) throw const PdfFormatException('The protection information is missing');
  final security = PdfSecurity.open(e.dict!, e.id0, password);
  final doc = _materialize(scan, security: security, skipNumber: e.number);
  return _write(doc);
}

/// Protects an unprotected PDF with AES 256 bit encryption; text, images and everything else of the file stay as they are.
Uint8List lockPdf(Uint8List bytes, {required String password, Random? random}) {
  final scan = scanPdf(bytes);
  if (scan.trailer['Encrypt'] != null) throw const AlreadyProtectedException();
  final doc = _materialize(scan);
  return _write(
    doc,
    writer: PdfAes256Writer.create(password, random: random),
    random: random,
  );
}

PdfDoc _materialize(PdfScan scan, {PdfSecurity? security, int? skipNumber}) {
  final objects = <int, PdfObj>{};
  for (final entry in scan.entries) {
    if (entry.number == skipNumber) continue;
    var obj = entry.object;
    if (security != null) obj = _decryptObject(obj, entry.number, entry.generation, security);
    if (obj is PdfStream) {
      final type = obj.dict.nameOf('Type');
      if (type == 'XRef') continue;
      if (type == 'ObjStm') {
        for (final inner in _expandObjectStream(obj)) {
          objects[inner.$1] = inner.$2;
        }
        continue;
      }
    }
    objects[entry.number] = obj;
  }

  final trailer = PdfDict();
  for (final key in const ['Root', 'Info', 'ID']) {
    final v = scan.trailer[key];
    if (v != null) trailer[key] = v;
  }
  if (trailer['Root'] is! PdfRef || objects[(trailer['Root'] as PdfRef).number] is! PdfDict) {
    // Without a usable trailer the document catalog is looked up by its type.
    final found = objects.entries.where((e) => e.value is PdfDict && (e.value as PdfDict).nameOf('Type') == 'Catalog').toList();
    if (found.isEmpty) throw const PdfFormatException('No document catalog');
    trailer['Root'] = PdfRef(found.last.key, 0);
  }
  return PdfDoc(objects, trailer);
}

PdfObj _decryptValue(PdfObj o, int number, int generation, PdfSecurity s) => switch (o) {
  PdfString(:final bytes) => PdfString(s.decrypt(bytes, number, generation, s.string)),
  PdfArray(:final items) => PdfArray([for (final i in items) _decryptValue(i, number, generation, s)]),
  PdfDict(:final entries) => PdfDict({for (final e in entries.entries) e.key: _decryptValue(e.value, number, generation, s)}),
  _ => o,
};

PdfObj _decryptObject(PdfObj o, int number, int generation, PdfSecurity s) {
  if (o is! PdfStream) return _decryptValue(o, number, generation, s);
  final type = o.dict.nameOf('Type');
  if (type == 'XRef') return o;
  final dict = _decryptValue(o.dict, number, generation, s) as PdfDict;
  final plain = (type == 'Metadata' && !s.encryptMetadata) || _hasIdentityCrypt(o.dict);
  return PdfStream(dict, plain ? o.data : s.decrypt(o.data, number, generation, s.stream));
}

List<String> _filters(PdfDict d) => switch (d['Filter']) {
  PdfName(:final name) => [name],
  PdfArray(:final items) => [
    for (final i in items)
      if (i is PdfName) i.name,
  ],
  _ => const [],
};

bool _hasIdentityCrypt(PdfDict d) {
  final filters = _filters(d);
  final index = filters.indexOf('Crypt');
  if (index < 0) return false;
  final parms = d['DecodeParms'];
  PdfObj? mine = parms is PdfArray && index < parms.items.length ? parms.items[index] : (parms is PdfDict ? parms : null);
  final name = mine is PdfDict ? mine.nameOf('Name') : null;
  return name == null || name == 'Identity';
}

/// Takes a Crypt filter out of a stream that is no longer encrypted.
PdfDict _withoutCrypt(PdfDict d) {
  final filters = _filters(d);
  final index = filters.indexOf('Crypt');
  if (index < 0) return d;
  final out = PdfDict(Map.of(d.entries));
  final left = [...filters]..removeAt(index);
  final parms = d['DecodeParms'];
  if (left.isEmpty) {
    out.entries.remove('Filter');
    out.entries.remove('DecodeParms');
  } else {
    out['Filter'] = left.length == 1 ? PdfName(left.first) : PdfArray([for (final f in left) PdfName(f)]);
    if (parms is PdfArray && index < parms.items.length) {
      final kept = [...parms.items]..removeAt(index);
      out['DecodeParms'] = kept.length == 1 ? kept.first : PdfArray(kept);
    }
  }
  return out;
}

List<(int, PdfObj)> _expandObjectStream(PdfStream s) {
  final filters = _filters(s.dict);
  if (filters.length > 1 || (filters.length == 1 && filters.first != 'FlateDecode' && filters.first != 'Fl')) {
    throw const PdfFormatException('Unsupported object stream');
  }
  final parms = s.dict['DecodeParms'];
  if (parms is PdfDict && (parms.intOf('Predictor') ?? 1) > 1) throw const PdfFormatException('Unsupported object stream');
  final data = filters.isEmpty ? s.data : Uint8List.fromList(zlib.decode(s.data));
  final n = s.dict.intOf('N') ?? 0;
  final first = s.dict.intOf('First') ?? 0;
  final lexer = PdfLexer(data);
  final header = <(int, int)>[];
  for (var i = 0; i < n; i++) {
    final num = lexer.parseObject();
    final off = lexer.parseObject();
    if (num is! PdfInt || off is! PdfInt) throw const PdfFormatException('Bad object stream');
    header.add((num.value, off.value));
  }
  final out = <(int, PdfObj)>[];
  for (final (number, offset) in header) {
    final at = first + offset;
    if (at < 0 || at >= data.length) continue;
    out.add((number, PdfLexer(data, at).parseObject()));
  }
  return out;
}

// region writing

void _collectRefs(PdfObj o, void Function(int) found) {
  final stack = <PdfObj>[o];
  while (stack.isNotEmpty) {
    final x = stack.removeLast();
    switch (x) {
      case PdfRef(:final number):
        found(number);
      case PdfArray(:final items):
        stack.addAll(items);
      case PdfDict(:final entries):
        stack.addAll(entries.values);
      case PdfStream(:final dict):
        stack.add(dict);
      default:
    }
  }
}

Uint8List _write(PdfDoc doc, {PdfAes256Writer? writer, Random? random}) {
  // Only what can be reached from the document catalog is written, in order, with new compact numbers.
  final order = <int>[];
  final newNumber = <int, int>{};
  final queue = <int>[];
  void visit(int n) {
    if (newNumber.containsKey(n) || !doc.objects.containsKey(n)) return;
    newNumber[n] = order.length + 1;
    order.add(n);
    queue.add(n);
  }

  _collectRefs(doc.trailer['Root']!, visit);
  if (doc.trailer['Info'] != null) _collectRefs(doc.trailer['Info']!, visit);
  while (queue.isNotEmpty) {
    _collectRefs(doc.objects[queue.removeLast()]!, visit);
  }

  final out = BytesBuilder(copy: false);
  void text(String s) => out.add(latin1.encode(s));
  text('%PDF-1.7\n%');
  out.add(const [0xE2, 0xE3, 0xCF, 0xD3]);
  text('\n');

  final offsets = <int>[];
  var length = out.length;
  void mark() => offsets.add(length);

  Uint8List Function(Uint8List)? enc = writer?.encrypt;
  final body = _Serializer(newNumber, enc);

  for (final old in order) {
    final obj = doc.objects[old]!;
    final piece = BytesBuilder(copy: false);
    mark();
    piece.add(latin1.encode('${newNumber[old]} 0 obj\n'));
    if (obj is PdfStream) {
      final dict = _withoutCrypt(obj.dict);
      final data = enc == null ? obj.data : enc(obj.data);
      final copy = PdfDict(Map.of(dict.entries))..['Length'] = PdfInt(data.length);
      body.write(piece, copy);
      piece.add(latin1.encode('\nstream\n'));
      piece.add(data);
      piece.add(latin1.encode('\nendstream'));
    } else {
      body.write(piece, obj);
    }
    piece.add(latin1.encode('\nendobj\n'));
    final bytes = piece.takeBytes();
    out.add(bytes);
    length += bytes.length;
  }

  var size = order.length + 1;
  int? encryptNumber;
  if (writer != null) {
    encryptNumber = size++;
    mark();
    final piece = BytesBuilder(copy: false);
    piece.add(latin1.encode('$encryptNumber 0 obj\n'));
    _Serializer(const {}, null).write(piece, writer.encryptDict);
    piece.add(latin1.encode('\nendobj\n'));
    final bytes = piece.takeBytes();
    out.add(bytes);
    length += bytes.length;
  }

  final xrefAt = length;
  final xref = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
  for (final o in offsets) {
    xref.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  final trailer = PdfDict({'Size': PdfInt(size), 'Root': PdfRef(newNumber[(doc.trailer['Root'] as PdfRef).number] ?? 1, 0)});
  final info = doc.trailer['Info'];
  if (info is PdfRef && newNumber.containsKey(info.number)) trailer['Info'] = PdfRef(newNumber[info.number]!, 0);
  var id = doc.trailer['ID'];
  if (id is! PdfArray || id.items.length != 2 || id.items.any((i) => i is! PdfString)) {
    final rnd = random ?? Random.secure();
    final fresh = PdfString(Uint8List.fromList([for (var i = 0; i < 16; i++) rnd.nextInt(256)]));
    id = PdfArray([fresh, fresh]);
  }
  trailer['ID'] = id;
  if (encryptNumber != null) trailer['Encrypt'] = PdfRef(encryptNumber, 0);
  final tb = BytesBuilder(copy: false);
  _Serializer(const {}, null, passRefsThrough: true).write(tb, trailer);
  out.add(latin1.encode(xref.toString()));
  out.add(latin1.encode('trailer\n'));
  out.add(tb.takeBytes());
  out.add(latin1.encode('\nstartxref\n$xrefAt\n%%EOF\n'));
  return out.takeBytes();
}

class _Serializer {
  _Serializer(this.numbers, this.encryptString, {this.passRefsThrough = false});

  final Map<int, int> numbers;
  final Uint8List Function(Uint8List)? encryptString;
  final bool passRefsThrough;

  void write(BytesBuilder out, PdfObj o) {
    void s(String t) => out.add(latin1.encode(t));
    switch (o) {
      case PdfNull():
        s('null');
      case PdfBool(:final value):
        s(value ? 'true' : 'false');
      case PdfInt(:final value):
        s('$value');
      case PdfReal(:final text):
        s(text);
      case PdfName(:final name):
        s('/');
        for (final c in name.codeUnits) {
          final regular = c > 32 && c < 127 && c != 0x23 && !isPdfDelimiter(c);
          s(regular ? String.fromCharCode(c) : '#${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      case PdfString(:final bytes):
        final data = encryptString == null ? bytes : encryptString!(bytes);
        final hex = StringBuffer('<');
        for (final b in data) {
          hex.write(b.toRadixString(16).padLeft(2, '0'));
        }
        hex.write('>');
        s(hex.toString());
      case PdfArray(:final items):
        s('[');
        for (var i = 0; i < items.length; i++) {
          if (i > 0) s(' ');
          write(out, items[i]);
        }
        s(']');
      case PdfDict(:final entries):
        s('<<');
        for (final e in entries.entries) {
          write(out, PdfName(e.key));
          s(' ');
          write(out, e.value);
          s('\n');
        }
        s('>>');
      case PdfRef(:final number, :final generation):
        if (passRefsThrough) {
          s('$number $generation R');
        } else {
          final n = numbers[number];
          s(n == null ? 'null' : '$n 0 R');
        }
      case PdfStream():
        throw StateError('A stream cannot be written inside another object');
    }
  }
}

// endregion

import 'dart:convert';
import 'dart:typed_data';

/// One element of DER (or definite/indefinite BER) data: a tag with its content, read from a buffer without copying.
class Der {
  Der._(this._data, this.tag, this._start, this._valueStart, this._valueEnd, this._end);

  final Uint8List _data;
  final int tag;
  final int _start;
  final int _valueStart;
  final int _valueEnd;
  final int _end;

  static const sequence = 0x30;
  static const set = 0x31;
  static const integer = 0x02;
  static const bitString = 0x03;
  static const octetString = 0x04;
  static const nullTag = 0x05;
  static const oidTag = 0x06;

  /// Reads the element that starts at [offset].
  static Der parse(Uint8List data, [int offset = 0]) {
    if (offset >= data.length) throw const FormatException('Unexpected end of data');
    final tag = data[offset];
    if (tag & 0x1F == 0x1F) throw const FormatException('Long tags are not supported');
    var p = offset + 1;
    if (p >= data.length) throw const FormatException('Unexpected end of data');
    var length = data[p++];
    if (length == 0x80) {
      // Indefinite length: the content runs to the end-of-contents marker.
      if (tag & 0x20 == 0) throw const FormatException('Bad length');
      final valueStart = p;
      while (true) {
        if (p + 1 >= data.length) throw const FormatException('Unexpected end of data');
        if (data[p] == 0 && data[p + 1] == 0) {
          return Der._(data, tag, offset, valueStart, p, p + 2);
        }
        p = parse(data, p)._end;
      }
    }
    if (length & 0x80 != 0) {
      final n = length & 0x7F;
      if (n > 4 || p + n > data.length) throw const FormatException('Bad length');
      length = 0;
      for (var i = 0; i < n; i++) {
        length = (length << 8) | data[p++];
      }
    }
    if (p + length > data.length) throw const FormatException('Unexpected end of data');
    return Der._(data, tag, offset, p, p + length, p + length);
  }

  int get length => _valueEnd - _valueStart;
  bool get constructed => tag & 0x20 != 0;
  bool isContext(int n) => tag & 0xC0 == 0x80 && tag & 0x1F == n;
  Uint8List get value => Uint8List.sublistView(_data, _valueStart, _valueEnd);

  /// The element with its tag and length, as it was read.
  Uint8List get encoded => Uint8List.sublistView(_data, _start, _end);

  /// The bytes of the whole element, ending where the next one begins.
  int get endOffset => _end;

  List<Der> get children {
    final out = <Der>[];
    var p = _valueStart;
    while (p < _valueEnd) {
      final c = parse(_data, p);
      out.add(c);
      p = c._end;
    }
    return out;
  }

  Der operator [](int i) => children[i];

  BigInt get integerValue {
    final v = value;
    if (v.isEmpty) return BigInt.zero;
    var r = BigInt.zero;
    for (final b in v) {
      r = (r << 8) | BigInt.from(b);
    }
    if (v[0] & 0x80 != 0) r -= BigInt.one << (8 * v.length);
    return r;
  }

  int get intValue => integerValue.toInt();

  String get oid {
    final v = value;
    if (v.isEmpty) return '';
    final parts = <int>[v[0] ~/ 40, v[0] % 40];
    var n = 0;
    for (var i = 1; i < v.length; i++) {
      n = (n << 7) | (v[i] & 0x7F);
      if (v[i] & 0x80 == 0) {
        parts.add(n);
        n = 0;
      }
    }
    return parts.join('.');
  }

  /// Text of a string type (UTF-8, printable, IA5, teletex and BMP strings).
  String get text {
    final v = value;
    if (tag == 0x1E) {
      return String.fromCharCodes([for (var i = 0; i + 1 < v.length; i += 2) (v[i] << 8) | v[i + 1]]);
    }
    try {
      return utf8.decode(v);
    } on FormatException {
      return latin1.decode(v);
    }
  }

  /// A UTCTime or GeneralizedTime as UTC.
  DateTime get time {
    final s = latin1.decode(value);
    final m = RegExp(r'^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?').firstMatch(s);
    if (m == null) throw const FormatException('Bad time');
    var year = int.parse(m[1]!);
    if (m[1]!.length == 2) year += year >= 50 ? 1900 : 2000;
    return DateTime.utc(year, int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6] ?? '0'));
  }

  /// The content of a BIT STRING without the leading count of unused bits.
  Uint8List get bits => Uint8List.sublistView(value, 1);
}

Uint8List _concat(Iterable<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

/// An element: tag, length and content.
Uint8List der(int tag, List<int> content) {
  final n = content.length;
  final len = n < 0x80
      ? [n]
      : n < 0x100
      ? [0x81, n]
      : n < 0x10000
      ? [0x82, n >> 8, n & 0xFF]
      : n < 0x1000000
      ? [0x83, n >> 16, (n >> 8) & 0xFF, n & 0xFF]
      : [0x84, n >> 24, (n >> 16) & 0xFF, (n >> 8) & 0xFF, n & 0xFF];
  return _concat([
    [tag],
    len,
    content,
  ]);
}

Uint8List derSequence(Iterable<List<int>> items) => der(Der.sequence, _concat(items));

Uint8List derSet(Iterable<List<int>> items) => der(Der.set, _concat(items));

/// A SET OF, its elements in the order DER demands (by their encoding).
Uint8List derSetOf(Iterable<Uint8List> items) {
  final sorted = items.toList()
    ..sort((a, b) {
      final n = a.length < b.length ? a.length : b.length;
      for (var i = 0; i < n; i++) {
        if (a[i] != b[i]) return a[i].compareTo(b[i]);
      }
      return a.length.compareTo(b.length);
    });
  return derSet(sorted);
}

Uint8List derInteger(BigInt v) {
  if (v == BigInt.zero) return der(Der.integer, [0]);
  var bytes = <int>[];
  var x = v;
  while (x > BigInt.zero) {
    bytes.insert(0, (x & BigInt.from(0xFF)).toInt());
    x >>= 8;
  }
  if (bytes[0] & 0x80 != 0) bytes = [0, ...bytes];
  return der(Der.integer, bytes);
}

Uint8List derInt(int v) => derInteger(BigInt.from(v));

Uint8List derOid(String oid) {
  final p = oid.split('.').map(int.parse).toList();
  final out = <int>[p[0] * 40 + p[1]];
  for (final n in p.skip(2)) {
    final chunk = <int>[n & 0x7F];
    var x = n >> 7;
    while (x > 0) {
      chunk.insert(0, 0x80 | (x & 0x7F));
      x >>= 7;
    }
    out.addAll(chunk);
  }
  return der(Der.oidTag, out);
}

Uint8List derOctets(List<int> bytes) => der(Der.octetString, bytes);

Uint8List derNull() => der(Der.nullTag, const []);

Uint8List derUtcTime(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return der(0x17, ascii.encode('${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z'));
}

/// A context-specific element `[n]`, constructed unless [primitive].
Uint8List derContext(int n, List<int> content, {bool primitive = false}) => der(0x80 | n | (primitive ? 0 : 0x20), content);

/// An algorithm identifier: the OID with optional parameters (NULL by default).
Uint8List derAlgorithm(String oid, {List<int>? parameters, bool noParameters = false}) =>
    derSequence([derOid(oid), if (!noParameters) parameters ?? derNull()]);

BigInt bytesToBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

Uint8List bigIntToBytes(BigInt v, {int? length}) {
  var x = v;
  final out = <int>[];
  while (x > BigInt.zero) {
    out.insert(0, (x & BigInt.from(0xFF)).toInt());
    x >>= 8;
  }
  if (length != null) {
    while (out.length < length) {
      out.insert(0, 0);
    }
  }
  return Uint8List.fromList(out.isEmpty ? [0] : out);
}

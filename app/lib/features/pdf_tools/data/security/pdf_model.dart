import 'dart:convert';
import 'dart:typed_data';

/// The parts a PDF file is made of.
sealed class PdfObj {
  const PdfObj();
}

class PdfNull extends PdfObj {
  const PdfNull();
}

class PdfBool extends PdfObj {
  const PdfBool(this.value);
  final bool value;
}

class PdfInt extends PdfObj {
  const PdfInt(this.value);
  final int value;
}

/// A real number kept as written so it is not changed by reading and writing it.
class PdfReal extends PdfObj {
  const PdfReal(this.text);
  final String text;
}

/// Names are kept as one character per byte (without the slash and with # codes resolved).
class PdfName extends PdfObj {
  const PdfName(this.name);
  final String name;
}

class PdfString extends PdfObj {
  const PdfString(this.bytes);
  final Uint8List bytes;
}

class PdfArray extends PdfObj {
  const PdfArray(this.items);
  final List<PdfObj> items;
}

class PdfDict extends PdfObj {
  PdfDict([Map<String, PdfObj>? entries]) : entries = entries ?? {};
  final Map<String, PdfObj> entries;

  PdfObj? operator [](String key) => entries[key];
  void operator []=(String key, PdfObj value) => entries[key] = value;

  int? intOf(String key) => switch (entries[key]) {
    PdfInt(:final value) => value,
    PdfReal(:final text) => double.tryParse(text)?.round(),
    _ => null,
  };

  String? nameOf(String key) => switch (entries[key]) {
    PdfName(:final name) => name,
    _ => null,
  };

  Uint8List? bytesOf(String key) => switch (entries[key]) {
    PdfString(:final bytes) => bytes,
    _ => null,
  };

  bool? boolOf(String key) => switch (entries[key]) {
    PdfBool(:final value) => value,
    _ => null,
  };
}

class PdfRef extends PdfObj {
  const PdfRef(this.number, this.generation);
  final int number;
  final int generation;
}

/// A stream: a dictionary plus the bytes exactly as stored (still compressed or encrypted).
class PdfStream extends PdfObj {
  PdfStream(this.dict, this.data);
  final PdfDict dict;
  final Uint8List data;
}

class PdfFormatException implements Exception {
  const PdfFormatException(this.message);
  final String message;

  @override
  String toString() => 'PdfFormatException: $message';
}

bool isPdfWhitespace(int c) => c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;

bool isPdfDelimiter(int c) => c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

/// Reads PDF syntax from a byte buffer.
class PdfLexer {
  PdfLexer(this.bytes, [this.pos = 0]);

  final Uint8List bytes;
  int pos;

  bool get atEnd => pos >= bytes.length;

  void skipWhitespace() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (isPdfWhitespace(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < bytes.length && bytes[pos] != 10 && bytes[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  bool startsWith(String word, [int? at]) {
    final p = at ?? pos;
    if (p + word.length > bytes.length) return false;
    for (var i = 0; i < word.length; i++) {
      if (bytes[p + i] != word.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// A keyword such as obj, endobj or stream: the word must end at a delimiter or space.
  bool atKeyword(String word) {
    if (!startsWith(word)) return false;
    final end = pos + word.length;
    return end >= bytes.length || isPdfWhitespace(bytes[end]) || isPdfDelimiter(bytes[end]);
  }

  PdfObj parseObject({int depth = 0}) {
    if (depth > 200) throw const PdfFormatException('Too deeply nested');
    skipWhitespace();
    if (atEnd) throw const PdfFormatException('Unexpected end of file');
    final c = bytes[pos];
    if (c == 0x2F) return _name();
    if (c == 0x28) return _literalString();
    if (c == 0x3C) {
      if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3C) return _dict(depth);
      return _hexString();
    }
    if (c == 0x5B) return _array(depth);
    if (_isDigit(c) || c == 0x2B || c == 0x2D || c == 0x2E) return _numberOrRef();
    return _keyword();
  }

  PdfObj _keyword() {
    final start = pos;
    while (pos < bytes.length && !isPdfWhitespace(bytes[pos]) && !isPdfDelimiter(bytes[pos])) {
      pos++;
    }
    final word = latin1.decode(bytes.sublist(start, pos));
    return switch (word) {
      'true' => const PdfBool(true),
      'false' => const PdfBool(false),
      'null' => const PdfNull(),
      _ => throw PdfFormatException('Unexpected "$word"'),
    };
  }

  PdfName _name() {
    pos++;
    final out = StringBuffer();
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (isPdfWhitespace(c) || isPdfDelimiter(c)) break;
      if (c == 0x23 && pos + 2 < bytes.length && _hexValue(bytes[pos + 1]) >= 0 && _hexValue(bytes[pos + 2]) >= 0) {
        out.writeCharCode(_hexValue(bytes[pos + 1]) * 16 + _hexValue(bytes[pos + 2]));
        pos += 3;
      } else {
        out.writeCharCode(c);
        pos++;
      }
    }
    return PdfName(out.toString());
  }

  PdfString _literalString() {
    pos++;
    final out = BytesBuilder(copy: false);
    var depth = 1;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x5C) {
        if (pos >= bytes.length) break;
        final e = bytes[pos++];
        switch (e) {
          case 0x6E:
            out.addByte(10);
          case 0x72:
            out.addByte(13);
          case 0x74:
            out.addByte(9);
          case 0x62:
            out.addByte(8);
          case 0x66:
            out.addByte(12);
          case 0x0D:
            if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var i = 0; i < 2 && pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x37; i++) {
                v = v * 8 + (bytes[pos++] - 0x30);
              }
              out.addByte(v & 0xFF);
            } else {
              out.addByte(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.addByte(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) return PdfString(out.takeBytes());
        out.addByte(c);
      } else if (c == 0x0D) {
        // An unescaped line break inside a string counts as a single line feed.
        out.addByte(10);
        if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
      } else {
        out.addByte(c);
      }
    }
    throw const PdfFormatException('Unterminated string');
  }

  PdfString _hexString() {
    pos++;
    final out = BytesBuilder(copy: false);
    var high = -1;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x3E) {
        if (high >= 0) out.addByte(high * 16);
        return PdfString(out.takeBytes());
      }
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high < 0) {
        high = v;
      } else {
        out.addByte(high * 16 + v);
        high = -1;
      }
    }
    throw const PdfFormatException('Unterminated hex string');
  }

  PdfArray _array(int depth) {
    pos++;
    final items = <PdfObj>[];
    while (true) {
      skipWhitespace();
      if (atEnd) throw const PdfFormatException('Unterminated array');
      if (bytes[pos] == 0x5D) {
        pos++;
        return PdfArray(items);
      }
      items.add(parseObject(depth: depth + 1));
    }
  }

  PdfDict _dict(int depth) {
    pos += 2;
    final dict = PdfDict();
    while (true) {
      skipWhitespace();
      if (atEnd) throw const PdfFormatException('Unterminated dictionary');
      if (bytes[pos] == 0x3E) {
        if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3E) {
          pos += 2;
          return dict;
        }
        throw const PdfFormatException('Stray ">"');
      }
      if (bytes[pos] != 0x2F) throw const PdfFormatException('Dictionary key expected');
      final key = _name().name;
      skipWhitespace();
      if (!atEnd && bytes[pos] == 0x3E) {
        dict[key] = const PdfNull();
        continue;
      }
      dict[key] = parseObject(depth: depth + 1);
    }
  }

  PdfObj _numberOrRef() {
    final start = pos;
    if (bytes[pos] == 0x2B || bytes[pos] == 0x2D) pos++;
    var digitsOnly = true;
    var any = false;
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (_isDigit(c)) {
        any = true;
        pos++;
      } else if (c == 0x2E) {
        digitsOnly = false;
        pos++;
      } else {
        break;
      }
    }
    if (!any && digitsOnly) throw const PdfFormatException('Bad number');
    final text = latin1.decode(bytes.sublist(start, pos));
    if (!digitsOnly) return PdfReal(text);
    final value = int.tryParse(text);
    if (value == null) return PdfReal(text);
    if (text.startsWith('-') || text.startsWith('+')) return PdfInt(value);

    // "12 0 R" is a reference.
    final saved = pos;
    skipWhitespace();
    final genStart = pos;
    while (pos < bytes.length && _isDigit(bytes[pos])) {
      pos++;
    }
    if (pos > genStart && pos - genStart < 6) {
      final gen = int.parse(latin1.decode(bytes.sublist(genStart, pos)));
      skipWhitespace();
      if (pos < bytes.length && bytes[pos] == 0x52 && (pos + 1 >= bytes.length || isPdfWhitespace(bytes[pos + 1]) || isPdfDelimiter(bytes[pos + 1]))) {
        pos++;
        return PdfRef(value, gen);
      }
    }
    pos = saved;
    return PdfInt(value);
  }
}

/// An object as found in the file, with the number it was given.
class PdfEntry {
  PdfEntry(this.number, this.generation, this.object, {this.streamStart});
  final int number;
  final int generation;
  PdfObj object;

  /// Where the stream bytes begin in the file, used to re-read a stream whose length was stored in another object.
  final int? streamStart;
}

/// Everything found by reading a PDF file from start to finish, before any decryption.
class PdfScan {
  PdfScan({required this.entries, required this.trailer});
  final List<PdfEntry> entries;
  final PdfDict trailer;
}

/// Reads the objects and trailers of a PDF without relying on its cross reference tables, which makes damaged and updated files readable.
PdfScan scanPdf(Uint8List bytes) {
  final head = latin1.decode(bytes.sublist(0, bytes.length < 1024 ? bytes.length : 1024), allowInvalid: true);
  if (!head.contains('%PDF-')) throw const PdfFormatException('Not a PDF');

  final entries = <PdfEntry>[];
  final trailer = PdfDict();
  final lexer = PdfLexer(bytes);
  var pos = 0;
  final n = bytes.length;

  void mergeTrailer(PdfDict d) {
    for (final key in const ['Root', 'Info', 'Encrypt', 'ID']) {
      final v = d[key];
      if (v != null) trailer[key] = v;
    }
  }

  while (pos < n) {
    final c = bytes[pos];
    // A trailer keyword or an object header, both at the start of a token.
    if (c == 0x74 && lexer.startsWith('trailer', pos) && (pos == 0 || isPdfWhitespace(bytes[pos - 1]) || isPdfDelimiter(bytes[pos - 1]))) {
      lexer.pos = pos + 7;
      try {
        final d = lexer.parseObject();
        if (d is PdfDict) mergeTrailer(d);
        pos = lexer.pos;
      } on PdfFormatException {
        pos += 7;
      }
      continue;
    }
    if (c == 0x6F &&
        lexer.startsWith('obj', pos) &&
        pos + 3 <= n &&
        (pos + 3 >= n || isPdfWhitespace(bytes[pos + 3]) || isPdfDelimiter(bytes[pos + 3])) &&
        pos > 0 &&
        isPdfWhitespace(bytes[pos - 1])) {
      final header = _headerBefore(bytes, pos);
      if (header != null) {
        lexer.pos = pos + 3;
        try {
          final entry = _readObject(lexer, header.$1, header.$2);
          entries.add(entry);
          final obj = entry.object;
          if (obj is PdfStream && obj.dict.nameOf('Type') == 'XRef') mergeTrailer(obj.dict);
          pos = lexer.pos;
          continue;
        } on PdfFormatException {
          // An unreadable object is skipped; the rest of the file may still be fine.
        }
      }
    }
    pos++;
  }

  _fixStreamLengths(bytes, entries);
  return PdfScan(entries: entries, trailer: trailer);
}

(int, int)? _headerBefore(Uint8List b, int objPos) {
  var p = objPos - 1;
  while (p >= 0 && isPdfWhitespace(b[p])) {
    p--;
  }
  final genEnd = p + 1;
  while (p >= 0 && _isDigit(b[p])) {
    p--;
  }
  final genStart = p + 1;
  if (genStart == genEnd || genEnd - genStart > 5) return null;
  if (p < 0 || !isPdfWhitespace(b[p])) return null;
  while (p >= 0 && isPdfWhitespace(b[p])) {
    p--;
  }
  final numEnd = p + 1;
  while (p >= 0 && _isDigit(b[p])) {
    p--;
  }
  final numStart = p + 1;
  if (numStart == numEnd || numEnd - numStart > 10) return null;
  if (p >= 0 && !isPdfWhitespace(b[p]) && !isPdfDelimiter(b[p])) return null;
  return (int.parse(latin1.decode(b.sublist(numStart, numEnd))), int.parse(latin1.decode(b.sublist(genStart, genEnd))));
}

PdfEntry _readObject(PdfLexer lexer, int number, int generation) {
  lexer.skipWhitespace();
  if (lexer.atKeyword('endobj')) {
    lexer.pos += 6;
    return PdfEntry(number, generation, const PdfNull());
  }
  final obj = lexer.parseObject();
  lexer.skipWhitespace();
  if (obj is PdfDict && lexer.atKeyword('stream')) {
    final b = lexer.bytes;
    var p = lexer.pos + 6;
    if (p < b.length && b[p] == 0x0D) {
      p++;
      if (p < b.length && b[p] == 0x0A) p++;
    } else if (p < b.length && b[p] == 0x0A) {
      p++;
    }
    final start = p;
    int end;
    final length = obj.entries['Length'] is PdfInt ? obj.intOf('Length') : null;
    if (length != null && length >= 0 && start + length <= b.length && _endstreamAt(b, start + length)) {
      end = start + length;
    } else {
      final idx = _indexOf(b, 'endstream', start);
      if (idx < 0) throw const PdfFormatException('Unterminated stream');
      end = idx;
      if (end > start && b[end - 1] == 0x0A) end--;
      if (end > start && b[end - 1] == 0x0D) end--;
    }
    final data = Uint8List.sublistView(b, start, end);
    var after = _indexOf(b, 'endstream', end);
    after = after < 0 ? b.length : after + 9;
    lexer.pos = after;
    lexer.skipWhitespace();
    if (lexer.atKeyword('endobj')) lexer.pos += 6;
    return PdfEntry(number, generation, PdfStream(obj, data), streamStart: start);
  }
  if (lexer.atKeyword('endobj')) lexer.pos += 6;
  return PdfEntry(number, generation, obj);
}

bool _endstreamAt(Uint8List b, int p) {
  var i = p;
  var skipped = 0;
  while (i < b.length && isPdfWhitespace(b[i]) && skipped < 4) {
    i++;
    skipped++;
  }
  const word = 'endstream';
  if (i + word.length > b.length) return false;
  for (var k = 0; k < word.length; k++) {
    if (b[i + k] != word.codeUnitAt(k)) return false;
  }
  return true;
}

int _indexOf(Uint8List b, String word, int from) {
  final first = word.codeUnitAt(0);
  final last = b.length - word.length;
  for (var i = from; i <= last; i++) {
    if (b[i] != first) continue;
    var ok = true;
    for (var k = 1; k < word.length; k++) {
      if (b[i + k] != word.codeUnitAt(k)) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

/// Streams whose length is stored in another object are cut at the first "endstream" while reading; with the real length known they are cut exactly.
void _fixStreamLengths(Uint8List b, List<PdfEntry> entries) {
  final byNumber = <int, PdfObj>{for (final e in entries) e.number: e.object};
  for (final e in entries) {
    final obj = e.object;
    if (obj is! PdfStream || e.streamStart == null) continue;
    final len = obj.dict['Length'];
    if (len is! PdfRef) continue;
    final target = byNumber[len.number];
    final value = target is PdfInt ? target.value : null;
    final start = e.streamStart!;
    if (value == null || value < 0 || start + value > b.length || !_endstreamAt(b, start + value)) continue;
    e.object = PdfStream(obj.dict, Uint8List.sublistView(b, start, start + value));
  }
}

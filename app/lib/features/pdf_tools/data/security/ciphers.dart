import 'dart:typed_data';

/// RC4 stream cipher, used by the older PDF protection levels.
Uint8List rc4(Uint8List key, Uint8List data) {
  final s = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    s[i] = i;
  }
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }
  final out = Uint8List(data.length);
  var a = 0, b = 0;
  for (var n = 0; n < data.length; n++) {
    a = (a + 1) & 0xFF;
    b = (b + s[a]) & 0xFF;
    final t = s[a];
    s[a] = s[b];
    s[b] = t;
    out[n] = data[n] ^ s[(s[a] + s[b]) & 0xFF];
  }
  return out;
}

final _sbox = Uint8List(256);
final _invSbox = Uint8List(256);
final _mul2 = Uint8List(256);
final _mul3 = Uint8List(256);
final _mul9 = Uint8List(256);
final _mul11 = Uint8List(256);
final _mul13 = Uint8List(256);
final _mul14 = Uint8List(256);
var _tablesReady = false;

int _xtime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1B : 0)) & 0xFF;

int _gmul(int a, int b) {
  var r = 0;
  while (b != 0) {
    if ((b & 1) != 0) r ^= a;
    a = _xtime(a);
    b >>= 1;
  }
  return r;
}

void _initTables() {
  if (_tablesReady) return;
  var p = 1, q = 1;
  do {
    p = (p ^ (p << 1) ^ ((p & 0x80) != 0 ? 0x1B : 0)) & 0xFF;
    q ^= q << 1;
    q ^= q << 2;
    q ^= q << 4;
    q &= 0xFF;
    if ((q & 0x80) != 0) q ^= 0x09;
    int rotl(int x, int n) => ((x << n) | (x >> (8 - n))) & 0xFF;
    final x = q ^ rotl(q, 1) ^ rotl(q, 2) ^ rotl(q, 3) ^ rotl(q, 4);
    _sbox[p] = (x ^ 0x63) & 0xFF;
  } while (p != 1);
  _sbox[0] = 0x63;
  for (var i = 0; i < 256; i++) {
    _invSbox[_sbox[i]] = i;
    _mul2[i] = _gmul(i, 2);
    _mul3[i] = _gmul(i, 3);
    _mul9[i] = _gmul(i, 9);
    _mul11[i] = _gmul(i, 11);
    _mul13[i] = _gmul(i, 13);
    _mul14[i] = _gmul(i, 14);
  }
  _tablesReady = true;
}

/// AES with a 128 or 256 bit key.
class Aes {
  Aes(Uint8List key) : _rounds = key.length == 16 ? 10 : (key.length == 32 ? 14 : throw ArgumentError('AES key must be 16 or 32 bytes')) {
    _initTables();
    _expandKey(key);
  }

  final int _rounds;
  late final Uint8List _round = Uint8List(16 * (_rounds + 1));
  final Uint8List _state = Uint8List(16);
  final Uint8List _scratch = Uint8List(16);

  void _expandKey(Uint8List key) {
    final nk = key.length ~/ 4;
    final total = 4 * (_rounds + 1);
    _round.setRange(0, key.length, key);
    var rcon = 1;
    final t = Uint8List(4);
    for (var i = nk; i < total; i++) {
      for (var k = 0; k < 4; k++) {
        t[k] = _round[(i - 1) * 4 + k];
      }
      if (i % nk == 0) {
        final first = t[0];
        t[0] = _sbox[t[1]] ^ rcon;
        t[1] = _sbox[t[2]];
        t[2] = _sbox[t[3]];
        t[3] = _sbox[first];
        rcon = _xtime(rcon);
      } else if (nk > 6 && i % nk == 4) {
        for (var k = 0; k < 4; k++) {
          t[k] = _sbox[t[k]];
        }
      }
      for (var k = 0; k < 4; k++) {
        _round[i * 4 + k] = _round[(i - nk) * 4 + k] ^ t[k];
      }
    }
  }

  void _addRoundKey(Uint8List s, int round) {
    final o = round * 16;
    for (var i = 0; i < 16; i++) {
      s[i] ^= _round[o + i];
    }
  }

  /// Encrypts one 16 byte block from [input] at [inOff] into [out] at [outOff].
  void encryptBlock(Uint8List input, int inOff, Uint8List out, int outOff) {
    final s = _state..setRange(0, 16, input, inOff);
    final tmp = _scratch;
    _addRoundKey(s, 0);
    for (var round = 1; round <= _rounds; round++) {
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          tmp[r + 4 * c] = _sbox[s[r + 4 * ((c + r) & 3)]];
        }
      }
      if (round < _rounds) {
        for (var c = 0; c < 4; c++) {
          final a0 = tmp[4 * c], a1 = tmp[4 * c + 1], a2 = tmp[4 * c + 2], a3 = tmp[4 * c + 3];
          s[4 * c] = _mul2[a0] ^ _mul3[a1] ^ a2 ^ a3;
          s[4 * c + 1] = a0 ^ _mul2[a1] ^ _mul3[a2] ^ a3;
          s[4 * c + 2] = a0 ^ a1 ^ _mul2[a2] ^ _mul3[a3];
          s[4 * c + 3] = _mul3[a0] ^ a1 ^ a2 ^ _mul2[a3];
        }
      } else {
        s.setAll(0, tmp);
      }
      _addRoundKey(s, round);
    }
    out.setRange(outOff, outOff + 16, s);
  }

  void decryptBlock(Uint8List input, int inOff, Uint8List out, int outOff) {
    final s = _state..setRange(0, 16, input, inOff);
    final tmp = _scratch;
    _addRoundKey(s, _rounds);
    for (var round = _rounds - 1; round >= 0; round--) {
      for (var c = 0; c < 4; c++) {
        for (var r = 0; r < 4; r++) {
          tmp[r + 4 * ((c + r) & 3)] = _invSbox[s[r + 4 * c]];
        }
      }
      s.setAll(0, tmp);
      _addRoundKey(s, round);
      if (round > 0) {
        for (var c = 0; c < 4; c++) {
          final a0 = s[4 * c], a1 = s[4 * c + 1], a2 = s[4 * c + 2], a3 = s[4 * c + 3];
          s[4 * c] = _mul14[a0] ^ _mul11[a1] ^ _mul13[a2] ^ _mul9[a3];
          s[4 * c + 1] = _mul9[a0] ^ _mul14[a1] ^ _mul11[a2] ^ _mul13[a3];
          s[4 * c + 2] = _mul13[a0] ^ _mul9[a1] ^ _mul14[a2] ^ _mul11[a3];
          s[4 * c + 3] = _mul11[a0] ^ _mul13[a1] ^ _mul9[a2] ^ _mul14[a3];
        }
      }
    }
    out.setRange(outOff, outOff + 16, s);
  }
}

/// CBC encryption. With [pad] the data gets PKCS#7 padding, otherwise its length must be a multiple of 16.
Uint8List aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List data, {bool pad = true}) {
  final aes = Aes(key);
  final padLen = pad ? 16 - data.length % 16 : 0;
  if (!pad && data.length % 16 != 0) throw ArgumentError('Data must be a multiple of 16 bytes');
  final input = Uint8List(data.length + padLen)..setAll(0, data);
  for (var i = data.length; i < input.length; i++) {
    input[i] = padLen;
  }
  final out = Uint8List(input.length);
  final prev = Uint8List.fromList(iv);
  final block = Uint8List(16);
  for (var o = 0; o < input.length; o += 16) {
    for (var i = 0; i < 16; i++) {
      block[i] = input[o + i] ^ prev[i];
    }
    aes.encryptBlock(block, 0, out, o);
    prev.setRange(0, 16, out, o);
  }
  return out;
}

/// CBC decryption. With [unpad] the PKCS#7 padding is removed; damaged padding is left as it is.
Uint8List aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List data, {bool unpad = true}) {
  final aes = Aes(key);
  final length = data.length - data.length % 16;
  final out = Uint8List(length);
  final prev = Uint8List.fromList(iv);
  final block = Uint8List(16);
  for (var o = 0; o < length; o += 16) {
    aes.decryptBlock(data, o, block, 0);
    for (var i = 0; i < 16; i++) {
      out[o + i] = block[i] ^ prev[i];
    }
    prev.setRange(0, 16, data, o);
  }
  if (!unpad || out.isEmpty) return out;
  final n = out.last;
  if (n < 1 || n > 16 || n > out.length) return out;
  for (var i = out.length - n; i < out.length; i++) {
    if (out[i] != n) return out;
  }
  return Uint8List.sublistView(out, 0, out.length - n);
}

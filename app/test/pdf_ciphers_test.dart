import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/pdf_tools/data/security/ciphers.dart';

Uint8List hex(String s) => Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String toHex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('RC4', () {
    test('matches the published test vectors', () {
      expect(toHex(rc4(Uint8List.fromList(utf8.encode('Key')), Uint8List.fromList(utf8.encode('Plaintext')))), 'bbf316e8d940af0ad3');
      expect(toHex(rc4(Uint8List.fromList(utf8.encode('Wiki')), Uint8List.fromList(utf8.encode('pedia')))), '1021bf0420');
    });

    test('decrypting is the same operation', () {
      final key = Uint8List.fromList([1, 2, 3, 4, 5]);
      final data = Uint8List.fromList(List.generate(300, (i) => i & 0xFF));
      expect(rc4(key, rc4(key, data)), data);
    });
  });

  group('AES', () {
    test('AES-128 block matches FIPS-197', () {
      final aes = Aes(hex('000102030405060708090a0b0c0d0e0f'));
      final out = Uint8List(16);
      aes.encryptBlock(hex('00112233445566778899aabbccddeeff'), 0, out, 0);
      expect(toHex(out), '69c4e0d86a7b0430d8cdb78070b4c55a');
      final back = Uint8List(16);
      aes.decryptBlock(out, 0, back, 0);
      expect(toHex(back), '00112233445566778899aabbccddeeff');
    });

    test('AES-256 block matches FIPS-197', () {
      final aes = Aes(hex('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'));
      final out = Uint8List(16);
      aes.encryptBlock(hex('00112233445566778899aabbccddeeff'), 0, out, 0);
      expect(toHex(out), '8ea2b7ca516745bfeafc49904b496089');
      final back = Uint8List(16);
      aes.decryptBlock(out, 0, back, 0);
      expect(toHex(back), '00112233445566778899aabbccddeeff');
    });

    test('CBC matches NIST SP 800-38A', () {
      final key = hex('2b7e151628aed2a6abf7158809cf4f3c');
      final iv = hex('000102030405060708090a0b0c0d0e0f');
      final plain = hex('6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e51');
      final cipher = aesCbcEncrypt(key, iv, plain, pad: false);
      expect(toHex(cipher), '7649abac8119b246cee98e9b12e9197d5086cb9b507219ee95db113a917678b2');
      expect(aesCbcDecrypt(key, iv, cipher, unpad: false), plain);
    });

    test('CBC with 256 bit key matches NIST SP 800-38A', () {
      final key = hex('603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4');
      final iv = hex('000102030405060708090a0b0c0d0e0f');
      final plain = hex('6bc1bee22e409f96e93d7e117393172a');
      expect(toHex(aesCbcEncrypt(key, iv, plain, pad: false)), 'f58c4c04d6e5f1ba779eabfb5f7bfbd6');
    });

    test('padding round trip for every length', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final iv = Uint8List.fromList(List.generate(16, (i) => 255 - i));
      for (var n = 0; n <= 40; n++) {
        final data = Uint8List.fromList(List.generate(n, (i) => (i * 7) & 0xFF));
        final enc = aesCbcEncrypt(key, iv, data);
        expect(enc.length % 16, 0);
        expect(enc.length, greaterThan(n));
        expect(aesCbcDecrypt(key, iv, enc), data, reason: 'length $n');
      }
    });

    test('damaged padding and short input do not throw', () {
      final key = Uint8List(16);
      final iv = Uint8List(16);
      expect(aesCbcDecrypt(key, iv, Uint8List(0)), isEmpty);
      expect(aesCbcDecrypt(key, iv, Uint8List(7)), isEmpty);
      expect(() => aesCbcDecrypt(key, iv, Uint8List(32)), returnsNormally);
    });

    test('a key of the wrong size is refused', () {
      expect(() => Aes(Uint8List(24)), throwsArgumentError);
    });
  });
}

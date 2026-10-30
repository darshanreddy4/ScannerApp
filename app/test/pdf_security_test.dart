import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_model.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_rewriter.dart';
import 'package:doculoom/features/pdf_tools/data/security/pdf_security.dart';

Uint8List fixture(String name) => File('test/fixtures/pdf_security/$name.pdf').readAsBytesSync();

/// What a reader would show: every stream decompressed, strings of every object.
class Content {
  Content(Uint8List pdf) {
    final scan = scanPdf(pdf);
    trailer = scan.trailer;
    for (final e in scan.entries) {
      final o = e.object;
      if (o is PdfStream) {
        var data = o.data;
        final filter = o.dict['Filter'];
        if (filter is PdfName && filter.name == 'FlateDecode') {
          try {
            data = Uint8List.fromList(zlib.decode(data));
          } on Object {
            data = Uint8List(0);
          }
        }
        streams.add((o.dict, data));
      }
      _strings(o);
    }
  }

  late final PdfDict trailer;
  final streams = <(PdfDict, Uint8List)>[];
  final strings = <String>[];

  void _strings(PdfObj o) {
    switch (o) {
      case PdfString(:final bytes):
        strings.add(latin1.decode(bytes));
      case PdfArray(:final items):
        items.forEach(_strings);
      case PdfDict(:final entries):
        entries.values.forEach(_strings);
      case PdfStream(:final dict):
        _strings(dict);
      default:
    }
  }

  String get text => streams.map((s) => latin1.decode(s.$2, allowInvalid: true)).join('\n');
}

void expectReadable(Uint8List pdf) {
  final c = Content(pdf);
  expect(c.trailer['Encrypt'], isNull, reason: 'protection removed');
  expect(c.text, contains('Hello page 1'));
  expect(c.text, contains('Hello page 2'));
  expect(c.text, contains('Hello page 3'));
  expect(c.strings, contains('Quarterly report'));
  expect(c.strings, contains('Asha Traders'));
  expect(c.strings, containsAll(['Note 1', 'Note 2', 'Note 3']));
  final image = c.streams.firstWhere((s) => s.$1.nameOf('Subtype') == 'Image').$2;
  expect(image, [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0]);
}

void main() {
  group('reading PDF syntax', () {
    PdfObj parse(String s) => PdfLexer(Uint8List.fromList(latin1.encode(s))).parseObject();

    test('numbers, names, booleans and references', () {
      final d = parse('<< /A 12 /B -3.5 /C /Na#20me /D true /E null /F 7 0 R /G [1 2 0 R (x)] >>') as PdfDict;
      expect(d.intOf('A'), 12);
      expect((d['B'] as PdfReal).text, '-3.5');
      expect(d.nameOf('C'), 'Na me');
      expect(d.boolOf('D'), isTrue);
      expect(d['E'], isA<PdfNull>());
      expect((d['F'] as PdfRef).number, 7);
      final g = d['G'] as PdfArray;
      expect(g.items[0], isA<PdfInt>());
      expect(g.items[1], isA<PdfRef>());
    });

    test('literal strings with escapes, octal codes and balanced brackets', () {
      final s = parse(r'(a\(b\)\n(c)\101\\ \053)') as PdfString;
      expect(latin1.decode(s.bytes), 'a(b)\n(c)A\\ +');
    });

    test('hex strings with spaces and a missing last digit', () {
      expect((parse('<48 65 6C 6c 6F 5>') as PdfString).bytes, [0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x50]);
    });

    test('comments and nesting are skipped or kept', () {
      final d = parse('<< /K % comment\n [ << /X 1 >> ] >>') as PdfDict;
      expect(((d['K'] as PdfArray).items.single as PdfDict).intOf('X'), 1);
    });

    test('damaged syntax is reported, not crashed on', () {
      expect(() => parse('<< /A (unterminated >>'), throwsA(isA<PdfFormatException>()));
      expect(() => parse('[1 2'), throwsA(isA<PdfFormatException>()));
      expect(() => parse('<< 5 6 >>'), throwsA(isA<PdfFormatException>()));
      expect(() => parse('garbage'), throwsA(isA<PdfFormatException>()));
    });

    test('a file that is not a PDF is refused', () {
      expect(() => scanPdf(Uint8List.fromList(utf8.encode('hello world'))), throwsA(isA<PdfFormatException>()));
    });

    test('streams are cut by their length, and by endstream when the length is wrong or stored elsewhere', () {
      // The data contains the text "endstream" and ends with a line break that belongs to it.
      const payload = 'abc\nendstream\r\n';
      final pdf =
          '%PDF-1.4\n1 0 obj\n<< /Length ${payload.length} >>\nstream\n${payload}\nendstream\nendobj\n'
          '2 0 obj\n<< /Length 99999 >>\nstream\nshort\nendstream\nendobj\n'
          '3 0 obj\n<< /Length 4 0 R >>\nstream\nxy\r\n\nendstream\nendobj\n'
          '4 0 obj\n4\nendobj\n'
          'trailer\n<< /Root 9 0 R >>\n';
      final scan = scanPdf(Uint8List.fromList(latin1.encode(pdf)));
      String data(int n) => latin1.decode((scan.entries.firstWhere((e) => e.number == n).object as PdfStream).data);
      expect(data(1), payload);
      expect(data(2), 'short');
      expect(data(3), 'xy\r\n', reason: 'the stored length keeps the line break that is part of the data');
      expect((scan.trailer['Root'] as PdfRef).number, 9);
    });

    test('later versions of an object win and a damaged object is skipped', () {
      const pdf = '%PDF-1.4\n1 0 obj\n(old)\nendobj\n2 0 obj\n<< /Broken (\nendobj\n1 0 obj\n(new)\nendobj\n';
      final scan = scanPdf(Uint8List.fromList(latin1.encode(pdf)));
      final ones = scan.entries.where((e) => e.number == 1).toList();
      expect(latin1.decode((ones.last.object as PdfString).bytes), 'new');
      expect(scan.entries.where((e) => e.number == 2), isEmpty);
    });
  });

  group('inspecting', () {
    test('an ordinary PDF is not protected', () {
      for (final name in ['plain', 'plain_objstm', 'plain_linearized']) {
        final info = inspectPdf(fixture(name));
        expect((info.encrypted, info.needsPassword), (false, false), reason: name);
      }
    });

    test('every protection level asks for a password', () {
      for (final name in ['rc4_40', 'rc4_128', 'aes128', 'aes128_clear_metadata', 'aes256', 'aes256_objstm', 'aes256_r5', 'aes256_unicode']) {
        final info = inspectPdf(fixture(name));
        expect((info.encrypted, info.needsPassword), (true, true), reason: name);
      }
    });

    test('a PDF that only restricts printing opens without a password', () {
      final info = inspectPdf(fixture('aes256_empty_user'));
      expect((info.encrypted, info.needsPassword), (true, false));
    });
  });

  group('unlocking', () {
    for (final name in ['rc4_40', 'rc4_128', 'aes128', 'aes128_clear_metadata', 'aes256', 'aes256_objstm', 'aes256_r5']) {
      test('$name opens with the password and keeps text, images and details', () {
        expectReadable(unlockPdf(fixture(name), password: 'secret'));
      });

      test('$name also opens with the owner password', () {
        expectReadable(unlockPdf(fixture(name), password: 'owner'));
      });

      test('$name refuses a wrong password', () {
        expect(() => unlockPdf(fixture(name), password: 'wrong'), throwsA(isA<WrongPasswordException>()));
        expect(() => unlockPdf(fixture(name), password: ''), throwsA(isA<WrongPasswordException>()));
      });
    }

    test('a password with accents works', () {
      expectReadable(unlockPdf(fixture('aes256_unicode'), password: 'pässwörd'));
      expect(() => unlockPdf(fixture('aes256_unicode'), password: 'passwoerd'), throwsA(isA<WrongPasswordException>()));
    });

    test('a PDF with only print restrictions is unlocked with an empty password', () {
      expectReadable(unlockPdf(fixture('aes256_empty_user'), password: ''));
    });

    test('the result is an ordinary PDF that can be read again', () {
      final once = unlockPdf(fixture('aes256_objstm'), password: 'secret');
      final text = String.fromCharCodes(once);
      expect(text, startsWith('%PDF-'));
      expect(text, contains('%%EOF'));
      expect(text, isNot(contains('/Encrypt')));
      expect(text, isNot(contains('/ObjStm')));
      expect(inspectPdf(once).encrypted, isFalse);
      expectReadable(once);
    });

    test('an unprotected PDF cannot be unlocked', () {
      expect(() => unlockPdf(fixture('plain'), password: 'x'), throwsA(isA<NotProtectedException>()));
    });

    test('unlocking leaves the original bytes alone', () {
      final original = fixture('aes256');
      final copy = Uint8List.fromList(original);
      unlockPdf(original, password: 'secret');
      expect(original, copy);
    });
  });

  group('locking', () {
    test('an ordinary PDF becomes protected and opens only with the password', () {
      for (final name in ['plain', 'plain_objstm', 'plain_linearized']) {
        final locked = lockPdf(fixture(name), password: 'Tr0ub4dor&3');
        final info = inspectPdf(locked);
        expect((info.encrypted, info.needsPassword), (true, true), reason: name);
        expectReadable(unlockPdf(locked, password: 'Tr0ub4dor&3'));
        expect(() => unlockPdf(locked, password: 'tr0ub4dor&3'), throwsA(isA<WrongPasswordException>()), reason: name);
        expect(() => unlockPdf(locked, password: ''), throwsA(isA<WrongPasswordException>()), reason: name);
      }
    });

    test('the locked file hides the text, strings and image', () {
      final locked = lockPdf(fixture('plain'), password: 'pw');
      final raw = latin1.decode(locked, allowInvalid: true);
      expect(raw, isNot(contains('Hello page')));
      expect(raw, isNot(contains('Quarterly report')));
      expect(raw, contains('/Encrypt'));
      expect(raw, contains('/AESV3'));
      final c = Content(locked);
      expect(c.text, isNot(contains('Hello page 1')));
      expect(c.strings, isNot(contains('Asha Traders')));
    });

    test('each lock uses fresh keys, and a fixed random source gives the same file', () {
      final a = lockPdf(fixture('plain'), password: 'pw');
      final b = lockPdf(fixture('plain'), password: 'pw');
      expect(a, isNot(b));
      expect(lockPdf(fixture('plain'), password: 'pw', random: Random(7)), lockPdf(fixture('plain'), password: 'pw', random: Random(7)));
    });

    test('long and unusual passwords work', () {
      for (final pw in ['a', 'ä€語🔒', 'x' * 200, 'with space and "quotes"']) {
        final locked = lockPdf(fixture('plain'), password: pw);
        expectReadable(unlockPdf(locked, password: pw));
      }
    });

    test('a protected PDF cannot be locked again', () {
      expect(() => lockPdf(fixture('aes256'), password: 'x'), throwsA(isA<AlreadyProtectedException>()));
    });

    test('lock and unlock keep the page tree, so every page is still there', () {
      final locked = lockPdf(fixture('plain'), password: 'pw');
      final back = unlockPdf(locked, password: 'pw');
      int pages(Uint8List b) => scanPdf(b).entries.where((e) => e.object is PdfDict && (e.object as PdfDict).nameOf('Type') == 'Page').length;
      expect(pages(back), pages(fixture('plain')));
      expect(pages(back), 3);
    });

    test('a damaged file is reported', () {
      final bad = Uint8List.fromList(utf8.encode('%PDF-1.4\nnothing here\n'));
      expect(() => lockPdf(bad, password: 'x'), throwsA(isA<PdfFormatException>()));
    });

    test('a large file is handled in reasonable time', () {
      final big = Uint8List(4 * 1024 * 1024);
      final r = Random(1);
      for (var i = 0; i < big.length; i++) {
        big[i] = r.nextInt(256);
      }
      final head = latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Big 3 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [] /Count 0 >>\nendobj\n3 0 obj\n<< /Length ${big.length} >>\nstream\n',
      );
      final tail = latin1.encode('\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n');
      final file = Uint8List.fromList([...head, ...big, ...tail]);
      final sw = Stopwatch()..start();
      final locked = lockPdf(file, password: 'pw');
      final back = unlockPdf(locked, password: 'pw');
      expect(sw.elapsed.inSeconds, lessThan(60));
      expect(back.length, greaterThan(big.length));
    });
  });
}

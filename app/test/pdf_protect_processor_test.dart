import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/features/pdf_tools/data/pdf_protect_processor.dart';

void main() {
  late Directory dir;
  const protector = PdfProtectProcessor();

  setUp(() => dir = Directory.systemTemp.createTempSync('sv_prot'));
  tearDown(() => dir.deleteSync(recursive: true));

  String fixture(String name) => p.absolute('test/fixtures/pdf_security/$name.pdf');
  String out(String name) => p.join(dir.path, name);

  test('inspect reports whether a password is needed', () async {
    final plain = (await protector.inspect(fixture('plain'))).valueOrNull!;
    expect((plain.encrypted, plain.needsPassword), (false, false));
    expect(plain.bytes, File(fixture('plain')).lengthSync());
    final locked = (await protector.inspect(fixture('aes256'))).valueOrNull!;
    expect((locked.encrypted, locked.needsPassword), (true, true));
    final restricted = (await protector.inspect(fixture('aes256_empty_user'))).valueOrNull!;
    expect((restricted.encrypted, restricted.needsPassword), (true, false));
  });

  test('lock writes a protected copy and unlock brings the same content back', () async {
    final locked = (await protector.lock(sourcePath: fixture('plain'), outputPath: out('locked.pdf'), password: 'Sunrise 2026')).valueOrNull!;
    expect(File(locked.path).existsSync(), isTrue);
    expect(locked.bytes, File(locked.path).lengthSync());
    expect((await protector.inspect(locked.path)).valueOrNull!.needsPassword, isTrue);
    final opened = (await protector.unlock(sourcePath: locked.path, outputPath: out('open.pdf'), password: 'Sunrise 2026')).valueOrNull!;
    expect((await protector.inspect(opened.path)).valueOrNull!.encrypted, isFalse);
  });

  test('a wrong password gives a password failure and writes nothing', () async {
    final r = await protector.unlock(sourcePath: fixture('aes128'), outputPath: out('x.pdf'), password: 'nope');
    expect(r.failureOrNull, isA<PasswordFailure>());
    expect(r.failureOrNull!.message, 'That password is not correct.');
    expect(File(out('x.pdf')).existsSync(), isFalse);
  });

  test('the right password unlocks every kind of protection', () async {
    for (final name in ['rc4_40', 'rc4_128', 'aes128', 'aes256', 'aes256_r5']) {
      final r = await protector.unlock(sourcePath: fixture(name), outputPath: out('$name.pdf'), password: 'secret');
      expect(r.failureOrNull, isNull, reason: name);
      expect(File(out('$name.pdf')).existsSync(), isTrue);
    }
  });

  test('mistakes are explained in plain words', () async {
    expect(
      (await protector.unlock(sourcePath: fixture('plain'), outputPath: out('a.pdf'), password: 'x')).failureOrNull!.message,
      contains('nothing to unlock'),
    );
    expect(
      (await protector.lock(sourcePath: fixture('aes256'), outputPath: out('b.pdf'), password: 'x')).failureOrNull!.message,
      contains('already has a password'),
    );
    expect((await protector.lock(sourcePath: fixture('plain'), outputPath: out('c.pdf'), password: '')).failureOrNull, isA<PasswordFailure>());
    expect((await protector.inspect(p.join(dir.path, 'missing.pdf'))).failureOrNull!.message, contains('could not be found'));
    final junk = File(out('junk.pdf'))..writeAsStringSync('this is not a pdf');
    expect((await protector.inspect(junk.path)).failureOrNull!.message, contains('not a readable PDF'));
    final noCatalog = File(out('empty.pdf'))..writeAsStringSync('%PDF-1.4\n1 0 obj\n<< /A 1 >>\nendobj\ntrailer\n<< >>\n');
    expect((await protector.lock(sourcePath: noCatalog.path, outputPath: out('d.pdf'), password: 'x')).failureOrNull!.message, contains('not a readable PDF'));
  });
}

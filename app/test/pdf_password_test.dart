import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:scanvault/app/di.dart';
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/core/theme/app_theme.dart';
import 'package:scanvault/features/pdf_tools/domain/pdf_protector.dart';
import 'package:scanvault/features/pdf_tools/presentation/pdf_password_cubit.dart';
import 'package:scanvault/features/pdf_tools/presentation/pdf_password_page.dart';

class _Protector implements PdfProtector {
  PdfProtectionStatus status = const PdfProtectionStatus(encrypted: false, needsPassword: false, bytes: 2048);
  Failure? inspectFailure;
  String? rightPassword;
  String? lastLockPassword;
  String? lastUnlockPassword;
  var locks = 0;
  var unlocks = 0;

  @override
  Future<Result<PdfProtectionStatus>> inspect(String path) async => inspectFailure != null ? Err(inspectFailure!) : Ok(status);

  @override
  Future<Result<ProtectedPdf>> lock({required String sourcePath, required String outputPath, required String password}) async {
    locks++;
    lastLockPassword = password;
    File(outputPath).writeAsBytesSync([1, 2, 3]);
    return Ok(ProtectedPdf(path: outputPath, bytes: 3000, originalBytes: 2048));
  }

  @override
  Future<Result<ProtectedPdf>> unlock({required String sourcePath, required String outputPath, required String password}) async {
    unlocks++;
    lastUnlockPassword = password;
    if (rightPassword != null && password != rightPassword) return const Err(PasswordFailure('That password is not correct.'));
    File(outputPath).writeAsBytesSync([1, 2, 3]);
    return Ok(ProtectedPdf(path: outputPath, bytes: 1900, originalBytes: 2048));
  }
}

void main() {
  late Directory dir;
  late _Protector protector;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sv_pwd');
    protector = _Protector();
    File(p.join(dir.path, 'Bank statement.pdf')).writeAsBytesSync([1]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String pdf() => p.join(dir.path, 'Bank statement.pdf');

  group('cubit', () {
    PdfPasswordCubit make() => PdfPasswordCubit(protector: protector, outputDir: () async => dir);

    test('an unprotected PDF can be locked once two matching passwords are typed', () async {
      final c = make();
      expect(c.state.blocker, 'Choose a PDF first.');
      await c.pick(pdf());
      expect(c.state.canLock, isTrue);
      expect(c.state.blocker, contains('at least 4'));
      c.setPassword('abcd');
      expect(c.state.blocker, 'The two passwords are not the same.');
      c.setConfirm('abcd');
      expect(c.state.blocker, isNull);
      await c.run();
      expect(protector.lastLockPassword, 'abcd');
      expect(c.state.status, PasswordStatus.done);
      expect(c.state.lockedNow, isTrue);
      expect(c.state.result!.path, contains('Bank statement_locked_'));
      await c.close();
    });

    test('the button does nothing until the rules are met', () async {
      final c = make();
      await c.pick(pdf());
      c.setPassword('abc');
      c.setConfirm('abc');
      await c.run();
      expect(protector.locks, 0);
      expect(c.state.failure!.message, contains('at least 4'));
      await c.close();
    });

    test('a protected PDF needs its password to be unlocked', () async {
      protector.status = const PdfProtectionStatus(encrypted: true, needsPassword: true, bytes: 100);
      protector.rightPassword = 'secret';
      final c = make();
      await c.pick(pdf());
      expect(c.state.canUnlock, isTrue);
      expect(c.state.blocker, 'Type the password.');
      c.setPassword('wrong');
      await c.run();
      expect(c.state.failure, isA<PasswordFailure>());
      expect(c.state.result, isNull);
      c.setPassword('secret');
      expect(c.state.failure, isNull, reason: 'typing clears the old message');
      await c.run();
      expect(c.state.result, isNotNull);
      expect(c.state.lockedNow, isFalse);
      expect(c.state.result!.path, contains('_unlocked_'));
      await c.close();
    });

    test('a PDF with only restrictions is unlocked without a password', () async {
      protector.status = const PdfProtectionStatus(encrypted: true, needsPassword: false, bytes: 100);
      final c = make();
      await c.pick(pdf());
      expect(c.state.blocker, isNull);
      await c.run();
      expect(protector.lastUnlockPassword, '');
      expect(c.state.result, isNotNull);
      await c.close();
    });

    test('a file that cannot be checked is reported and nothing is kept', () async {
      protector.inspectFailure = const ExportFailure('This file is not a readable PDF.');
      final c = make();
      await c.pick(pdf());
      expect(c.state.path, isNull);
      expect(c.state.failure!.message, contains('not a readable PDF'));
      await c.close();
    });

    test('choosing another file starts again and clear empties everything', () async {
      final c = make();
      await c.pick(pdf());
      c.setPassword('abcd');
      c.setConfirm('abcd');
      await c.run();
      await c.pick(pdf());
      expect(c.state.password, isEmpty);
      expect(c.state.result, isNull);
      c.clear();
      expect(c.state.path, isNull);
      await c.close();
    });
  });

  group('page', () {
    Future<PdfPasswordCubit> open(WidgetTester tester, {double width = 400}) async {
      tester.view.physicalSize = Size(width * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      await sl.reset();
      sl.registerSingleton<PdfProtector>(protector);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const PdfPasswordPage()));
      await tester.pump();
      return tester.element(find.byType(Scaffold).first).read<PdfPasswordCubit>();
    }

    Future<void> see(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(f);
      await tester.pump();
    }

    testWidgets('starts with a choose button and an honest note', (tester) async {
      await open(tester);
      expect(find.text('Choose a PDF'), findsOneWidget);
      expect(find.textContaining('cannot recover forgotten passwords'), findsOneWidget);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('locking: two fields, a hint and a result at ${width.toInt()} px', (tester) async {
        final cubit = await open(tester, width: width);
        await tester.runAsync(() => cubit.pick(pdf()));
        await tester.pump();
        expect(find.text('Bank statement.pdf'), findsOneWidget);
        expect(find.textContaining('No password'), findsOneWidget);
        expect(find.text('Password'), findsOneWidget);
        expect(find.text('Repeat the password'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'Password'), 'Sunrise1');
        await tester.enterText(find.widgetWithText(TextField, 'Repeat the password'), 'Sunrise');
        await tester.pump();
        expect(find.text('The two passwords are not the same.'), findsOneWidget);
        await tester.enterText(find.widgetWithText(TextField, 'Repeat the password'), 'Sunrise1');
        await tester.pump();
        final lock = find.widgetWithText(FilledButton, 'Lock PDF');
        await see(tester, lock);
        expect(tester.widget<FilledButton>(lock).onPressed, isNotNull);
        await tester.runAsync(cubit.run);
        await tester.pump();
        expect(protector.lastLockPassword, 'Sunrise1');
        final done = find.text('Your PDF is locked');
        await see(tester, done);
        expect(done, findsOneWidget);
        expect(find.text('Share'), findsOneWidget);
        expect(find.text('Save to Files'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the password can be shown and hidden', (tester) async {
      final cubit = await open(tester);
      await tester.runAsync(() => cubit.pick(pdf()));
      await tester.pump();
      bool obscured() => tester.widget<TextField>(find.widgetWithText(TextField, 'Password')).obscureText;
      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(obscured(), isFalse);
    });

    testWidgets('unlocking: a wrong password is shown under the field, then the right one works', (tester) async {
      protector.status = const PdfProtectionStatus(encrypted: true, needsPassword: true, bytes: 100);
      protector.rightPassword = 'secret';
      final cubit = await open(tester);
      await tester.runAsync(() => cubit.pick(pdf()));
      await tester.pump();
      expect(find.textContaining('Protected with a password'), findsOneWidget);
      expect(find.text('Repeat the password'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'nope');
      final unlock = find.widgetWithText(FilledButton, 'Unlock PDF');
      await see(tester, unlock);
      await tester.runAsync(cubit.run);
      await tester.pump();
      expect(find.text('That password is not correct.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'secret');
      await tester.pump();
      await see(tester, unlock);
      await tester.runAsync(cubit.run);
      await tester.pump();
      final done = find.text('Your PDF is unlocked');
      await see(tester, done);
      expect(done, findsOneWidget);
    });

    testWidgets('a PDF with restrictions only offers to remove them', (tester) async {
      protector.status = const PdfProtectionStatus(encrypted: true, needsPassword: false, bytes: 100);
      final cubit = await open(tester);
      await tester.runAsync(() => cubit.pick(pdf()));
      await tester.pump();
      expect(find.textContaining('opens without a password'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Remove restrictions'), findsOneWidget);
    });
  });
}

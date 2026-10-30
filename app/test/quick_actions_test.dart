import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/app/quick_actions.dart';
import 'package:doculoom/features/importer/domain/importer.dart';
import 'package:doculoom/features/reader/presentation/reader_page.dart';

void main() {
  test('every action has an id that comes back unchanged and a screen', () {
    for (final a in QuickAction.values) {
      expect(quickActionFrom(a.id), a);
      expect(a.route, startsWith('/'));
    }
    expect(quickActionFrom('nope'), isNull);
    expect(quickActionFrom(null), isNull);
    expect(QuickAction.values.map((a) => a.id).toSet().length, QuickAction.values.length);
  });

  test('the Android shortcuts, widget and tiles use the same ids as the app', () {
    final res = 'android/app/src/main';
    final shortcuts = File('$res/res/xml/shortcuts.xml').readAsStringSync();
    final inShortcuts = RegExp(r'android:name="doculoom_quick" android:value="([a-z_]+)"').allMatches(shortcuts).map((m) => m[1]).toSet();
    expect(inShortcuts, QuickAction.values.map((a) => a.id).toSet());

    final kotlin = File('$res/kotlin/com/doculoom/app/QuickActions.kt').readAsStringSync();
    final constants = RegExp(r'const val [A-Z_]+ = "([a-z_]+)"').allMatches(kotlin).map((m) => m[1]!).toSet()..remove('doculoom_quick');
    expect(constants, QuickAction.values.map((a) => a.id).toSet());
    expect(kotlin, contains('EXTRA = "doculoom_quick"'));

    final manifest = File('$res/AndroidManifest.xml').readAsStringSync();
    for (final name in ['.QuickWidgetProvider', '.ScanTile', '.IdPhotoTile', '.ReadPdfTile']) {
      expect(manifest, contains('android:name="$name"'), reason: name);
    }
    expect(manifest, contains('android:resource="@xml/shortcuts"'));
    expect(File('$res/res/xml/quick_widget_info.xml').existsSync(), isTrue);
    expect(File('$res/res/layout/widget_quick.xml').existsSync(), isTrue);
    for (final icon in ['scan', 'id', 'pdf', 'qr']) {
      expect(File('$res/res/drawable/ic_qa_$icon.xml').existsSync(), isTrue, reason: icon);
    }
  });

  group('running an action', () {
    late GoRouter router;
    late BuildContext context;
    final opened = <String>[];

    Future<void> pumpApp(WidgetTester tester) async {
      opened.clear();
      router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, _) => Builder(
              builder: (c) {
                context = c;
                return const Scaffold(body: Text('home'));
              },
            ),
          ),
          GoRoute(
            path: '/scan',
            builder: (_, _) => const Scaffold(body: Text('camera')),
          ),
          GoRoute(
            path: '/passport-photo',
            builder: (_, _) => const Scaffold(body: Text('id photo')),
          ),
          GoRoute(
            path: '/qr-scan',
            builder: (_, _) => const Scaffold(body: Text('qr')),
          ),
          GoRoute(
            path: '/reader',
            builder: (_, state) {
              final a = state.extra! as ReaderArgs;
              return Scaffold(body: Text('reader ${a.path} ${a.kind.name}'));
            },
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    int depth() => router.routerDelegate.currentConfiguration.matches.length;

    testWidgets('scan hands over to the camera opener, and not when the camera is already open', (tester) async {
      await pumpApp(tester);
      await runQuickAction(context, QuickAction.scan, router: router, openScan: (c) => opened.add('scan'));
      expect(opened, ['scan']);
      router.push('/scan');
      await tester.pumpAndSettle();
      await runQuickAction(context, QuickAction.scan, router: router, openScan: (c) => opened.add('scan again'));
      expect(opened, ['scan']);
    });

    testWidgets('ID photo and QR scan open their screens once', (tester) async {
      await pumpApp(tester);
      await runQuickAction(context, QuickAction.idPhoto, router: router);
      await tester.pumpAndSettle();
      expect(find.text('id photo'), findsOneWidget);
      expect(depth(), 2);
      await runQuickAction(context, QuickAction.idPhoto, router: router);
      await tester.pumpAndSettle();
      expect(depth(), 2, reason: 'a second tap does not stack another copy');
      await runQuickAction(context, QuickAction.qrScan, router: router);
      await tester.pumpAndSettle();
      expect(find.text('qr'), findsOneWidget);
      expect(depth(), 3);
    });

    testWidgets('Read PDF asks for a file and opens it in the reader', (tester) async {
      await pumpApp(tester);
      unawaited(runQuickAction(context, QuickAction.readPdf, router: router, pickPdf: () async => '/files/a.PDF'));
      await tester.pumpAndSettle();
      expect(find.text('reader /files/a.PDF ${ImportKind.pdf.name}'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      unawaited(runQuickAction(context, QuickAction.readPdf, router: router, pickPdf: () async => '/files/b.docx'));
      await tester.pumpAndSettle();
      expect(find.text('reader /files/b.docx ${ImportKind.docx.name}'), findsOneWidget);
    });

    testWidgets('Read PDF can be used again from the reader, and a cancelled picker opens nothing', (tester) async {
      await pumpApp(tester);
      unawaited(runQuickAction(context, QuickAction.readPdf, router: router, pickPdf: () async => null));
      await tester.pumpAndSettle();
      expect(depth(), 1);
      unawaited(runQuickAction(context, QuickAction.readPdf, router: router, pickPdf: () async => '/a.pdf'));
      await tester.pumpAndSettle();
      unawaited(runQuickAction(context, QuickAction.readPdf, router: router, pickPdf: () async => '/b.pdf'));
      await tester.pumpAndSettle();
      expect(depth(), 3);
    });

    testWidgets('a file picker that fails is explained', (tester) async {
      await pumpApp(tester);
      unawaited(runQuickAction(context, QuickAction.readPdf, router: router, pickPdf: () async => throw Exception('no picker')));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('file picker is unavailable'), findsOneWidget);
      expect(depth(), 1);
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/ocr_tool/presentation/ocr_tool_cubit.dart';
import 'package:doculoom/features/ocr_tool/presentation/ocr_tool_page.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/speech/presentation/read_aloud_page.dart';
import 'package:doculoom/features/tools/presentation/tools_view.dart';

import 'support/ocr_tool_fakes.dart';
import 'support/pdf_ui_fakes.dart';

void main() {
  late Directory dir;
  late FakeTextReader reader;
  late FakeTranslator translator;

  setUp(() async {
    dir = tempDir();
    reader = FakeTextReader({'a.jpg': 'Hello world.', 'b.png': 'Second picture.', 'p0.jpg': 'Page one.', 'p1.jpg': 'Page two.', 'p2.jpg': 'Page three.'});
    translator = FakeTranslator();
    await sl.reset();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('reading files', () {
    OcrToolCubit make({int pdfPages = 3, int maxPdf = 60, OcrScript script = OcrScript.latin, String target = 'en'}) => OcrToolCubit(
      engine: reader,
      translator: translator,
      outputDir: () async => dir,
      script: script,
      target: target,
      pdfPages: () => FakePicturePages(pdfPages),
      maxPdfPages: maxPdf,
    );

    test('a picture is read with the chosen script and its text is the text', () async {
      final c = make(script: OcrScript.devanagari);
      await c.addFiles(['/x/a.jpg']);
      expect(c.state.status, OcrToolStatus.ready);
      expect(c.state.text, 'Hello world.');
      expect(reader.reads.single.script, OcrScript.devanagari);
      expect(c.state.failure, isNull);
      await c.close();
    });

    test('several pictures follow one another with a blank line between, and more can be added later', () async {
      final c = make();
      await c.addFiles(['/x/a.jpg', '/x/b.png']);
      expect(c.state.text, 'Hello world.\n\nSecond picture.');
      await c.addFiles(['/x/a.jpg']);
      expect(c.state.text, 'Hello world.\n\nSecond picture.\n\nHello world.');
      await c.close();
    });

    test('a PDF is read page by page and its temporary pictures are removed', () async {
      final c = make();
      await c.addFiles(['/x/report.pdf']);
      expect(c.state.text, 'Page one.\n\nPage two.\n\nPage three.');
      expect(reader.reads.length, 3);
      expect(Directory('${dir.path}/ocr_tool').listSync(), isEmpty, reason: 'working folders are removed');
      await c.close();
    });

    test('a long PDF is read up to the limit and says so', () async {
      final c = make(pdfPages: 5, maxPdf: 2);
      await c.addFiles(['/x/report.pdf']);
      expect(c.state.text, 'Page one.\n\nPage two.');
      expect(c.state.notes.single, contains('has 5 pages; the first 2 were read'));
      await c.close();
    });

    test('files that are not pictures or PDFs are skipped with a note, and the others are still read', () async {
      reader.texts['PHOTO.JPG'] = 'Hello world.';
      final c = make();
      await c.addFiles(['/x/notes.docx', '/x/PHOTO.JPG']);
      expect(c.state.text, 'Hello world.');
      expect(c.state.notes.single, contains('"notes.docx" is not a picture or a PDF'));
      await c.close();
    });

    test('a picture that cannot be read is noted by name and does not stop the rest', () async {
      reader.failing.add('a.jpg');
      final c = make();
      await c.addFiles(['/x/a.jpg', '/x/b.png']);
      expect(c.state.text, 'Second picture.');
      expect(c.state.notes.single, allOf(contains('Could not read "a.jpg"'), contains('could not be read')));
      await c.close();
    });

    test('a PDF that cannot be opened is noted and the rest goes on', () async {
      final c = OcrToolCubit(engine: reader, translator: translator, outputDir: () async => dir, pdfPages: () => FakePicturePages(1, failOpen: true));
      await c.addFiles(['/x/locked.pdf', '/x/a.jpg']);
      expect(c.state.text, 'Hello world.');
      expect(c.state.notes.single, contains('Could not open "locked.pdf"'));
      await c.close();
    });

    test('pictures with no text give a message and an empty text', () async {
      final c = make();
      await c.addFiles(['/x/blank.jpg']);
      expect(c.state.hasText, isFalse);
      expect(c.state.failure?.message, contains('No text was found'));
      await c.addFiles(['/x/a.jpg']);
      expect(c.state.failure, isNull, reason: 'a later reading that finds text clears the message');
      await c.close();
    });

    test('Stop ends the reading, keeps what was read and says so', () async {
      final c = make();
      reader.hold = Completer<void>();
      final done = c.addFiles(['/x/a.jpg', '/x/b.png']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.state.reading, isTrue);
      c.cancel();
      reader.hold!.complete();
      await done;
      expect(c.state.text, 'Hello world.');
      expect(c.state.notes.last, contains('Stopped'));
      expect(reader.reads, hasLength(1));
      await c.close();
    });

    test('nothing happens while it is already reading, or when no files are given', () async {
      final c = make();
      await c.addFiles(const []);
      expect(c.state.status, OcrToolStatus.idle);
      reader.hold = Completer<void>();
      final first = c.addFiles(['/x/a.jpg']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.addFiles(['/x/b.png']);
      reader.hold!.complete();
      await first;
      expect(c.state.text, 'Hello world.');
      await c.close();
    });

    test('the script can be changed only when not reading, and Clear empties the text but keeps the choices', () async {
      final c = make(target: 'fr');
      c.setScript(OcrScript.devanagari);
      await c.addFiles(['/x/a.jpg']);
      c.clear();
      expect(c.state.text, '');
      expect(c.state.script, OcrScript.devanagari);
      expect(c.state.target, 'fr');
      expect(c.state.status, OcrToolStatus.idle);
      await c.close();
    });
  });

  group('translating', () {
    OcrToolCubit make({String target = 'hi'}) =>
        OcrToolCubit(engine: reader, translator: translator, outputDir: () async => dir, target: target, pdfPages: () => FakePicturePages(1));

    Future<OcrToolCubit> withText({String target = 'hi', String file = 'a.jpg'}) async {
      final c = make(target: target);
      await c.addFiles(['/x/$file']);
      return c;
    }

    test('the language is found by the phone, the data is there, and the text is translated', () async {
      translator.downloaded.addAll(['en', 'hi']);
      final c = await withText();
      await c.translate();
      expect(translator.detectCalls, ['Hello world.']);
      expect(c.state.source, 'en');
      expect(c.state.sourceDetected, isTrue);
      expect(c.state.translate, TranslateStatus.done);
      expect(c.state.translated, '[hi] Hello world.');
      expect(translator.downloads, isEmpty);
      await c.close();
    });

    test('a language chosen by the person is used without detecting', () async {
      translator.downloaded.addAll(['fr', 'hi', 'en']);
      final c = await withText();
      c.setSource('fr');
      await c.translate();
      expect(translator.detectCalls, isEmpty);
      expect(translator.translations.single.from, 'fr');
      expect(c.state.sourceDetected, isFalse);
      await c.close();
    });

    test('when language data is missing it asks first, naming what is needed, and nothing is downloaded yet', () async {
      final c = await withText(target: 'hi');
      translator.detectResult = 'fr';
      await c.translate();
      expect(c.state.translate, TranslateStatus.needsDownload);
      expect(c.state.pending, ['fr', 'hi', 'en'], reason: 'English is the go-between for two other languages');
      expect(translator.downloads, isEmpty);
      expect(translator.translations, isEmpty);
      await c.close();
    });

    test('after agreeing, the data is downloaded one language at a time and the text is translated', () async {
      final c = await withText(target: 'hi');
      await c.translate();
      expect(c.state.pending, ['en', 'hi']);
      await c.confirmDownloadAndTranslate();
      expect(translator.downloads, ['en', 'hi']);
      expect(c.state.translate, TranslateStatus.done);
      expect(c.state.pending, isEmpty);
      await c.close();
    });

    test('only the data that is missing is downloaded', () async {
      translator.downloaded.add('en');
      final c = await withText(target: 'hi');
      await c.translate();
      expect(c.state.pending, ['hi']);
      await c.confirmDownloadAndTranslate();
      expect(translator.downloads, ['hi']);
      await c.close();
    });

    test('Not now leaves the text as it is, and a failed download says which language and why', () async {
      final c = await withText(target: 'hi');
      await c.translate();
      c.dismissDownload();
      expect(c.state.translate, TranslateStatus.idle);
      expect(c.state.pending, isEmpty);

      translator.failDownload = true;
      await c.translate();
      await c.confirmDownloadAndTranslate();
      expect(c.state.translate, TranslateStatus.failed);
      expect(c.state.translateMessage, allOf(contains('English'), contains('could not be downloaded'), contains('internet')));
      expect(c.state.translated, isNull);
      await c.close();
    });

    test('a text whose language cannot be told asks the person to choose it', () async {
      translator.detectResult = null;
      final c = await withText();
      await c.translate();
      expect(c.state.translate, TranslateStatus.failed);
      expect(c.state.translateMessage, contains('Choose it under "From"'));
      expect(translator.downloads, isEmpty);
      await c.close();
    });

    test('the same language on both sides is refused with its name', () async {
      translator.detectResult = 'hi';
      final c = await withText(target: 'hi');
      await c.translate();
      expect(c.state.translateMessage, contains('already in Hindi'));
      await c.close();
    });

    test('no text to translate is said plainly', () async {
      final c = make();
      await c.translate();
      expect(c.state.translate, TranslateStatus.failed);
      expect(c.state.translateMessage, contains('no text'));
      await c.close();
    });

    test('a long text is translated passage by passage with progress, and the paragraphs are kept', () async {
      translator.downloaded.addAll(['en', 'hi']);
      reader.texts['long.jpg'] = 'Heading\n\nFirst paragraph here.\n\nSecond paragraph here.';
      final c = await withText(file: 'long.jpg');
      final seen = <String>[];
      final sub = c.stream.listen((s) {
        if (s.translateTotal > 0) seen.add('${s.translateDone}/${s.translateTotal}');
      });
      await c.translate();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(c.state.translated, '[hi] Heading\n\n[hi] First paragraph here.\n\n[hi] Second paragraph here.');
      expect(seen, containsAllInOrder(['1/3', '2/3', '3/3']));
      await c.close();
    });

    test('a translator that fails gives a message and no translation, and Stop ends it quietly', () async {
      translator.downloaded.addAll(['en', 'hi']);
      translator.failTranslate = StateError('boom');
      final c = await withText();
      await c.translate();
      expect(c.state.translate, TranslateStatus.failed);
      expect(c.state.translateMessage, contains('could not be translated'));
      expect(c.state.translated, isNull);

      translator
        ..failTranslate = null
        ..hold = Completer<void>();
      final run = c.translate();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.state.translating, isTrue);
      c.cancelTranslation();
      translator.hold!.complete();
      await run;
      expect(c.state.translate, TranslateStatus.idle);
      expect(c.state.translated, isNull);
      await c.close();
    });

    test('changing the languages or editing the text drops an old translation, and a language chosen by hand survives an edit', () async {
      translator.downloaded.addAll(['en', 'hi', 'es']);
      final c = await withText();
      await c.translate();
      expect(c.state.translated, isNotNull);
      c.setTarget('es');
      expect(c.state.translated, isNull);
      expect(c.state.translate, TranslateStatus.idle);

      await c.translate();
      c.setText('Changed text.');
      expect(c.state.translated, isNull);
      expect(c.state.source, isNull, reason: 'a detected language is found again for the new text');

      c.setSource('en');
      c.setText('Changed again.');
      expect(c.state.source, 'en');
      c.setTarget('xx');
      expect(c.state.target, 'es', reason: 'an unknown language is not accepted');
      await c.close();
    });

    test('the translation can become the text, with the languages turned round so it can go back', () async {
      translator.downloaded.addAll(['en', 'hi']);
      final c = await withText(target: 'hi');
      await c.translate();
      c.useTranslationAsText();
      expect(c.state.text, '[hi] Hello world.');
      expect(c.state.source, 'hi');
      expect(c.state.target, 'en');
      expect(c.state.translated, isNull);
      await c.translate();
      expect(c.state.translated, '[en] [hi] Hello world.');
      await c.close();
    });

    test('the phone\'s own language is the first target; when it is English the first target is Hindi', () {
      expect(make(target: 'xx').state.target, 'en');
      expect(make(target: 'es').state.target, 'es');
    });

    test('language data on the phone can be listed and removed', () async {
      translator.downloaded.addAll(['en', 'hi']);
      final c = make();
      expect(await c.downloadedLanguages(), ['en', 'hi']);
      await c.deleteLanguage('hi');
      expect(translator.deleted, ['hi']);
      expect(await c.downloadedLanguages(), ['en']);
      await c.close();
    });
  });

  group('the screen', () {
    late FakeShare share;
    late List<Object?> spoken;

    Future<void> open(
      WidgetTester tester, {
      List<String> images = const ['/x/a.jpg'],
      List<String> files = const ['/x/report.pdf'],
      double width = 400,
      double height = 900,
      double scale = 1,
    }) async {
      share = FakeShare();
      spoken = [];
      sl.registerSingleton<ShareService>(share);
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => dir.path);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null));
      final settings = SettingsCubit(_Prefs());
      await tester.runAsync(settings.load);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => OcrToolPage(
              engine: reader,
              translator: translator,
              pdfPages: () => FakePicturePages(2),
              pickImages: () async => images,
              pickFiles: () async => files,
            ),
          ),
          GoRoute(
            path: '/read-aloud',
            builder: (_, s) {
              final a = s.extra! as ReadAloudArgs;
              spoken.add(a);
              return Scaffold(body: Text('SPEAK ${a.title}|${a.language}|${a.text}'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: settings,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(scale)),
            child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Future<void> readPictures(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-images')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-images')));
      await settle(tester);
    }

    String field(WidgetTester tester) => tester.widget<TextField>(find.byKey(const ValueKey('ocrtool-text'))).controller!.text;

    testWidgets('it starts with ways to add pictures and files, the language of the text and a promise about privacy', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('ocrtool-images')), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrtool-files')), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrtool-script-latin')), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrtool-script-devanagari')), findsOneWidget);
      expect(find.textContaining('never uploaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrtool-text')), findsNothing);
      expect(find.byKey(const ValueKey('ocrtool-translate')), findsNothing);
    });

    testWidgets('chosen pictures are read and the text can be corrected by hand', (tester) async {
      await open(tester);
      await readPictures(tester);
      expect(field(tester), 'Hello world.');
      expect(find.byKey(const ValueKey('ocrtool-translate')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('ocrtool-text')), 'Hello brave world.');
      await tester.pump();
      expect(field(tester), 'Hello brave world.');
    });

    testWidgets('a PDF from the files is read page by page into the same text', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('ocrtool-files')));
      await settle(tester);
      expect(field(tester), 'Hello world.\n\nPage one.\n\nPage two.');
      expect(find.text('Add more'), findsOneWidget);
    });

    testWidgets('while reading there is progress with the file name and a Stop button', (tester) async {
      await open(tester);
      reader.hold = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('ocrtool-images')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      expect(find.textContaining('Reading a.jpg'), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrtool-cancel')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('ocrtool-images'))).onPressed, isNull);
      reader.hold!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('ocrtool-progress')), findsNothing);
    });

    testWidgets('a picture with no text shows why', (tester) async {
      await open(tester, images: const ['/x/blank.jpg']);
      await readPictures(tester);
      expect(find.byKey(const ValueKey('ocrtool-failure')), findsOneWidget);
      expect(find.byKey(const ValueKey('ocrtool-text')), findsNothing);
    });

    testWidgets('a cancelled picker adds nothing', (tester) async {
      await open(tester, images: const []);
      await readPictures(tester);
      expect(find.byKey(const ValueKey('ocrtool-text')), findsNothing);
      expect(reader.reads, isEmpty);
    });

    testWidgets('translating shows the translation with Listen in its own language, Copy, Share and Use as text', (tester) async {
      translator.downloaded.addAll(['en', 'hi']);
      await open(tester);
      await readPictures(tester);
      expect(find.text('Hindi'), findsOneWidget, reason: 'the first target is Hindi when the phone is English');
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ocrtool-translation')), findsOneWidget);
      expect(find.text('[hi] Hello world.'), findsOneWidget);
      expect(find.text('English (detected)'), findsOneWidget);

      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-copy-translation')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-copy-translation')));
      await tester.pump();
      expect(clip, '[hi] Hello world.');

      await tester.tap(find.byKey(const ValueKey('ocrtool-share-translation')));
      await settle(tester);
      expect(share.single.single.mime, 'text/plain');
      expect(File(share.single.single.path).readAsStringSync(), '[hi] Hello world.');

      await tester.tap(find.byKey(const ValueKey('ocrtool-use-translation')));
      await tester.pump();
      expect(field(tester), '[hi] Hello world.');
      expect(find.byKey(const ValueKey('ocrtool-translation')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-listen')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-listen')));
      await tester.pumpAndSettle();
      expect(find.text('SPEAK Text|hi-IN|[hi] Hello world.'), findsOneWidget, reason: 'the voice follows the language of the text');
    });

    testWidgets('Listen to a translation asks for a voice in that language', (tester) async {
      translator.downloaded.addAll(['en', 'ta']);
      await open(tester);
      await readPictures(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-to')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-to')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lang-search')), 'tam');
      await tester.pump();
      expect(find.byKey(const ValueKey('lang-ta')), findsOneWidget);
      expect(find.byKey(const ValueKey('lang-fr')), findsNothing);
      expect(find.text('On this phone'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('lang-ta')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-listen-translation')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-listen-translation')));
      await tester.pumpAndSettle();
      expect(find.text('SPEAK Translation|ta|[ta] Hello world.'), findsOneWidget);
    });

    testWidgets('with data missing it asks, naming the languages and the size, and Not now closes the question', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ocrtool-download-ask')), findsOneWidget);
      expect(find.text('Download English and Hindi language data?'), findsOneWidget);
      expect(find.textContaining('30 MB'), findsOneWidget);
      expect(find.textContaining('only thing that uses the internet'), findsOneWidget);
      expect(translator.downloads, isEmpty);
      await tester.tap(find.byKey(const ValueKey('ocrtool-download-no')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ocrtool-download-ask')), findsNothing);
      expect(find.byKey(const ValueKey('ocrtool-translate')), findsOneWidget);
    });

    testWidgets('agreeing downloads and translates; a failed download shows why', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      translator.failDownload = true;
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ocrtool-download')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ocrtool-translate-failure')), findsOneWidget);
      expect(find.textContaining('could not be downloaded'), findsOneWidget);

      translator.failDownload = false;
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('ocrtool-download')));
      await settle(tester);
      expect(find.text('[hi] Hello world.'), findsOneWidget);
    });

    testWidgets('a language that cannot be found is chosen under From, and Detect automatically goes back', (tester) async {
      translator
        ..detectResult = null
        ..downloaded.addAll(['en', 'hi', 'fr']);
      await open(tester);
      await readPictures(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      expect(find.textContaining('Choose it under "From"'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-from')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-from')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lang-auto')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('lang-search')), 'French');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lang-fr')));
      await tester.pumpAndSettle();
      expect(find.text('French'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      expect(find.text('[hi] Hello world.'), findsOneWidget);
      expect(translator.translations.last.from, 'fr');

      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-from')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-from')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lang-auto')));
      await tester.pumpAndSettle();
      expect(find.text('Detect automatically'), findsOneWidget);
    });

    testWidgets('the swap button turns the languages round, and is off while the language is unknown', (tester) async {
      translator.downloaded.addAll(['en', 'hi']);
      await open(tester);
      await readPictures(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-swap')));
      await tester.pump();
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('ocrtool-swap'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-swap')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-swap')));
      await tester.pump();
      expect(find.text('Hindi'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
    });

    testWidgets('sharing the text sends a text file; Copy puts it on the clipboard', (tester) async {
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('ocrtool-share')));
      await settle(tester);
      expect(share.single.single.mime, 'text/plain');
      expect(File(share.single.single.path).readAsStringSync(), 'Hello world.');
    });

    testWidgets('editing the text clears an earlier translation', (tester) async {
      translator.downloaded.addAll(['en', 'hi']);
      await open(tester);
      await readPictures(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-translate')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ocrtool-translation')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('ocrtool-text')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('ocrtool-text')), 'New words here.');
      await tester.pump();
      expect(find.byKey(const ValueKey('ocrtool-translation')), findsNothing);
    });

    testWidgets('Clear empties everything, and the menu shows the language data on the phone with a way to remove it', (tester) async {
      translator.downloaded.addAll(['en', 'hi']);
      await open(tester);
      await readPictures(tester);
      await tester.tap(find.byKey(const ValueKey('ocrtool-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language data on this phone'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('langdata-hi')), findsOneWidget);
      expect(find.byKey(const ValueKey('langdata-en')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('langdata-delete-hi')));
      await tester.pumpAndSettle();
      expect(translator.deleted, ['hi']);
      expect(find.byKey(const ValueKey('langdata-hi')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('langdata-delete-en')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('langdata-empty')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('ocrtool-clear')));
      await tester.pump();
      expect(find.byKey(const ValueKey('ocrtool-text')), findsNothing);
    });

    testWidgets('a language can be downloaded ahead from the language data list, and a failure shows why', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('ocrtool-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Language data on this phone'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('langdata-empty')), findsOneWidget);

      translator.failDownload = true;
      await tester.tap(find.byKey(const ValueKey('langdata-download')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lang-search')), 'French');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lang-fr')));
      await settle(tester);
      expect(find.byKey(const ValueKey('langdata-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('langdata-fr')), findsNothing);

      translator.failDownload = false;
      await tester.tap(find.byKey(const ValueKey('langdata-download')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('lang-search')), 'French');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('lang-fr')));
      await settle(tester);
      expect(translator.downloads, ['fr', 'fr']);
      expect(find.byKey(const ValueKey('langdata-fr')), findsOneWidget);
      expect(find.byKey(const ValueKey('langdata-error')), findsNothing);
    });

    testWidgets('a small phone with large text does not overflow', (tester) async {
      translator.downloaded.addAll(['en', 'hi']);
      await open(tester, width: 320, height: 568, scale: 1.4);
      await readPictures(tester);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('ocrtool-translate')), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ocrtool-translate')));
      await settle(tester);
      expect(find.byKey(const ValueKey('ocrtool-translation')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the Tools tab', () {
    testWidgets('OCR and translate is the first thing on the page and opens the tool', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: ToolsView()),
          ),
          GoRoute(
            path: '/ocr-tool',
            builder: (_, _) => const Scaffold(body: Text('OCR TOOL')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      final featured = tester.getTopLeft(find.byKey(const ValueKey('tool-ocr')));
      final firstSection = tester.getTopLeft(find.text('PDF and documents'));
      final firstTool = tester.getTopLeft(find.text('Read PDF or Word'));
      expect(featured.dy, lessThan(firstSection.dy));
      expect(featured.dy, lessThan(firstTool.dy));
      expect(find.text('OCR and translate'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tool-ocr')));
      await tester.pumpAndSettle();
      expect(find.text('OCR TOOL'), findsOneWidget);
    });
  });
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

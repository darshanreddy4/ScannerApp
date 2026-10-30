import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/speech/domain/speech_chunks.dart';
import 'package:doculoom/features/speech/domain/speech_service.dart';
import 'package:doculoom/features/speech/presentation/read_aloud_cubit.dart';
import 'package:doculoom/features/speech/presentation/read_aloud_page.dart';

class FakeSpeech implements SpeechService {
  final controller = StreamController<SpeechEvent>.broadcast();
  var available = true;
  var result = SpeechStart.started;
  final calls = <({List<String> chunks, int from, String? language, double rate})>[];
  var stops = 0;
  var settingsOpened = 0;

  @override
  Stream<SpeechEvent> get events => controller.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<SpeechStart> speak(List<String> chunks, {required int from, String? language, required double rate}) async {
    calls.add((chunks: chunks, from: from, language: language, rate: rate));
    return result;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<bool> openVoiceSettings() async {
    settingsOpened++;
    return true;
  }

  Future<void> emit(SpeechEvent e) async {
    controller.add(e);
    await Future<void>.delayed(Duration.zero);
  }
}

const _text = 'First sentence is here. Second sentence follows it.\n\nA new paragraph starts. It has two sentences.';

void main() {
  group('cutting text for the voice', () {
    test('lines wrapped by the width of the page are joined into one sentence', () {
      expect(splitForSpeech('The quick brown fox\njumps over the lazy dog.'), ['The quick brown fox jumps over the lazy dog.']);
    });

    test('a word cut by a hyphen at the end of a line is made whole', () {
      expect(splitForSpeech('This is an exam-\nple of a long word.'), ['This is an example of a long word.']);
    });

    test('list items and headings are spoken one at a time so the voice pauses', () {
      expect(splitForSpeech('Shopping list\nMilk\nEggs\nBread'), ['Shopping list', 'Milk', 'Eggs', 'Bread']);
    });

    test('short sentences are packed together, paragraphs are never mixed, and nothing is longer than the limit', () {
      final pieces = splitForSpeech(_text);
      expect(pieces, ['First sentence is here. Second sentence follows it.', 'A new paragraph starts. It has two sentences.']);
      final long = List.filled(60, 'This sentence is a little long.').join(' ');
      final cut = splitForSpeech(long, maxLength: 200);
      expect(cut.every((c) => c.length <= 200), isTrue);
      expect(cut.join(' '), long, reason: 'nothing is lost');
    });

    test('one huge sentence is cut at commas or spaces, never inside a word', () {
      final huge = '${List.generate(80, (i) => 'word$i').join(' ')}.';
      final cut = splitForSpeech(huge, maxLength: 100);
      expect(cut.length, greaterThan(3));
      expect(cut.every((c) => c.length <= 100), isTrue);
      expect(cut.join(' '), huge);
      expect(splitForSpeech('a' * 500, maxLength: 100).every((c) => c.length <= 100), isTrue, reason: 'even with no space to cut at');
    });

    test('Devanagari sentences end at the danda', () {
      expect(splitForSpeech('यह पहला वाक्य है। यह दूसरा वाक्य है।', maxLength: 20), ['यह पहला वाक्य है।', 'यह दूसरा वाक्य है।']);
    });

    test('pieces with nothing to say, and empty text, give nothing', () {
      expect(splitForSpeech('---\n***\n...'), isEmpty);
      expect(splitForSpeech(''), isEmpty);
      expect(splitForSpeech('   \n\n  '), isEmpty);
    });

    test('Windows line ends, tabs and odd spaces are cleaned', () {
      expect(splitForSpeech('One\u00A0two\tthree.\r\nFour five.'), ['One two three. Four five.']);
    });
  });

  group('which voice', () {
    test('Latin text follows the phone, Devanagari and Arabic ask for their own voice', () {
      expect(guessSpeechLanguage('Hello world'), isNull);
      expect(guessSpeechLanguage('नमस्ते दुनिया'), 'hi-IN');
      expect(guessSpeechLanguage('مرحبا بالعالم'), 'ar');
      expect(guessSpeechLanguage('Hello नमस्ते दुनिया, कैसे हो'), 'hi-IN');
      expect(guessSpeechLanguage('1234 5678'), isNull);
      expect(guessSpeechLanguage(''), isNull);
    });

    test('the list starts with Automatic and every language is listed once', () {
      expect(speechLanguages.first, (null, 'Automatic'));
      final codes = speechLanguages.map((e) => e.$1).toList();
      expect(codes.toSet().length, codes.length);
    });
  });

  group('reading', () {
    late FakeSpeech speech;

    ReadAloudCubit make([String text = _text]) {
      speech = FakeSpeech();
      return ReadAloudCubit(service: speech, text: text);
    }

    test('it opens ready to read, with the text in pieces', () async {
      final c = make();
      await c.start();
      expect(c.state.status, ReadStatus.idle);
      expect(c.state.chunks, hasLength(2));
      expect(c.state.index, 0);
      await c.close();
    });

    test('a phone with no voice engine says so and cannot read', () async {
      final c = make();
      speech.available = false;
      await c.start();
      expect(c.state.status, ReadStatus.unavailable);
      expect(c.state.message, contains('no text-to-speech engine'));
      await c.close();
    });

    test('Read starts from the first piece at normal speed with the phone\'s language', () async {
      final c = make();
      await c.start();
      await c.play();
      expect(c.state.status, ReadStatus.speaking);
      expect(speech.calls.single.from, 0);
      expect(speech.calls.single.rate, 1.0);
      expect(speech.calls.single.language, isNull);
      expect(speech.calls.single.chunks, c.state.chunks);
      await c.close();
    });

    test('the piece being spoken follows what the voice reports, and the end brings it back to the start', () async {
      final c = make();
      await c.start();
      await c.play();
      await speech.emit(const SpeechChunk(1));
      expect(c.state.index, 1);
      await speech.emit(const SpeechDone());
      expect(c.state.status, ReadStatus.idle);
      expect(c.state.index, 0);
      await c.close();
    });

    test('reports that arrive when it is not speaking are ignored', () async {
      final c = make();
      await c.start();
      await speech.emit(const SpeechChunk(1));
      await speech.emit(const SpeechDone());
      await speech.emit(const SpeechFailed('x'));
      expect(c.state.index, 0);
      expect(c.state.status, ReadStatus.idle);
      await c.close();
    });

    test('pause keeps the place, and resume carries on from that piece', () async {
      final c = make();
      await c.start();
      await c.play();
      await speech.emit(const SpeechChunk(1));
      await c.pause();
      expect(c.state.status, ReadStatus.paused);
      expect(c.state.index, 1);
      expect(speech.stops, 1);
      await c.toggle();
      expect(c.state.status, ReadStatus.speaking);
      expect(speech.calls.last.from, 1);
      await c.close();
    });

    test('next and previous restart the voice at the new piece while reading, and only move the place when not', () async {
      final c = make('One.\n\nTwo.\n\nThree.\n\nFour.');
      await c.start();
      await c.next();
      expect(c.state.index, 1);
      expect(speech.calls, isEmpty, reason: 'not reading, so nothing is spoken');
      await c.play();
      await c.next();
      expect(speech.calls.last.from, 2);
      await c.previous();
      expect(speech.calls.last.from, 1);
      await c.close();
    });

    test('moving past either end stays on the first and last piece', () async {
      final c = make('One.\n\nTwo.');
      await c.start();
      await c.previous();
      expect(c.state.index, 0);
      await c.seek(99);
      expect(c.state.index, 1);
      await c.next();
      expect(c.state.index, 1);
      await c.close();
    });

    test('Stop goes back to the start', () async {
      final c = make();
      await c.start();
      await c.play();
      await speech.emit(const SpeechChunk(1));
      await c.stop();
      expect(c.state.status, ReadStatus.idle);
      expect(c.state.index, 0);
      await c.close();
    });

    test('speed changes are used at once while reading, at the piece being read', () async {
      final c = make();
      await c.start();
      await c.play();
      await speech.emit(const SpeechChunk(1));
      await c.setRate(1.5);
      expect(speech.calls.last.rate, 1.5);
      expect(speech.calls.last.from, 1);
      await c.close();
    });

    test('a speed chosen before reading is used when it starts', () async {
      final c = make();
      await c.start();
      await c.setRate(0.75);
      expect(speech.calls, isEmpty);
      await c.play();
      expect(speech.calls.single.rate, 0.75);
      await c.close();
    });

    test('Hindi text asks for a Hindi voice, and a language chosen by the person wins', () async {
      final c = make('यह पहला वाक्य है। यह दूसरा वाक्य है।');
      await c.start();
      await c.play();
      expect(speech.calls.last.language, 'hi-IN');
      await c.setLanguage('en');
      expect(speech.calls.last.language, 'en');
      await c.setLanguage(null);
      expect(speech.calls.last.language, 'hi-IN');
      await c.close();
    });

    test('a language the phone has no voice for says so and can be changed', () async {
      final c = make();
      await c.start();
      speech.result = SpeechStart.languageMissing;
      await c.setLanguage('tr');
      await c.play();
      expect(c.state.status, ReadStatus.languageMissing);
      expect(c.state.message, contains('no voice for that language'));
      speech.result = SpeechStart.started;
      await c.setLanguage('en');
      expect(c.state.status, ReadStatus.idle);
      expect(c.state.message, isNull);
      await c.play();
      expect(c.state.status, ReadStatus.speaking);
      await c.close();
    });

    test('an engine that stops working while reading is reported', () async {
      final c = make();
      await c.start();
      await c.play();
      await speech.emit(const SpeechFailed('The phone\'s voice stopped working.'));
      expect(c.state.status, ReadStatus.failed);
      expect(c.state.message, contains('voice stopped'));
      await c.close();
    });

    test('an engine that disappears when asked to speak is reported', () async {
      final c = make();
      await c.start();
      speech.result = SpeechStart.unavailable;
      await c.play();
      expect(c.state.status, ReadStatus.unavailable);
      await c.close();
    });

    test('text with nothing to read has no pieces and Read does nothing', () async {
      final c = make('---');
      await c.start();
      expect(c.state.hasText, isFalse);
      await c.play();
      expect(speech.calls, isEmpty);
      await c.close();
    });

    test('leaving stops the voice', () async {
      final c = make();
      await c.start();
      await c.play();
      await c.close();
      expect(speech.stops, greaterThan(0));
    });

    test('a second tap while the voice is starting does not start it twice', () async {
      final c = make();
      await c.start();
      await Future.wait([c.play(), c.play()]);
      expect(speech.calls, hasLength(1));
      await c.close();
    });
  });

  group('the screen', () {
    late FakeSpeech speech;

    Future<void> open(WidgetTester tester, {String text = _text, double width = 400, double height = 800, double textScale = 1}) async {
      speech = FakeSpeech();
      tester.view.physicalSize = Size(width * 3, height * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(textScale)),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: ReadAloudPage(
              args: ReadAloudArgs(title: 'Lease', text: text),
              service: speech,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('it shows the text in pieces and starts reading from a tapped piece', (tester) async {
      await open(tester);
      expect(find.text('Part 1 of 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('read-chunk-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('read-chunk-1')));
      await tester.pump();
      await tester.pump();
      expect(speech.calls, isEmpty, reason: 'a tap only moves the place while it is not reading');
      expect(find.text('Part 2 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('read-play')));
      await tester.pump();
      await tester.pump();
      expect(speech.calls.single.from, 1);
      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('Read becomes Pause, then Resume, and the speed and language can be chosen', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('read-play')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('read-rate-1.5')));
      await tester.pump();
      await tester.pump();
      expect(speech.calls.last.rate, 1.5);
      await tester.tap(find.byKey(const ValueKey('read-play')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('read-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();
      expect(find.text('Spanish'), findsOneWidget);
    });

    testWidgets('with no voice engine it says so, offers the voice settings and cannot start', (tester) async {
      speech = FakeSpeech()..available = false;
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ReadAloudPage(
            args: const ReadAloudArgs(title: 'Lease', text: _text),
            service: speech,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('read-message')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('read-play'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('read-open-settings')));
      await tester.pump();
      expect(speech.settingsOpened, 1);
    });

    testWidgets('a document with no text says so instead of showing empty controls that do nothing', (tester) async {
      await open(tester, text: '');
      expect(find.byKey(const ValueKey('read-empty')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('read-play'))).onPressed, isNull);
    });

    testWidgets('the current piece follows the voice and the list scrolls to it', (tester) async {
      final text = List.generate(40, (i) => 'Paragraph number $i has some words in it.').join('\n\n');
      await open(tester, text: text);
      await tester.tap(find.byKey(const ValueKey('read-play')));
      await tester.pump();
      await tester.pump();
      final chunks = speech.calls.single.chunks.length;
      speech.controller.add(SpeechChunk(chunks - 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Part $chunks of $chunks'), findsOneWidget);
      expect(find.byKey(ValueKey('read-chunk-${chunks - 1}')), findsOneWidget, reason: 'the last piece has been scrolled into view');
    });

    testWidgets('it fits a small phone with large text', (tester) async {
      await open(tester, width: 320, height: 568, textScale: 1.4);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('read-play')));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

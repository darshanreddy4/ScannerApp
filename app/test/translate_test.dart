import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:doculoom/features/speech/domain/speech_chunks.dart';
import 'package:doculoom/features/translate/domain/translate_text.dart';
import 'package:doculoom/features/translate/domain/translation_languages.dart';
import 'package:doculoom/features/translate/domain/translation_service.dart';

import 'support/ocr_tool_fakes.dart';

void main() {
  group('languages', () {
    test('the list is exactly the languages the on-device translator has', () {
      final mine = translationLanguages.map((l) => l.code).toSet();
      final theirs = TranslateLanguage.values.map((l) => l.bcpCode).toSet();
      expect(mine, theirs);
      expect(translationLanguages.length, theirs.length, reason: 'each language once');
      expect(translationLanguages.map((l) => l.name).toSet().length, translationLanguages.length);
    });

    test('names are looked up by code, and an unknown code is shown as it is', () {
      expect(languageName('hi'), 'Hindi');
      expect(languageName('pt'), 'Portuguese');
      expect(languageName('xx'), 'xx');
      expect(isTranslationLanguage('tr'), isTrue);
      expect(isTranslationLanguage('xx'), isFalse);
    });

    test('a code with a region or script, or an old spelling, maps to the translator language', () {
      expect(translationCodeFor('pt-BR'), 'pt');
      expect(translationCodeFor('hi-Latn'), 'hi');
      expect(translationCodeFor('zh_TW'), 'zh');
      expect(translationCodeFor('nb'), 'no');
      expect(translationCodeFor('iw'), 'he');
      expect(translationCodeFor('EN'), 'en');
      expect(translationCodeFor('und'), isNull);
      expect(translationCodeFor(''), isNull);
      expect(translationCodeFor(null), isNull);
      expect(translationCodeFor('xx'), isNull);
    });

    test('English is added to what is needed when neither language is English', () {
      expect(languagesNeeded('hi', 'en'), ['hi', 'en']);
      expect(languagesNeeded('en', 'fr'), ['en', 'fr']);
      expect(languagesNeeded('hi', 'fr'), ['hi', 'fr', 'en']);
    });

    test('every translator language can be chosen as a voice, once', () {
      final codes = speechLanguages.map((l) => l.$1).toList();
      expect(codes.toSet().length, codes.length);
      for (final l in translationLanguages) {
        expect(codes, contains(speechVoiceFor(l.code)), reason: l.name);
      }
      expect(speechVoiceFor('hi'), 'hi-IN');
      expect(speechVoiceFor('ta'), 'ta');
      expect(codes.first, isNull);
    });
  });

  group('cutting text for the translator', () {
    test('lines cut by the width of the page are one sentence; headings and paragraphs stay apart', () {
      final parts = splitForTranslation('Annual report\n\nThe company grew\nby ten percent in\nthe last year.\nIt hired more people.\n\nSecond paragraph.');
      expect(
        [for (final p in parts) p.text],
        ['Annual report', 'The company grew by ten percent in the last year.', 'It hired more people.', 'Second paragraph.'],
      );
      expect([for (final p in parts) p.after], ['\n\n', '\n', '\n\n', '']);
    });

    test('a word cut by a hyphen at the end of a line is made whole', () {
      expect(splitForTranslation('The informa-\ntion was clear.').single.text, 'The information was clear.');
    });

    test('a long passage is cut at sentences, each piece within the limit, and put back with spaces', () {
      final sentence = 'This is a sentence that has some length to it. ';
      final text = sentence * 12;
      final parts = splitForTranslation(text, maxLength: 200);
      expect(parts.length, greaterThan(1));
      expect(parts.every((p) => p.text.length <= 200), isTrue);
      expect(parts.every((p) => p.text.endsWith('.')), isTrue);
      expect([for (final p in parts.take(parts.length - 1)) p.after].toSet(), {' '});
      expect(parts.last.after, '');
      expect(parts.map((p) => p.text).join(' '), text.trim());
    });

    test('one huge sentence is cut at commas or spaces, never inside a word', () {
      final words = List.generate(120, (i) => 'word$i').join(' ');
      final parts = splitForTranslation(words, maxLength: 100);
      expect(parts.every((p) => p.text.length <= 100), isTrue);
      expect(parts.map((p) => p.text).join(' '), words);
    });

    test('empty text, blank lines and odd line ends give nothing or are cleaned', () {
      expect(splitForTranslation(''), isEmpty);
      expect(splitForTranslation('  \n\n \n'), isEmpty);
      expect([for (final p in splitForTranslation('One.\r\nTwo.\r\n\r\nThree.')) p.text], ['One.', 'Two.', 'Three.']);
    });

    test('Devanagari sentences end at the danda', () {
      final parts = splitForTranslation('यह पहला वाक्य है। यह दूसरा वाक्य है।', maxLength: 25);
      expect(parts.length, 2);
    });
  });

  group('translating long text', () {
    test('every passage is translated in order and the paragraphs come back as they were', () async {
      final t = FakeTranslator();
      final out = await translateLongText(t, 'Title\n\nFirst line\nof the text.\n\nLast one.', from: 'en', to: 'hi');
      expect(out, '[hi] Title\n\n[hi] First line of the text.\n\n[hi] Last one.');
      expect(t.translations.every((x) => x.from == 'en' && x.to == 'hi'), isTrue);
      expect(t.translations, hasLength(3));
    });

    test('passages with no letters, such as numbers and dates, are kept as they are and not sent to the translator', () async {
      final t = FakeTranslator();
      final out = await translateLongText(t, 'Total\n\n1,234.50\n\n12/03/2026', from: 'en', to: 'fr');
      expect(out, '[fr] Total\n\n1,234.50\n\n12/03/2026');
      expect(t.translations, hasLength(1));
    });

    test('progress is reported after every passage, and a stop request ends it with what is done not returned', () async {
      final t = FakeTranslator();
      final seen = <String>[];
      await translateLongText(t, 'A one.\n\nB two.\n\nC three.', from: 'en', to: 'de', onProgress: (d, n) => seen.add('$d/$n'));
      expect(seen, ['1/3', '2/3', '3/3']);

      final t2 = FakeTranslator();
      var calls = 0;
      expect(
        () => translateLongText(t2, 'A one.\n\nB two.\n\nC three.', from: 'en', to: 'de', isCancelled: () => ++calls > 1),
        throwsA(isA<TranslationCancelled>()),
      );
    });

    test('a translator that returns nothing for a passage leaves the original there, and one that fails fails the whole job', () async {
      final empty = _Blank();
      expect(await translateLongText(empty, 'Hello there.', from: 'en', to: 'fr'), 'Hello there.');
      final t = FakeTranslator()..failTranslate = StateError('boom');
      expect(() => translateLongText(t, 'Hello there.', from: 'en', to: 'fr'), throwsStateError);
    });

    test('text with nothing in it gives an empty string without asking the translator', () async {
      final t = FakeTranslator();
      expect(await translateLongText(t, '  \n ', from: 'en', to: 'fr'), '');
      expect(t.translations, isEmpty);
    });
  });
}

class _Blank extends FakeTranslator {
  @override
  Future<String> translate(String text, {required String from, required String to}) async => '  ';
}

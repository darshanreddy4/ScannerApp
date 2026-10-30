import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/core/utils/region.dart';
import 'package:doculoom/features/amount_words/presentation/amount_words_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:doculoom/features/amount_words/domain/amount_words.dart';

String? _w(String a, WordsLanguage l, String c, {bool only = false, WordsCase k = WordsCase.title}) =>
    amountInWords(a, language: l, currency: c, only: only, letters: k);

void main() {
  group('reading the amount', () {
    test('Indian, English and German ways of writing it', () {
      expect(parseWordsAmount('1,23,456.50'), (whole: 123456, minor: 50, hasMinor: true));
      expect(parseWordsAmount('1,234,567.8'), (whole: 1234567, minor: 80, hasMinor: true));
      expect(parseWordsAmount('1.234,56'), (whole: 1234, minor: 56, hasMinor: true));
      expect(parseWordsAmount('12,5'), (whole: 12, minor: 50, hasMinor: true));
      expect(parseWordsAmount('1,234'), (whole: 1234, minor: 0, hasMinor: false));
      expect(parseWordsAmount('1.234.567'), (whole: 1234567, minor: 0, hasMinor: false));
      expect(parseWordsAmount(' 1 234 ')?.whole, 1234);
      expect(parseWordsAmount('999999999999.99')?.whole, wordsMax);
    });

    test('what is not an amount is refused', () {
      for (final bad in ['', 'abc', '1,2,3', '1e5', '.5', '-5', '1234567890123', '1.2.3', '12,345,67', '1000000000000', '5,']) {
        expect(parseWordsAmount(bad), isNull, reason: bad);
      }
      expect(wordsAmountProblem('', currency: 'INR'), isNull);
      expect(wordsAmountProblem('12abc', currency: 'INR'), contains('not valid'));
      expect(wordsAmountProblem('12.50', currency: 'none'), contains('Choose a currency'));
      expect(wordsAmountProblem('12', currency: 'none'), isNull);
    });
  });

  group('English with lakh and crore', () {
    test('a cheque amount', () {
      expect(_w('123456.50', WordsLanguage.enIn, 'INR', only: true), 'Rupees One Lakh Twenty Three Thousand Four Hundred Fifty Six and Fifty Paise Only');
      expect(_w('1', WordsLanguage.enIn, 'INR', only: true), 'Rupees One Only');
      expect(_w('0.50', WordsLanguage.enIn, 'INR'), 'Fifty Paise');
      expect(_w('21.01', WordsLanguage.enIn, 'INR'), 'Rupees Twenty One and One Paisa');
      expect(_w('10000000', WordsLanguage.enIn, 'INR'), 'Rupees One Crore');
      expect(_w('0', WordsLanguage.enIn, 'INR'), 'Rupees Zero');
    });

    test('crores and lakhs', () {
      expect(
        _w('1234567890', WordsLanguage.enIn, 'none', k: WordsCase.lower),
        'one hundred twenty three crore forty five lakh sixty seven thousand eight hundred ninety',
      );
      expect(_w('100000', WordsLanguage.enIn, 'none', k: WordsCase.lower), 'one lakh');
      expect(_w('99999', WordsLanguage.enIn, 'none', k: WordsCase.lower), 'ninety nine thousand nine hundred ninety nine');
      expect(
        _w('999999999999', WordsLanguage.enIn, 'none', k: WordsCase.lower),
        startsWith('ninety nine thousand nine hundred ninety nine crore ninety nine lakh'),
      );
    });
  });

  group('English with million and billion', () {
    test('dollars, pounds and euros', () {
      expect(_w('1234.56', WordsLanguage.en, 'USD'), 'One Thousand Two Hundred Thirty-Four Dollars and Fifty-Six Cents');
      expect(_w('1', WordsLanguage.en, 'USD', only: true, k: WordsCase.upper), 'ONE DOLLAR ONLY');
      expect(_w('2000000.01', WordsLanguage.en, 'USD'), 'Two Million Dollars and One Cent');
      expect(_w('101', WordsLanguage.en, 'GBP', k: WordsCase.lower), 'one hundred one pounds');
      expect(_w('1000000000', WordsLanguage.en, 'none', k: WordsCase.lower), 'one billion');
      expect(_w('12', WordsLanguage.en, 'none', k: WordsCase.lower), 'twelve');
    });
  });

  group('German', () {
    test('euros and cents', () {
      expect(
        _w('1234567.89', WordsLanguage.de, 'EUR'),
        'Eine Million zweihundertvierunddreißigtausendfünfhundertsiebenundsechzig Euro und neunundachtzig Cent',
      );
      expect(_w('1', WordsLanguage.de, 'EUR'), 'Ein Euro');
      expect(_w('21', WordsLanguage.de, 'EUR'), 'Einundzwanzig Euro');
      expect(_w('101.01', WordsLanguage.de, 'EUR'), 'Einhundertein Euro und ein Cent');
      expect(_w('2000000', WordsLanguage.de, 'EUR'), 'Zwei Millionen Euro');
      expect(_w('1100000000', WordsLanguage.de, 'EUR'), 'Eine Milliarde einhundert Millionen Euro');
      expect(_w('12.50', WordsLanguage.de, 'EUR', k: WordsCase.upper), 'ZWÖLF EURO UND FÜNFZIG CENT');
    });

    test('the number alone', () {
      expect(_w('1', WordsLanguage.de, 'none', k: WordsCase.lower), 'eins');
      expect(_w('1001', WordsLanguage.de, 'none', k: WordsCase.lower), 'eintausendeins');
      expect(_w('30', WordsLanguage.de, 'none', k: WordsCase.lower), 'dreißig');
    });
  });

  group('Arabic', () {
    test('the noun takes the form the number asks for', () {
      expect(_w('1', WordsLanguage.ar, 'SAR'), 'ريال واحد');
      expect(_w('2', WordsLanguage.ar, 'SAR'), 'ريالان');
      expect(_w('3', WordsLanguage.ar, 'SAR'), 'ثلاثة ريالات');
      expect(_w('11', WordsLanguage.ar, 'SAR'), 'أحد عشر ريالاً');
      expect(_w('100', WordsLanguage.ar, 'SAR'), 'مائة ريال');
      expect(_w('200', WordsLanguage.ar, 'SAR'), 'مائتا ريال');
      expect(_w('2000', WordsLanguage.ar, 'SAR'), 'ألفا ريال');
      expect(_w('3000', WordsLanguage.ar, 'SAR'), 'ثلاثة آلاف ريال');
    });

    test('amounts with the minor unit, and the "only" frame', () {
      expect(_w('25.50', WordsLanguage.ar, 'SAR'), 'خمسة وعشرون ريالاً وخمسون هللةً');
      expect(_w('0.05', WordsLanguage.ar, 'SAR', only: true), 'فقط خمس هللات لا غير');
      expect(_w('2500000', WordsLanguage.ar, 'AED'), 'مليونان وخمسمائة ألف درهم');
    });

    test('the number alone', () {
      expect(_w('1234', WordsLanguage.ar, 'none'), 'ألف ومائتان وأربعة وثلاثون');
      expect(_w('0', WordsLanguage.ar, 'none'), 'صفر');
    });
  });

  test('every language writes every number below a hundred and a few more without gaps', () {
    for (final l in WordsLanguage.values) {
      for (var n = 0; n < 1000; n++) {
        final text = amountInWords('$n', language: l, currency: 'none')!;
        expect(text.trim(), isNotEmpty, reason: '$l $n');
        expect(text, isNot(contains('  ')), reason: '$l $n');
        expect(text, isNot(contains('null')), reason: '$l $n');
      }
    }
  });

  test('a currency can be found and every one has names in every language', () {
    expect(wordsCurrency('INR')?.name, 'Indian rupee (INR)');
    expect(wordsCurrency('XXX'), isNull);
    for (final c in wordsCurrencies) {
      for (final l in WordsLanguage.values) {
        expect(
          amountInWords('7.05', language: l, currency: c.code),
          isNotNull,
          reason: '${c.code} $l',
        );
      }
    }
  });

  test('the figures are grouped the way the language writes them', () {
    final a = parseWordsAmount('1234567.5')!;
    expect(wordsFigures(a, indian: true), '12,34,567.50');
    expect(wordsFigures(a, indian: false), '1,234,567.50');
    expect(wordsFigures(parseWordsAmount('999')!, indian: true), '999');
    expect(wordsFigures(parseWordsAmount('1000')!, indian: true), '1,000');
    expect(wordsFigures(parseWordsAmount('100000')!, indian: true), '1,00,000');
  });

  group('the page', () {
    final copied = <String>[];

    Future<void> open(WidgetTester tester, {double width = 400}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      copied.clear();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const AmountWordsPage()));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    String result(WidgetTester tester) => tester.widget<SelectableText>(find.byKey(const ValueKey('words-result'))).data!;

    testWidgets('writes the amount, and follows the currency, language and options', (tester) async {
      Region.apply(paper: PaperChoice.auto, date: DateStyle.auto, tools: ToolRegion.usa);
      addTearDown(() => Region.apply(paper: PaperChoice.auto, date: DateStyle.auto));
      await open(tester);
      expect(find.text('Enter an amount to see it in words.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('words-amount')), '1234.5');
      await tester.pump();
      expect(result(tester), 'One Thousand Two Hundred Thirty-Four Dollars and Fifty Cents');
      expect(find.text('In figures: 1,234.50'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('words-only')));
      await tester.tap(find.byKey(const ValueKey('words-case-upper')));
      await tester.pump();
      expect(result(tester), 'ONE THOUSAND TWO HUNDRED THIRTY-FOUR DOLLARS AND FIFTY CENTS ONLY');
      await tester.tap(find.byKey(const ValueKey('words-lang-enIn')));
      await tester.pump();
      expect(find.text('In figures: 1,234.50'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('words-lang-de')));
      await tester.pump();
      expect(find.byKey(const ValueKey('words-only')), findsNothing, reason: 'German has no "only"');
      expect(result(tester), 'EINTAUSENDZWEIHUNDERTVIERUNDDREISSIG US-DOLLAR UND FÜNFZIG CENT');
    });

    testWidgets('in India the amount is written with lakh and crore, with "Only"', (tester) async {
      Region.apply(paper: PaperChoice.auto, date: DateStyle.auto, tools: ToolRegion.india);
      addTearDown(() => Region.apply(paper: PaperChoice.auto, date: DateStyle.auto));
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('words-amount')), '1,23,456.50');
      await tester.pump();
      expect(result(tester), 'Rupees One Lakh Twenty Three Thousand Four Hundred Fifty Six and Fifty Paise Only');
      expect(find.text('In figures: 1,23,456.50'), findsOneWidget);
    });

    testWidgets('a wrong amount is explained and nothing is written', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('words-amount')), '1,2,3');
      await tester.pump();
      expect(find.textContaining('The amount is not valid'), findsNothing, reason: 'not before the field is left');
      await tester.enterText(find.byKey(const ValueKey('words-amount')), '12.5.');
      await tester.tap(find.byKey(const ValueKey('words-only')));
      await tester.pump();
      expect(find.byKey(const ValueKey('words-result')), findsNothing);
    });

    testWidgets('Arabic is shown right to left with its note, and the words can be copied', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const ValueKey('words-amount')), '25.50');
      await tester.tap(find.byKey(const ValueKey('words-lang-ar')));
      await tester.pump();
      expect(find.textContaining('native speaker'), findsOneWidget);
      expect(find.byKey(const ValueKey('words-case-upper')), findsNothing, reason: 'Arabic has no capitals');
      expect(tester.widget<SelectableText>(find.byKey(const ValueKey('words-result'))).textDirection, TextDirection.rtl);
      await tester.tap(find.byKey(const ValueKey('words-copy')));
      await tester.pump();
      expect(copied.single, result(tester));
    });

    testWidgets('the choices are remembered', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('words-lang-de')));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      final p = await SharedPreferences.getInstance();
      expect(p.getString('words_language'), 'de');
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('fits at ${width.toInt()} px', (tester) async {
        await open(tester, width: width);
        await tester.enterText(find.byKey(const ValueKey('words-amount')), '999999999999.99');
        await tester.tap(find.byKey(const ValueKey('words-lang-ar')));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('words-lang-de')));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

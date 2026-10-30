import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/i18n/app_language.dart';
import 'package:doculoom/core/i18n/tr.dart';
import 'package:doculoom/core/i18n/lang/europe.dart';
import 'package:doculoom/core/i18n/lang/cards.dart';
import 'package:doculoom/core/i18n/lang/packet.dart';
import 'package:doculoom/core/i18n/lang/checklists.dart';
import 'package:doculoom/core/i18n/lang/cvdesigns.dart';
import 'package:doculoom/core/i18n/lang/sharepdf.dart';
import 'package:doculoom/core/i18n/lang/coinsv2.dart';
import 'package:doculoom/core/i18n/lang/taxsuite.dart';
import 'package:doculoom/core/i18n/lang/reminderhelp.dart';
import 'package:doculoom/core/i18n/lang/stamps.dart';
import 'package:doculoom/core/i18n/lang/upi.dart';
import 'package:doculoom/core/i18n/lang/words.dart';
import 'package:doculoom/core/i18n/translations.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/core/utils/format.dart';
import 'package:doculoom/core/utils/region.dart';
import 'package:doculoom/core/widgets/text.dart' as app;
import 'package:doculoom/features/export/data/document_builders.dart';
import 'package:doculoom/features/export/domain/entities/export_options.dart';
import 'package:doculoom/features/id_card/domain/id_card.dart';
import 'package:doculoom/features/id_card/presentation/id_card_cubit.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/reminders/domain/reminder_service.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/settings/presentation/settings_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/coins_fakes.dart';
import 'support/pdf_ui_fakes.dart';
import 'support/reminder_fakes.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _NoAds implements AdService {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsRequired() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<RewardResult> showRewarded() async => RewardResult.unavailable;
  @override
  Future<void> showInterstitialIfEligible(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  _Prefs(this.initial);
  final AppSettings initial;
  AppSettings? saved;
  @override
  Future<AppSettings> load() async => initial;
  @override
  Future<void> save(AppSettings settings) async => saved = settings;
}

void resetRegion() {
  Region.apply(paper: PaperChoice.auto, date: DateStyle.auto);
  Region.countryOverride = 'IN';
  Strings.code = 'en';
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    resetRegion();
    await sl.reset();
    sl
      ..registerSingleton<AdService>(_NoAds())
      ..registerSingleton(ReminderService(FakeReminderPlatform()));
  });
  tearDown(resetRegion);

  group('the translation table', () {
    const wordsLanguages = ['hi', 'ar', 'es', 'fr', 'de', 'pt', 'it', 'nl', 'pl', 'tr', 'ru'];
    const europeLanguages = ['es', 'fr', 'de', 'pt', 'it', 'nl', 'pl', 'tr', 'ru'];
    // The text of each tool that is translated as a group: the phrases, and the languages that have all of them.
    final groups = <(String, Set<String>, List<String>)>[
      ('the Europe tools', esEurope.keys.toSet(), europeLanguages),
      ('the amount-in-words tool', esWords.keys.toSet(), wordsLanguages),
      ('the UPI tools', hiUpi.keys.toSet(), const ['hi', 'mr', 'kn']),
      ('the stamp library', esStamps.keys.toSet(), wordsLanguages),
      ('the loyalty cards', esCards.keys.toSet(), wordsLanguages),
      ('the checklists', esLists.keys.toSet(), wordsLanguages),
      ('the application packet', esPacket.keys.toSet(), wordsLanguages),
      ('the CV designs', esCvDesigns.keys.toSet(), wordsLanguages),
      ('the share options', esSharePdf.keys.toSet(), wordsLanguages),
      ('the coins and passes', esCoinsV2.keys.toSet(), wordsLanguages),
      ('the tax, ID and Hijri tools', esTaxSuite.keys.toSet(), wordsLanguages),
      ('the reminder help', esReminderHelp.keys.toSet(), wordsLanguages),
    ];
    final grouped = {for (final g in groups) ...g.$2};
    // What every language has: the Europe phrases are in the Europe languages only, so Hindi stands for the base text.
    final english = translations['hi']!.keys.where((k) => !grouped.contains(k)).toList();

    test('there is a table for each language the picker offers', () {
      expect(translationLanguages.toSet(), {
        for (final l in AppLanguage.values)
          if (l.code != null && l.code != 'en') l.code,
      });
      expect(AppLanguage.supportedCodes.toSet(), {'en', ...translationLanguages});
    });

    test('every language has the same phrases, and none is empty', () {
      for (final lang in translationLanguages) {
        final table = translations[lang]!;
        expect(table.keys.toSet().difference(grouped), english.toSet(), reason: lang);
        // A tool's text is either all there or, when other tools share some phrases, only those.
        for (final (name, keys, languages) in groups) {
          final others = {
            for (final g in groups)
              if (g.$1 != name) ...g.$2,
          };
          final has = table.keys.toSet().intersection(keys);
          if (languages.contains(lang)) {
            expect(has, keys, reason: '$lang: the text of $name');
          } else {
            expect(has.intersection(keys.difference(others)), isEmpty, reason: '$lang: $name');
          }
        }
        for (final e in table.entries) {
          expect(e.value.trim(), isNotEmpty, reason: '$lang ${e.key}');
          expect(e.value, e.value.trim(), reason: 'no stray spaces in $lang "${e.key}"');
        }
      }
    });

    test('keys have no stray spaces and every {name} of the English text is in each translation', () {
      final names = RegExp(r'\{(\w+)\}');
      for (final lang in translationLanguages) {
        for (final e in translations[lang]!.entries) {
          expect(e.key, e.key.trim());
          expect({for (final m in names.allMatches(e.value)) m.group(1)}, {for (final m in names.allMatches(e.key)) m.group(1)}, reason: '$lang ${e.key}');
        }
      }
    });

    test('the main tabs and everyday buttons are translated in every language', () {
      for (final lang in translationLanguages) {
        for (final key in ['Documents', 'Tools', 'Settings', 'Cancel', 'Save', 'Delete', 'Share', 'Scan a document']) {
          expect(translations[lang]![key], isNotNull, reason: '$lang $key');
        }
      }
    });

    test('translations are different from English for nearly every phrase', () {
      // Names and words that are written the same in most languages.
      const names = {
        'Aadhaar',
        'Emirates ID',
        'Rajab',
        'Ramadan',
        'Safar',
        'Muharram',
        'Shawwal',
        'Eid al-Adha',
        'Eid al-Fitr',
        '{day} {month}',
        'Test',
        '30 minutes',
      };
      for (final lang in translationLanguages) {
        final same = [
          for (final e in translations[lang]!.entries)
            if (e.value == e.key && !names.contains(e.key)) e.key,
        ];
        expect(same.length, lessThan(english.length ~/ 15), reason: '$lang: $same');
      }
    });

    test('each language is written in its own script', () {
      final script = {
        'hi': RegExp(r'[\u0900-\u097F]'),
        'mr': RegExp(r'[\u0900-\u097F]'),
        'kn': RegExp(r'[\u0C80-\u0CFF]'),
        'ar': RegExp(r'[\u0600-\u06FF]'),
        'ur': RegExp(r'[\u0600-\u06FF]'),
        'zh': RegExp(r'[\u4E00-\u9FFF]'),
        'ja': RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF]'),
        'ru': RegExp(r'[\u0400-\u04FF]'),
      };
      script.forEach((lang, re) {
        final t = translations[lang]!;
        final inScript = t.values.where(re.hasMatch).length;
        expect(inScript, greaterThan(t.length * 0.9), reason: lang);
      });
    });
  });

  group('tr', () {
    test('English text stays as it is', () {
      expect(tr('Cancel'), 'Cancel');
      expect(tr('A sentence that has no translation'), 'A sentence that has no translation');
    });

    test('text is returned in the chosen language, and text without a translation stays English', () {
      for (final (lang, cancel) in [
        ('hi', 'रद्द करें'),
        ('es', 'Cancelar'),
        ('fr', 'Annuler'),
        ('de', 'Abbrechen'),
        ('pt', 'Cancelar'),
        ('ar', 'إلغاء'),
        ('ur', 'منسوخ کریں'),
        ('zh', '取消'),
        ('ja', 'キャンセル'),
        ('kn', 'ರದ್ದುಮಾಡಿ'),
        ('mr', 'रद्द करा'),
        ('it', 'Annulla'),
        ('nl', 'Annuleren'),
        ('pl', 'Anuluj'),
        ('tr', 'İptal'),
        ('ru', 'Отмена'),
      ]) {
        Strings.code = lang;
        expect(tr('Cancel'), cancel, reason: lang);
        expect(tr('A sentence that has no translation'), 'A sentence that has no translation');
      }
    });

    test('parts of a sentence are filled in', () {
      Strings.code = 'de';
      expect(trf('{n} items for {who}', {'n': 3, 'who': 'you'}), '3 items for you');
    });

    test('the system language follows the phone when it is offered, else English', () {
      Strings.use(AppLanguage.system);
      expect(Strings.code, 'en');
      Strings.use(AppLanguage.hi);
      expect(Strings.code, 'hi');
      expect(AppLanguage.es.locale, const Locale('es'));
      expect(AppLanguage.system.locale, isNull);
    });
  });

  group('the Text widget', () {
    Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: child),
      ),
    );

    testWidgets('shows fixed text in English, and in the chosen language when it has a translation', (tester) async {
      await show(tester, const Column(children: [app.Text('Save'), app.Text('Not translated at all')]));
      expect(find.text('Save'), findsOneWidget);
      Strings.code = 'es';
      await show(
        tester,
        const Column(
          children: [
            app.Text('Save', key: ValueKey('a')),
            app.Text('Not translated at all'),
          ],
        ),
      );
      expect(find.text('Guardar'), findsOneWidget);
      expect(find.text('Not translated at all'), findsOneWidget);
    });

    testWidgets('it is still a framework Text, with its style and limits kept', (tester) async {
      Strings.code = 'fr';
      await show(tester, const app.Text('Cancel', key: ValueKey('t'), maxLines: 1, style: TextStyle(fontSize: 21), overflow: TextOverflow.ellipsis));
      final w = tester.widget<Text>(find.byKey(const ValueKey('t')));
      expect(w, isA<Text>());
      expect(w.data, 'Cancel', reason: 'the widget keeps the English it was given');
      final shown = tester.widget<Text>(find.text('Annuler'));
      expect(shown.maxLines, 1);
      expect(shown.style!.fontSize, 21);
    });

    testWidgets('text made of parts is left as it is', (tester) async {
      Strings.code = 'es';
      await show(tester, app.Text.rich(const TextSpan(text: 'Save')));
      expect(find.textContaining('Save', findRichText: true), findsOneWidget);
    });

    testWidgets('changing the language changes the text on screen when the locale changes', (tester) async {
      Widget app0(Locale locale) => MaterialApp(
        locale: locale,
        supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: app.Text('Settings')),
      );
      await tester.pumpWidget(app0(const Locale('en')));
      expect(find.text('Settings'), findsOneWidget);
      Strings.code = 'de';
      await tester.pumpWidget(app0(const Locale('de')));
      expect(find.text('Einstellungen'), findsOneWidget);
    });

    testWidgets('the built-in widgets have texts for every offered language', (tester) async {
      for (final code in AppLanguage.supportedCodes) {
        late String ok;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(code),
            supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Builder(
              builder: (c) {
                ok = MaterialLocalizations.of(c).cancelButtonLabel;
                return const SizedBox();
              },
            ),
          ),
        );
        expect(ok, isNotEmpty, reason: code);
        if (code != 'en') expect(ok, isNot('Cancel'), reason: code);
      }
    });
  });

  group('dates and counts follow the region and the language', () {
    final day = DateTime(2026, 3, 5, 9, 7);

    test('day first, month first and year first', () {
      Region.apply(paper: PaperChoice.auto, date: DateStyle.dayFirst);
      expect(formatDate(day), '5 Mar 2026');
      Region.apply(paper: PaperChoice.auto, date: DateStyle.monthFirst);
      expect(formatDate(day), 'Mar 5, 2026');
      Region.apply(paper: PaperChoice.auto, date: DateStyle.yearFirst);
      expect(formatDate(day), '2026-03-05');
      expect(formatDateTime(day), '2026-03-05, 09:07');
    });

    test('automatic follows the country', () {
      for (final (country, style) in [('IN', DateStyle.dayFirst), ('GB', DateStyle.dayFirst), ('US', DateStyle.monthFirst), ('JP', DateStyle.yearFirst)]) {
        Region.countryOverride = country;
        expect(Region.dateStyle, style, reason: '$country');
      }
      Region.countryOverride = 'US';
      expect(formatDate(day), 'Mar 5, 2026');
      Region.apply(paper: PaperChoice.auto, date: DateStyle.dayFirst);
      expect(formatDate(day), '5 Mar 2026', reason: 'a choice wins over the region');
    });

    test('month names and page counts are in the chosen language', () {
      final expected = {
        'hi': '5 मार्च 2026',
        'es': '5 mar 2026',
        'fr': '5 mars 2026',
        'de': '5 März 2026',
        'pt': '5 mar 2026',
        'ar': '5 مارس 2026',
        'ur': '5 مارچ 2026',
        'zh': '2026年3月5日',
        'ja': '2026年3月5日',
        'kn': '5 ಮಾರ್ಚ್ 2026',
        'mr': '5 मार्च 2026',
        'it': '5 mar 2026',
        'nl': '5 mrt 2026',
        'pl': '5 mar 2026',
        'tr': '5 Mar 2026',
        'ru': '5 март 2026',
      };
      expected.forEach((lang, text) {
        Strings.code = lang;
        expect(formatDate(day), text, reason: lang);
      });
      Strings.code = 'es';
      expect(pagesLabel(1), '1 página');
      expect(pagesLabel(3), '3 páginas');
      expect(monthYearLabel('2026-12'), 'dic 2026');
      Strings.code = 'ja';
      expect(monthYearLabel('2026-12'), '2026年12月');
      expect(pagesLabel(2), '2 ページ');
      Strings.code = 'ar';
      expect(pagesLabel(1), '1 صفحة');
      expect(pagesLabel(3), '3 صفحات');
      Strings.code = 'pl';
      expect(
        [
          for (final n in [1, 2, 5, 12, 22, 25]) pagesLabel(n),
        ],
        ['1 strona', '2 strony', '5 stron', '12 stron', '22 strony', '25 stron'],
      );
      Strings.code = 'ru';
      expect(
        [
          for (final n in [1, 2, 5, 11, 21, 24]) pagesLabel(n),
        ],
        ['1 страница', '2 страницы', '5 страниц', '11 страниц', '21 страница', '24 страницы'],
      );
      Region.apply(paper: PaperChoice.auto, date: DateStyle.yearFirst);
      Strings.code = 'zh';
      expect(formatDate(day), '2026-03-05', reason: 'a year-first choice is written as numbers');
      Strings.code = 'en';
      expect(pagesLabel(1), '1 page');
      expect(pagesLabel(3), '3 pages');
    });

    test('every language has twelve month names', () {
      for (final lang in translationLanguages) {
        Strings.code = lang;
        final names = [for (var m = 1; m <= 12; m++) monthName(m)];
        expect(names.toSet().length, 12, reason: lang);
      }
    });
  });

  group('paper', () {
    test('Letter is chosen for the countries that use it, A4 elsewhere, and a choice wins', () {
      for (final (country, letter) in [('US', true), ('CA', true), ('MX', true), ('IN', false), ('GB', false), ('DE', false)]) {
        Region.countryOverride = country;
        expect(Region.letter, letter, reason: '$country');
      }
      Region.countryOverride = 'IN';
      Region.apply(paper: PaperChoice.letter, date: DateStyle.auto);
      expect(Region.letter, isTrue);
      expect((Region.paperWidthMm, Region.paperHeightMm), (215.9, 279.4));
      Region.countryOverride = 'US';
      Region.apply(paper: PaperChoice.a4, date: DateStyle.auto);
      expect(Region.letter, isFalse);
      expect((Region.paperWidthMm, Region.paperHeightMm), (210, 297));
    });

    group('exported files', () {
      late Directory dir;
      late PageSource page;

      setUp(() {
        dir = tempDir();
        final image = img.Image(width: 1000, height: 1300);
        img.fill(image, color: img.ColorRgb8(240, 240, 240));
        final file = File('${dir.path}/p.jpg')..writeAsBytesSync(img.encodeJpg(image));
        page = PageSource(path: file.path, width: 1000, height: 1300);
      });
      tearDown(() => dir.deleteSync(recursive: true));

      List<double> mediaBox(String path) {
        final text = String.fromCharCodes(File(path).readAsBytesSync());
        final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]').firstMatch(text)!;
        return [double.parse(m.group(1)!), double.parse(m.group(2)!)];
      }

      test('a PDF page is fitted into A4, or into Letter', () async {
        await buildPdf([page], ExportQuality.high, '${dir.path}/a4.pdf');
        final a4 = mediaBox('${dir.path}/a4.pdf');
        expect(a4[0], closeTo(595, 0.5));
        expect(a4[1], closeTo(773.5, 0.5));
        await buildPdf([page], ExportQuality.high, '${dir.path}/letter.pdf', letter: true);
        final letter = mediaBox('${dir.path}/letter.pdf');
        expect(letter[0], closeTo(609, 0.5));
        expect(letter[1], closeTo(792, 0.5));
      });

      test('the PDF made in the background uses the paper of the region', () async {
        Region.apply(paper: PaperChoice.letter, date: DateStyle.auto);
        await buildPdfInBackground([page], ExportQuality.high, '${dir.path}/bg.pdf');
        expect(mediaBox('${dir.path}/bg.pdf')[1], closeTo(792, 0.5));
      });

      test('a Word file has pages of A4, or of Letter', () {
        String pageSize(bool letter) {
          buildDocx([page], ExportQuality.high, '${dir.path}/x.docx', letter: letter);
          final doc = ZipDecoder().decodeBytes(File('${dir.path}/x.docx').readAsBytesSync());
          final xml = String.fromCharCodes(doc.findFile('word/document.xml')!.content as List<int>);
          return RegExp(r'<w:pgSz [^>]*/>').firstMatch(xml)!.group(0)!;
        }

        expect(pageSize(false), '<w:pgSz w:w="11906" w:h="16838"/>');
        expect(pageSize(true), '<w:pgSz w:w="12240" w:h="15840"/>');
      });
    });

    test('the ID card copy starts on the paper of the region', () {
      final a4 = IdCardCubit(maker: _NoMaker(), workDir: () async => Directory.systemTemp);
      expect(a4.state.options.paper, CardPaper.a4);
      Region.countryOverride = 'US';
      final letter = IdCardCubit(maker: _NoMaker(), workDir: () async => Directory.systemTemp);
      expect(letter.state.options.paper, CardPaper.letter);
    });
  });

  group('languages written from right to left', () {
    Future<TextDirection> directionIn(WidgetTester tester, String code) async {
      late TextDirection d;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (c) {
              d = Directionality.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      return d;
    }

    test('Arabic and Urdu are the right-to-left languages', () {
      for (final l in AppLanguage.values) {
        expect(l.rightToLeft, l == AppLanguage.ar || l == AppLanguage.ur, reason: l.name);
      }
    });

    testWidgets('the screens turn round for them and for no other language', (tester) async {
      for (final code in AppLanguage.supportedCodes) {
        expect(await directionIn(tester, code), AppLanguage.rightToLeftCodes.contains(code) ? TextDirection.rtl : TextDirection.ltr, reason: code);
      }
    });

    testWidgets('a row starts at the right edge, padding and alignment follow the start of the line', (tester) async {
      Future<(double, double, double)> measure(String code) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(code),
            supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: Column(
                  key: const ValueKey('column'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        SizedBox(key: ValueKey('first'), width: 40, height: 10),
                        SizedBox(width: 40, height: 10),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsetsDirectional.only(start: 30),
                      child: SizedBox(key: ValueKey('padded'), width: 10, height: 10),
                    ),
                    Container(
                      alignment: AlignmentDirectional.centerStart,
                      height: 20,
                      child: const SizedBox(key: ValueKey('aligned'), width: 10, height: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        double left(String k) => tester.getTopLeft(find.byKey(ValueKey(k))).dx - tester.getTopLeft(find.byKey(const ValueKey('column'))).dx;
        return (left('first'), left('padded'), left('aligned'));
      }

      final ltr = await measure('en');
      final rtl = await measure('ar');
      expect(ltr, (0.0, 30.0, 0.0));
      expect(rtl, (360.0, 360.0, 390.0), reason: 'the first item of a row is at the right in Arabic');
    });

    testWidgets('arrows that show the way forward and back turn round', (tester) async {
      expect(AppIcons.next.matchTextDirection, isTrue);
      expect(AppIcons.back.matchTextDirection, isTrue);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.rtl,
          child: Icon(AppIcons.next, key: ValueKey('i')),
        ),
      );
      final transforms = find.descendant(of: find.byKey(const ValueKey('i')), matching: find.byType(Transform));
      expect(transforms, findsOneWidget, reason: 'the icon is drawn flipped');
    });

    testWidgets('the Settings screen in Arabic is written in Arabic, from the right, and fits', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      Strings.code = 'ar';
      final cubit = SettingsCubit(_Prefs(const AppSettings(language: AppLanguage.ar)));
      await tester.runAsync(cubit.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => PlanCubit(_Plans())),
            BlocProvider.value(value: cubit),
            BlocProvider(create: (_) => coinsCubit()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const Scaffold(body: SettingsView()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('لغة التطبيق'), 300);
      expect(find.text('لغة التطبيق'), findsOneWidget);
      final label = tester.getTopRight(find.text('لغة التطبيق')).dx;
      expect(label, greaterThan(200), reason: 'the title starts at the right edge');
      expect(tester.takeException(), isNull);
    });
  });

  group('the settings', () {
    test('region and language are kept between visits, and start automatic', () async {
      final repo = SettingsRepositoryImpl();
      final first = await repo.load();
      expect((first.paper, first.dateStyle, first.language), (PaperChoice.auto, DateStyle.auto, AppLanguage.system));
      await repo.save(first.copyWith(paper: PaperChoice.letter, dateStyle: DateStyle.monthFirst, language: AppLanguage.hi));
      final again = await repo.load();
      expect((again.paper, again.dateStyle, again.language), (PaperChoice.letter, DateStyle.monthFirst, AppLanguage.hi));
    });

    test('choosing them changes how the whole app reads', () async {
      final cubit = SettingsCubit(_Prefs(const AppSettings()));
      await cubit.update((s) => s.copyWith(paper: PaperChoice.letter, dateStyle: DateStyle.yearFirst, language: AppLanguage.fr));
      expect(Region.letter, isTrue);
      expect(formatDate(DateTime(2026, 3, 5)), '2026-03-05');
      expect(Strings.code, 'fr');
      await cubit.update((s) => s.copyWith(language: AppLanguage.en));
      expect(Strings.code, 'en');
      await cubit.close();
    });

    testWidgets('the screen offers the three choices, saves them, and its words change at once', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final prefs = _Prefs(const AppSettings());
      final cubit = SettingsCubit(prefs);
      await tester.runAsync(cubit.load);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => PlanCubit(_Plans())),
            BlocProvider.value(value: cubit),
            BlocProvider(create: (_) => coinsCubit()),
          ],
          child: BlocSelector<SettingsCubit, AppSettings, AppLanguage>(
            selector: (s) => s.language,
            builder: (context, language) => MaterialApp(
              theme: AppTheme.light(),
              locale: language.locale,
              supportedLocales: [for (final c in AppLanguage.supportedCodes) Locale(c)],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: const Scaffold(body: SettingsView()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final k in ['setting-language', 'setting-paper', 'setting-date-style']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(find.text('Region and language'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('setting-paper')));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('setting-paper')), matching: find.byType(DropdownButtonFormField<PaperChoice>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('US Letter').last);
      await tester.pumpAndSettle();
      expect(prefs.saved!.paper, PaperChoice.letter);
      expect(Region.letter, isTrue);

      await tester.ensureVisible(find.byKey(const ValueKey('setting-date-style')));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('setting-date-style')), matching: find.byType(DropdownButtonFormField<DateStyle>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Year first: 2026-03-05').last);
      await tester.pumpAndSettle();
      expect(prefs.saved!.dateStyle, DateStyle.yearFirst);

      await tester.ensureVisible(find.byKey(const ValueKey('setting-language')));
      await tester.pump();
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('setting-language')), matching: find.byType(DropdownButtonFormField<AppLanguage>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Español').last);
      await tester.pumpAndSettle();
      expect(prefs.saved!.language, AppLanguage.es);
      expect(Strings.code, 'es');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Escaneo'), -400, scrollable: find.byType(Scrollable).first);
      expect(find.text('Escaneo'), findsOneWidget, reason: 'the section label changed to Spanish');
      expect(find.text('Idioma de la app'), findsOneWidget);
      expect(find.text('Español'), findsWidgets, reason: 'the languages are always named in themselves');
    });
  });
}

class _NoMaker implements IdCardMaker {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

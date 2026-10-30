import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/cv/data/cv_pdf.dart';
import 'package:doculoom/features/cv/data/cv_store.dart';
import 'package:doculoom/features/cv/domain/cv.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/cv/presentation/cv_page.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/pdf_tools/data/pdf_picture_pages.dart';
import 'package:doculoom/features/reader/data/pdf_text_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _asset(String path) => File(path).readAsBytes();

class _Pages implements PdfPicturePages {
  int closed = 0;
  final widths = <int>[];

  @override
  Future<int> open(String path) async => 2;

  @override
  Future<Uint8List> render(int page, {required int width, required bool png}) async {
    widths.add(width);
    return Uint8List.fromList(png ? img.encodePng(img.Image(width: 20, height: 28)) : img.encodeJpg(img.Image(width: 20, height: 28)));
  }

  @override
  Future<void> close() async => closed++;
}

class _Share implements ShareService {
  final files = <List<String>>[];
  String? mime;

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async => const Ok(null);

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async {
    files.add(paths);
    mime = mimeType;
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareText({required String text, String? subject}) async => const Ok(null);
}

class _Save implements SaveService {
  String? name;
  String? mime;

  @override
  Future<Result<bool>> saveToFiles({required String sourcePath, required String fileName, required String mimeType}) async {
    name = fileName;
    mime = mimeType;
    return const Ok(true);
  }

  @override
  Future<Result<int>> saveImagesToGallery(List<String> paths) async => Ok(paths.length);
}

const _cv = CvData(
  name: 'Zoë Kowalski',
  headline: 'Mechanical engineer',
  email: 'zoe@example.eu',
  phone: '+48 600 100 200',
  address: 'ul. Długa 5, 80-001 Gdańsk',
  birthDate: '14.03.1992',
  nationality: 'Polish',
  summary: 'Engineer with eight years in manufacturing.',
  work: [
    CvEntry(title: 'Senior engineer', organisation: 'Werk AG', place: 'München', from: '03/2019', description: 'Led a team of six.'),
    CvEntry(title: 'Engineer', organisation: 'Fabryka', from: '2014', to: '2019'),
  ],
  education: [CvEntry(title: 'MSc Mechanical Engineering', organisation: 'Politechnika Gdańska', from: '2009', to: '2014')],
  skills: ['CAD', 'Lean', 'Projektmanagement'],
  languages: [
    CvLanguage(name: 'Polish', level: 'Native'),
    CvLanguage(name: 'German', level: 'C1'),
  ],
);

String _text(Uint8List pdf) => extractPdfText(pdf).map((p) => p.text).join('\n').replaceAll('\u00A0', ' ');

void main() {
  group('data', () {
    test('survives being saved and read back', () {
      final back = CvData.fromJson(_cv.toJson());
      expect(back.toJson(), _cv.toJson());
      expect(back.work[1].to, '2019');
      expect(back.languages.last.level, 'C1');
    });

    test('damaged data is read as far as possible', () {
      final d = CvData.fromJson({
        'name': 5,
        'work': 'x',
        'languages': [
          1,
          {'name': 'A', 'level': 'Z9'},
        ],
        'skills': ['a', 3],
        'language': '',
      });
      expect((d.name, d.language), ('', 'en'));
      expect(d.work, isEmpty);
      expect(d.languages.last.level, 'B2');
      expect(d.skills, ['a']);
    });

    test('skills are split on commas, semicolons and lines', () {
      expect(splitSkills('CAD, Lean;  Excel\n\n Python ,'), ['CAD', 'Lean', 'Excel', 'Python']);
      expect(splitSkills('  '), isEmpty);
    });

    test('what is missing is named', () {
      expect(cvProblem(const CvData()), contains('name'));
      expect(cvProblem(const CvData(name: 'A')), contains('full name'));
      expect(cvProblem(const CvData(name: 'Anna')), contains('email'));
      expect(cvProblem(const CvData(name: 'Anna', email: 'a@b.eu')), contains('work'));
      expect(cvProblem(const CvData(name: 'Anna', phone: '123456', summary: 'x')), isNull);
      expect(cvProblem(_cv), isNull);
    });

    test('every supported language has every heading', () {
      for (final code in CvLabels.supported.keys) {
        for (final key in ['cv', 'personal', 'profile', 'work', 'education', 'languages', 'skills', 'born', 'nationality', 'present', 'native']) {
          expect(CvLabels.of(code)[key], isNotEmpty, reason: '$code $key');
        }
      }
      expect(CvLabels.of('xx')['work'], 'Work experience');
    });

    test('a photo is made smaller', () {
      final big = img.Image(width: 2000, height: 1200)..clear(img.ColorRgb8(200, 100, 50));
      final small = img.decodeJpg(shrinkPhoto(Uint8List.fromList(img.encodePng(big))))!;
      expect((small.width, small.height), (600, 360));
      expect(() => shrinkPhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });
  });

  group('checks', () {
    final now = DateTime(2026, 10, 28);
    List<String> fields(CvData d) => [for (final i in cvIssues(d, now: now)) i.field];
    const base = CvData(name: 'Anna Rossi', email: 'a@b.eu', summary: 'Hello');

    test('dates are read in the forms people write them', () {
      expect(parseCvDate('03/2019'), (year: 2019, month: 3));
      expect(parseCvDate(' 3.2019 '), (year: 2019, month: 3));
      expect(parseCvDate('2019-03'), (year: 2019, month: 3));
      expect(parseCvDate('2019'), (year: 2019, month: null));
      for (final bad in ['13/2019', '00/2019', '3/19', '1900', '03/2300', 'March 2019', '', '2019/']) {
        expect(parseCvDate(bad), isNull, reason: bad);
      }
      expect(formatCvDate(parseCvDate('3.2019')!), '03/2019');
      expect(parseCvBirthDate('25/03/1990'), DateTime(1990, 3, 25));
      expect(parseCvBirthDate('5.3.1990'), DateTime(1990, 3, 5));
      expect(parseCvBirthDate('1990-03-25'), DateTime(1990, 3, 25));
      for (final bad in ['31/02/1990', '32/01/1990', '25/13/1990', '25/03/90', 'x', '']) {
        expect(parseCvBirthDate(bad), isNull, reason: bad);
      }
      expect(formatCvBirthDate(DateTime(1990, 3, 5)), '05/03/1990');
    });

    test('email, phone and website', () {
      for (final ok in ['a@b.eu', 'first.last+cv@mail.example.co.uk', "o'neil@x.org"]) {
        expect(isCvEmail(ok), isTrue, reason: ok);
      }
      for (final bad in ['a@b', 'a@', '@b.eu', 'a b@c.eu', 'a@b..eu', '']) {
        expect(isCvEmail(bad), isFalse, reason: bad);
      }
      for (final ok in ['+49 170 1234567', '(020) 7946-0958', '+91 98765 43210', '0170.1234567']) {
        expect(isCvPhone(ok), isTrue, reason: ok);
      }
      for (final bad in ['12', 'abc', '+49 170 12345 6789 0123', '12-ab-34567', '']) {
        expect(isCvPhone(bad), isFalse, reason: bad);
      }
      for (final ok in ['www.example.com', 'https://example.eu/anna', 'linkedin.com/in/anna']) {
        expect(isCvWebsite(ok), isTrue, reason: ok);
      }
      for (final bad in ['example', 'http://', 'a b.com', '']) {
        expect(isCvWebsite(bad), isFalse, reason: bad);
      }
    });

    test('characters the PDF font cannot print are found', () {
      expect(isCvPrintable('Zoë Kowalski Łódź Ελένη Иван € – “quotes”'), isTrue);
      for (final bad in ['राम', 'ರಾಮ್', 'محمد', '李雷', 'Ram 😀']) {
        expect(isCvPrintable(bad), isFalse, reason: bad);
      }
      expect(fields(const CvData(name: 'राम शर्मा', email: 'a@b.eu', summary: 'x')), ['name']);
    });

    test('what is missing is named once, at its field', () {
      expect(fields(const CvData()), ['name', 'contact', 'content']);
      expect(fields(const CvData(name: 'A', email: 'a@b.eu', summary: 'x')), ['name'], reason: 'one letter is not a name');
      expect(fields(base), isEmpty);
      expect(fields(const CvData(name: 'Anna', email: 'x', phone: '1', summary: 's', website: 'x', birthDate: '1/1/1')), [
        'email',
        'phone',
        'website',
        'birth',
      ]);
    });

    test('the date of birth must be real and plausible', () {
      CvData born(String b) => CvData(name: 'Anna', email: 'a@b.eu', summary: 's', birthDate: b);
      expect(fields(born('25/03/1990')), isEmpty);
      expect(fields(born('29/02/2023')), ['birth']);
      expect(fields(born('01/01/2027')), ['birth'], reason: 'future');
      expect(fields(born('01/01/2020')), ['birth'], reason: 'too young');
      expect(fields(born('01/01/1900')), ['birth'], reason: 'too old');
      expect(cvIssues(born('01/01/2027'), now: now).single.message, contains('future'));
    });

    test('a job or course needs a title and a start date, and the dates must fit', () {
      CvData job(CvEntry e) => CvData(name: 'Anna', email: 'a@b.eu', work: [e]);
      expect(fields(job(const CvEntry())), ['content'], reason: 'an untouched entry is ignored');
      expect(fields(job(const CvEntry(title: 'Dev', from: '03/2019'))), isEmpty);
      expect(fields(job(const CvEntry(title: 'Dev', from: '03/2019', to: '02/2020'))), isEmpty);
      expect(fields(job(const CvEntry(title: 'Dev'))), ['work.0.from']);
      expect(fields(job(const CvEntry(from: '03/2019', to: '2020'))), ['work.0.title', 'content']);
      expect(fields(job(const CvEntry(title: 'Dev', from: 'March'))), ['work.0.from']);
      expect(fields(job(const CvEntry(title: 'Dev', from: '03/2019', to: '02/2019'))), ['work.0.to']);
      expect(
        fields(job(const CvEntry(title: 'Dev', from: '2019', to: '2019'))),
        isEmpty,
        reason: 'the same year is allowed',
      );
      expect(fields(job(const CvEntry(title: 'Dev', from: '12/2026'))), ['work.0.from'], reason: 'starts in the future');
      expect(fields(job(const CvEntry(title: 'Dev', from: '03/2019', to: '12/2030'))), ['work.0.to'], reason: 'a job cannot have ended yet');
      expect(
        fields(
          CvData(
            name: 'Anna',
            email: 'a@b.eu',
            education: const [CvEntry(title: 'BSc', from: '2024', to: '06/2028')],
          ),
        ),
        isEmpty,
        reason: 'a course may end in the future',
      );
      expect(
        fields(
          CvData(
            name: 'Anna',
            email: 'a@b.eu',
            education: [CvEntry(title: '', from: '2020')],
          ),
        ),
        ['education.0.title', 'content'],
      );
    });

    test('texts that are too long are found', () {
      expect(fields(CvData(name: 'Anna', email: 'a@b.eu', summary: 'x' * 1201)), ['summary']);
      expect(
        fields(
          CvData(
            name: 'Anna',
            email: 'a@b.eu',
            work: [CvEntry(title: 'Dev', from: '2020', description: 'x' * 601)],
          ),
        ),
        ['work.0.description'],
      );
      expect(fields(CvData(name: 'Anna', email: 'a@b.eu', summary: 'x' * 1200)), isEmpty);
    });

    test('dates are tidied before the CV is made', () {
      final t = tidyCv(
        const CvData(
          name: ' Anna ',
          email: 'a@b.eu',
          birthDate: '5.3.1990',
          work: [
            CvEntry(title: ' Dev ', from: '3.2019', to: '2020'),
            CvEntry(),
          ],
        ),
      );
      expect(
        (t.name, t.birthDate, t.work.length, t.work.single.title, t.work.single.from, t.work.single.to),
        ('Anna', '05/03/1990', 1, 'Dev', '03/2019', '2020'),
      );
    });

    test('an unknown layout or colour falls back to the default', () {
      final d = CvData.fromJson({'template': 'zzz', 'accent': 5});
      expect((d.template, d.accent), ('europe', defaultCvAccent));
      expect(CvData.fromJson(const CvData(template: 'modern', accent: 0xFF0F766E).toJson()).template, 'modern');
    });

    test('the font files are listed in pubspec.yaml, or the PDF cannot be made on a phone', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/fonts/'));
      expect(File('assets/fonts/Roboto-Regular.ttf').existsSync() && File('assets/fonts/Roboto-Bold.ttf').existsSync(), isTrue);
    });
  });

  group('the PDF', () {
    for (final template in cvTemplates.keys) {
      test('the $template layout has everything, with and without a photo', () async {
        final photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 100, height: 100)..clear(img.ColorRgb8(10, 120, 200))));
        final d = CvData.fromJson({..._cv.toJson(), 'template': template, 'accent': cvAccents[1]});
        final design = cvDesignOf(template);
        final without = await buildCvPdf(d, loadAsset: _asset);
        final withPhoto = await buildCvPdf(d, loadAsset: _asset, photo: photo);
        if (design.hasPhoto) expect(withPhoto.length, greaterThan(without.length));
        final text = _text(withPhoto).toLowerCase();
        for (final s in [
          'zoë kowalski',
          'mechanical engineer',
          'work experience',
          'senior engineer',
          'werk ag',
          'projektmanagement',
          'german',
          'zoe@example.eu',
        ]) {
          expect(text, contains(s), reason: '$template $s');
        }
        // US and UK CVs leave out the birth date and nationality.
        expect(text.contains('14.03.1992'), design.personal, reason: template);
      });
    }

    for (final design in cvDesigns) {
      test('the ${design.id} design continues on more pages and keeps every entry', () async {
        final many = CvData(
          name: 'A',
          email: 'a@b.eu',
          template: design.id,
          skills: ['One', 'Two'],
          languages: [const CvLanguage(name: 'German', level: 'B1')],
          work: [for (var i = 0; i < 40; i++) CvEntry(title: 'Job $i', organisation: 'Org $i', from: '$i', description: 'Did things. ' * 20)],
        );
        final pages = extractPdfText(await buildCvPdf(many, loadAsset: _asset));
        expect(pages.length, greaterThan(1), reason: design.id);
        final all = pages.map((p) => p.text).join(' ');
        expect(all, contains('Job 0'));
        expect(all, contains('Job 39'));
      });
    }

    test('has the CV in the chosen language with accents', () async {
      // Headings are set in capitals, so the check ignores case.
      final text = _text(await buildCvPdf(CvData.fromJson({..._cv.toJson(), 'language': 'de'}), loadAsset: _asset)).toLowerCase();
      for (final s in [
        'Zoë Kowalski',
        'Mechanical engineer',
        'Berufserfahrung',
        'Ausbildung',
        'Sprachkenntnisse',
        'Kenntnisse',
        'Pers\u00F6nliche Daten',
        'Senior engineer',
        'Werk AG, München',
        '03/2019 \u2013 heute',
        '2014 \u2013 2019',
        'Politechnika Gdańska',
        'Muttersprache',
        'C1',
        'Projektmanagement',
        'Geburtsdatum',
        'Długa',
      ]) {
        expect(text, contains(s.toLowerCase()), reason: s);
      }
    });

    test('with a photo, in English, and as US Letter', () async {
      final photo = Uint8List.fromList(img.encodeJpg(img.Image(width: 100, height: 100)..clear(img.ColorRgb8(10, 120, 200))));
      final bytes = await buildCvPdf(_cv, loadAsset: _asset, photo: photo);
      expect(_text(bytes).toLowerCase(), contains('work experience'));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan((await buildCvPdf(_cv, loadAsset: _asset)).length), reason: 'the picture is inside');
    });

    test('a long CV continues on more pages', () async {
      final many = CvData(
        name: 'A',
        email: 'a@b.eu',
        work: [for (var i = 0; i < 40; i++) CvEntry(title: 'Job $i', organisation: 'Org $i', from: '$i', description: 'Did things. ' * 20)],
      );
      final pages = extractPdfText(await buildCvPdf(many, loadAsset: _asset));
      expect(pages.length, greaterThan(1));
      expect(pages.map((p) => p.text).join(' '), contains('Job 39'));
    });

    test('a CV with only a name and a profile still works', () async {
      final text = _text(
        await buildCvPdf(
          const CvData(name: 'Only Name', email: 'x@y.eu', summary: 'Hello'),
          loadAsset: _asset,
        ),
      );
      expect(text, contains('Only Name'));
      expect(text, contains('Hello'));
      expect(text.toLowerCase(), isNot(contains('work experience')));
    });
  });

  group('page', () {
    late Directory work, app;
    setUp(() {
      work = Directory.systemTemp.createTempSync('sv_cv_w');
      app = Directory.systemTemp.createTempSync('sv_cv_a');
    });
    tearDown(() {
      work.deleteSync(recursive: true);
      app.deleteSync(recursive: true);
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 16; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await tester.pump();
    }

    Future<void> open(WidgetTester tester, {double width = 400, Future<String?> Function()? pick, PdfPicturePages Function()? pages}) async {
      tester.view.physicalSize = Size(width * 3, 5000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CvPage(
            workDir: () async => work,
            appDir: () async => app,
            loadAsset: _asset,
            pickPhoto: pick ?? () async => null,
            pdfPages: pages ?? _Pages.new,
          ),
        ),
      );
      await settle(tester);
    }

    testWidgets('makes a PDF, and the draft and photo come back next time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final pic = File('${app.path}/pic.png')..writeAsBytesSync(img.encodePng(img.Image(width: 50, height: 50)..clear(img.ColorRgb8(1, 2, 3))));
      await open(tester, pick: () async => pic.path);
      await tester.enterText(find.widgetWithText(TextField, 'Full name *'), 'Anna Rossi');
      await tester.enterText(find.widgetWithText(TextField, 'Email *'), 'anna@example.eu');
      await tester.enterText(find.widgetWithText(TextField, 'Job title *'), 'Designer');
      await tester.enterText(find.widgetWithText(TextField, 'Employer'), 'Studio');
      await tester.enterText(find.widgetWithText(TextField, 'From (03/2019) *').first, '3.2019');
      await tester.tap(find.byKey(const ValueKey('work-current-0')));
      await tester.pump();
      await tester.tap(find.text('Add a language'));
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Language'), 'Italian');
      await tester.pump();
      await tester.tap(find.text('Add a photo'));
      await settle(tester);
      expect(find.text('Change photo'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('create-cv')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-cv')));
      await settle(tester);
      final file = Directory('${work.path}/cv').listSync().whereType<File>().single;
      expect(file.path, endsWith('CV_Anna_Rossi.pdf'));
      final text = _text(file.readAsBytesSync());
      expect(text, contains('Anna Rossi'));
      expect(text, contains('Designer'));
      expect(text, contains('Italian'));
      expect(text, contains('03/2019'), reason: 'the date is written in one form');

      await open(tester);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Full name *')).controller!.text, 'Anna Rossi');
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Language')).controller!.text, 'Italian');
      expect(find.text('Change photo'), findsOneWidget);
    });

    Future<void> fillAndCreate(WidgetTester tester) async {
      await tester.enterText(find.widgetWithText(TextField, 'Full name *'), 'Anna Rossi');
      await tester.enterText(find.widgetWithText(TextField, 'Email *'), 'anna@example.eu');
      await tester.enterText(find.widgetWithText(TextField, 'Job title *'), 'Designer');
      await tester.enterText(find.widgetWithText(TextField, 'From (03/2019) *').first, '03/2019');
      await tester.ensureVisible(find.byKey(const ValueKey('work-current-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('work-current-0')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('create-cv')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-cv')));
      await settle(tester);
    }

    testWidgets('a design is chosen from the gallery, described, kept and used', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('template-sidebar_dark')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('template-sidebar_dark')));
      await tester.pump();
      expect(find.textContaining('A dark column with coloured headings.'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('accent-${cvAccents[7]}')));
      await tester.pump(const Duration(milliseconds: 900));
      await fillAndCreate(tester);
      expect(_text(Directory('${work.path}/cv').listSync().whereType<File>().single.readAsBytesSync()), contains('Anna Rossi'));
      final saved = await CvStore(appDir: () async => app).load();
      expect((saved.template, saved.accent), ('sidebar_dark', cvAccents[7]));

      await open(tester);
      expect(find.textContaining('A dark column with coloured headings.'), findsOneWidget);
    });

    testWidgets('a black and white design is chosen and the colours go away', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('template-ats')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('template-ats')));
      await tester.pump();
      expect(find.byKey(const ValueKey('mono-note')), findsOneWidget);
      expect(find.textContaining('The birth date and nationality are left out.'), findsOneWidget);
    });

    testWidgets('the finished CV can be previewed, saved to Files and shared as pictures', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final share = _Share(), save = _Save(), pages = _Pages();
      await open(tester, pages: () => pages);
      sl.registerSingleton<ShareService>(share);
      sl.registerSingleton<SaveService>(save);
      await fillAndCreate(tester);

      await tester.ensureVisible(find.byKey(const ValueKey('cv-preview')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cv-preview')));
      await settle(tester);
      expect(find.byKey(const ValueKey('preview-pages')), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(pages.closed, 1);
      await tester.tap(find.byKey(const ValueKey('preview-close')));
      await settle(tester);
      expect(find.byKey(const ValueKey('preview-pages')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('cv-save')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cv-save')));
      await settle(tester);
      expect((save.name, save.mime), ('CV_Anna_Rossi.pdf', 'application/pdf'));

      await tester.ensureVisible(find.byKey(const ValueKey('cv-pictures')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cv-pictures')));
      await settle(tester);
      expect(share.mime, 'image/jpeg');
      expect(share.files.single.map((f) => f.split('/').last), ['CV_Anna_Rossi_1.jpg', 'CV_Anna_Rossi_2.jpg']);
      expect(share.files.single.every((f) => File(f).existsSync()), isTrue);
      expect(pages.widths.last, 1654);
      expect(pages.closed, 2);
    });

    testWidgets('asks for what is missing', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('create-cv')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-cv')));
      await settle(tester);
      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Fix the marked fields, then try again.'), findsOneWidget);
      expect(Directory('${work.path}/cv').existsSync(), isFalse);
    });

    testWidgets('wrong values are shown next to their field, and fixing them clears the message', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Full name *'), 'Anna Rossi');
      await tester.enterText(find.widgetWithText(TextField, 'Email *'), 'anna@');
      await tester.enterText(find.widgetWithText(TextField, 'Phone *'), '12');
      await tester.enterText(find.widgetWithText(TextField, 'Date of birth (optional)'), '31/02/1990');
      await tester.enterText(find.widgetWithText(TextField, 'Job title *'), 'Designer');
      await tester.enterText(find.widgetWithText(TextField, 'From (03/2019) *').first, '13/2019');
      await tester.ensureVisible(find.byKey(const ValueKey('create-cv')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-cv')));
      await settle(tester);
      expect(find.textContaining('The email address is not valid'), findsOneWidget);
      expect(find.textContaining('The phone number is not valid'), findsOneWidget);
      expect(find.textContaining('not a real date'), findsOneWidget);
      expect(find.textContaining('The date is not valid. Use MM/YYYY'), findsOneWidget);
      expect(find.text('Enter the end date, or tick that you are still there.'), findsNothing, reason: 'one problem per field');
      expect(Directory('${work.path}/cv').existsSync(), isFalse);

      await tester.enterText(find.widgetWithText(TextField, 'Email *'), 'anna@example.eu');
      await tester.pump();
      expect(find.textContaining('The email address is not valid'), findsNothing);
    });

    testWidgets('an end date is asked for unless the job is current', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Full name *'), 'Anna Rossi');
      await tester.enterText(find.widgetWithText(TextField, 'Email *'), 'anna@example.eu');
      await tester.enterText(find.widgetWithText(TextField, 'Job title *'), 'Designer');
      await tester.enterText(find.widgetWithText(TextField, 'From (03/2019) *').first, '03/2019');
      await tester.ensureVisible(find.byKey(const ValueKey('create-cv')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-cv')));
      await settle(tester);
      expect(find.text('Enter the end date, or tick that you are still there.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('work-current-0')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('work-current-0')));
      await tester.pump();
      expect(find.text('Enter the end date, or tick that you are still there.'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('create-cv')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-cv')));
      await settle(tester);
      expect(Directory('${work.path}/cv').listSync(), hasLength(1));
    });

    testWidgets('the layout and colour are kept and used', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('template-classic')));
      await tester.tap(find.byKey(const ValueKey('template-classic')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('accent-${cvAccents[3]}')));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      final saved = await CvStore(appDir: () async => app).load();
      expect((saved.template, saved.accent), ('classic', cvAccents[3]));
    });

    testWidgets('a photo that is not a picture is refused', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final bad = File('${app.path}/bad.png')..writeAsBytesSync([1, 2, 3]);
      await open(tester, pick: () async => bad.path);
      await tester.tap(find.text('Add a photo'));
      await settle(tester);
      expect(find.text('That picture could not be used.'), findsOneWidget);
      expect(find.text('Add a photo'), findsOneWidget);
    });

    test('the store can be cleared', () async {
      SharedPreferences.setMockInitialValues({});
      final store = CvStore(appDir: () async => app);
      await store.save(_cv);
      await store.savePhoto(Uint8List.fromList([1, 2, 3]));
      expect((await store.load()).name, 'Zoë Kowalski');
      expect(await store.loadPhoto(), isNotNull);
      await store.clear();
      expect((await store.load()).name, '');
      expect(await store.loadPhoto(), isNull);
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('fits at ${width.toInt()} px', (tester) async {
        SharedPreferences.setMockInitialValues({});
        await open(tester, width: width);
        await tester.tap(find.text('Add a language'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

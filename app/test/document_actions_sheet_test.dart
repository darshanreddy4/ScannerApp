import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/reminder_fakes.dart';
import 'package:go_router/go_router.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/compress_level.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';
import 'package:doculoom/features/documents/presentation/widgets/document_actions.dart';
import 'package:doculoom/features/monetization/domain/entities/plan_status.dart';
import 'package:doculoom/features/ocr/domain/ocr_engine.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/ocr/domain/recognize_document_text.dart';
import 'package:doculoom/features/ocr/domain/text_repository.dart';
import 'package:doculoom/features/speech/presentation/read_aloud_page.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/monetization/presentation/plan_cubit.dart';
import 'package:doculoom/features/reminders/data/reminder_platform.dart';
import 'package:doculoom/features/reminders/domain/reminder_service.dart';
import 'package:doculoom/features/settings/data/settings_repository.dart';
import 'package:doculoom/features/settings/domain/app_settings.dart';
import 'package:doculoom/features/settings/presentation/settings_cubit.dart';
import 'package:doculoom/features/tables/presentation/table_page.dart';

class _Plans implements PlanRepository {
  @override
  Future<PlanStatus> current() async => PlanStatus.free;
  @override
  Future<void> setPlan(PlanStatus plan) async {}
}

class _Prefs implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _CardEngine implements OcrEngine {
  _CardEngine({this.fail = false});
  final bool fail;

  @override
  Future<Result<OcrPageResult>> recognize(String imagePath, OcrScript script) async {
    if (fail) return const Err(OcrFailure('no text engine'));
    const lines = ['Tara Dsouza', 'Head of Sales', '+971 4 123 4567'];
    return Ok(
      OcrPageResult(
        width: 10,
        height: 10,
        blocks: [
          OcrBlock(lines: [for (final l in lines) OcrLine(text: l, left: 0, top: 0, right: 1, bottom: 1)]),
        ],
      ),
    );
  }
}

class _CardTexts implements TextRepository {
  _CardTexts([this.saved = const []]);
  final List<PageText> saved;

  @override
  Future<Result<List<PageText>>> loadText(String documentId) async => Ok(saved);

  @override
  Future<Result<void>> saveText(String documentId, List<PageText> pages) async => const Ok(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Docs implements DocumentRepository {
  final metaCalls = <String>[];
  final expiryCalls = <({DateTime? expires, bool clear})>[];
  final splits = <(String, int)>[];

  @override
  Future<Result<ScannedDocument>> splitDocument({required String id, required int startPage}) async {
    splits.add((id, startPage));
    return Ok(_doc(pageCount: 2));
  }

  @override
  Future<Result<int>> documentSize(String id) async => const Ok(452 * 1024);

  @override
  Future<Result<ScannedDocument>> updateMeta(
    String id, {
    bool? favorite,
    bool? pinned,
    bool? locked,
    List<String>? tags,
    DateTime? date,
    DateTime? expires,
    bool clearExpiry = false,
  }) async {
    metaCalls.add('fav=$favorite pin=$pinned');
    if (expires != null || clearExpiry) expiryCalls.add((expires: expires, clear: clearExpiry));
    return Ok(_doc(favorite: favorite ?? false, pinned: pinned ?? false));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

ScannedDocument _doc({bool favorite = false, bool pinned = false, int pageCount = 0, DateTime? expires}) => ScannedDocument(
  id: 'd1',
  title: 'Rent agreement',
  createdAt: DateTime(2026, 3, 1),
  updatedAt: DateTime(2026, 3, 2),
  pages: [for (var i = 0; i < pageCount; i++) DocumentPage(id: 'p$i', position: i, imagePath: '/x/$i.jpg', rawPath: '/x/r$i.jpg', width: 10, height: 10)],
  favorite: favorite,
  pinned: pinned,
  expiresAt: expires,
);

void main() {
  late _Docs docs;
  late FakeReminderPlatform reminders;

  setUpAll(() {
    docs = _Docs();
    sl.registerSingleton<GetDocumentSize>(GetDocumentSize(docs));
    sl.registerSingleton<UpdateDocumentMeta>(UpdateDocumentMeta(docs));
    sl.registerSingleton<SplitDocument>(SplitDocument(docs));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reminders = FakeReminderPlatform(access: ReminderAccess.denied, afterAsk: ReminderAccess.granted);
    if (sl.isRegistered<ReminderService>()) sl.unregister<ReminderService>();
    sl.registerSingleton(ReminderService(reminders));
  });

  Future<void> open(WidgetTester tester, {double width = 360, int pages = 0, DateTime? expires}) async {
    tester.view.physicalSize = Size(width * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDocumentActions(
                    context,
                    _doc(pageCount: pages, expires: expires),
                    refresh: () async {},
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/ocr',
          builder: (_, s) => Scaffold(body: Text('OCR ${(s.extra! as ScannedDocument).title}')),
        ),
        GoRoute(
          path: '/read-aloud',
          builder: (_, s) => Scaffold(body: Text('SPEAK ${(s.extra! as ReadAloudArgs).title}: ${(s.extra! as ReadAloudArgs).text}')),
        ),
        GoRoute(
          path: '/table',
          builder: (_, s) => Scaffold(body: Text('TABLE ${(s.extra! as TableArgs).title}: ${(s.extra! as TableArgs).imagePaths.join(',')}')),
        ),
        GoRoute(
          path: '/contact',
          builder: (_, s) => Scaffold(body: Text('CONTACT ${s.extra}')),
        ),
        GoRoute(
          path: '/print',
          builder: (_, s) => Scaffold(body: Text('PRINT ${(s.extra! as ScannedDocument).title}')),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => PlanCubit(_Plans())),
          BlocProvider(create: (_) => SettingsCubit(_Prefs())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet shows the header, quick actions and rows without overflow on a narrow phone', (tester) async {
    await open(tester, width: 320);

    expect(find.text('Rent agreement'), findsOneWidget);
    expect(find.textContaining('452 kB'), findsOneWidget);
    for (final label in ['Share PDF', 'Share images', 'Print', 'Compress', 'Lock', 'Delete']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Save to Files or Drive (PDF)'), findsOneWidget);
    expect(find.text('Move to folder'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet is not stretched across a tablet', (tester) async {
    await open(tester, width: 1280);
    expect(tester.getSize(find.byType(GridView)).width, lessThanOrEqualTo(640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit and More expand to show the extra actions', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.text('Split document'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Split document'), findsOneWidget);

    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Date and time'));
    await tester.pumpAndSettle();
    for (final label in ['Add to favourites', 'Pin to top', 'Tags', 'Duplicate', 'Date and time']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Extract text opens the text screen for the document', (tester) async {
    await open(tester);
    await tester.ensureVisible(find.text('Extract text (OCR)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extract text (OCR)'));
    await tester.pumpAndSettle();
    expect(find.text('OCR Rent agreement'), findsOneWidget);
  });

  testWidgets('Contact from card reads the pages again and opens the contact screen, every time it is chosen', (tester) async {
    sl.registerSingleton(RecognizeDocumentText(_CardEngine(), _CardTexts()));
    addTearDown(() => sl.unregister<RecognizeDocumentText>());
    for (var i = 0; i < 2; i++) {
      await open(tester, pages: 1);
      await tester.ensureVisible(find.text('Contact from card'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact from card'));
      await tester.pumpAndSettle();
      expect(find.textContaining('CONTACT Tara Dsouza'), findsOneWidget, reason: 'round ${i + 1}');
      expect(find.textContaining('+971 4 123 4567'), findsOneWidget);
    }
  });

  testWidgets('Contact from card shows the failure and stays on the document when the text cannot be read', (tester) async {
    sl.registerSingleton(RecognizeDocumentText(_CardEngine(fail: true), _CardTexts()));
    addTearDown(() => sl.unregister<RecognizeDocumentText>());
    await open(tester, pages: 1);
    await tester.ensureVisible(find.text('Contact from card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contact from card'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CONTACT'), findsNothing);
    expect(find.textContaining('no text engine'), findsOneWidget);
  });

  testWidgets('Read aloud uses the text that was already read, without reading the pages again', (tester) async {
    sl.registerSingleton<TextRepository>(_CardTexts([const PageText(position: 0, script: OcrScript.latin, markdown: '# Lease', plain: 'Lease terms apply.')]));
    addTearDown(() => sl.unregister<TextRepository>());
    await open(tester, pages: 1);
    await tester.ensureVisible(find.text('Read aloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read aloud'));
    await tester.pumpAndSettle();
    expect(find.text('SPEAK Rent agreement: Lease terms apply.'), findsOneWidget);
  });

  testWidgets('Read aloud on a document whose text was not read yet reads the pages first', (tester) async {
    sl
      ..registerSingleton<TextRepository>(_CardTexts())
      ..registerSingleton(RecognizeDocumentText(_CardEngine(), _CardTexts()));
    addTearDown(() {
      sl.unregister<TextRepository>();
      sl.unregister<RecognizeDocumentText>();
    });
    await open(tester, pages: 1);
    await tester.ensureVisible(find.text('Read aloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read aloud'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SPEAK Rent agreement: Tara Dsouza'), findsOneWidget);
  });

  testWidgets('Read aloud stays on the document and shows the failure when the pages cannot be read', (tester) async {
    sl
      ..registerSingleton<TextRepository>(_CardTexts())
      ..registerSingleton(RecognizeDocumentText(_CardEngine(fail: true), _CardTexts()));
    addTearDown(() {
      sl.unregister<TextRepository>();
      sl.unregister<RecognizeDocumentText>();
    });
    await open(tester, pages: 1);
    await tester.ensureVisible(find.text('Read aloud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Read aloud'));
    await tester.pumpAndSettle();
    expect(find.textContaining('SPEAK'), findsNothing);
    expect(find.textContaining('no text engine'), findsOneWidget);
  });

  testWidgets('Table to spreadsheet opens the table screen with the picture of every page', (tester) async {
    await open(tester, pages: 2);
    await tester.ensureVisible(find.text('Table to spreadsheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Table to spreadsheet'));
    await tester.pumpAndSettle();
    expect(find.text('TABLE Rent agreement: /x/0.jpg,/x/1.jpg'), findsOneWidget);
  });

  testWidgets('Print closes the sheet and opens the print screen for the document', (tester) async {
    await open(tester);
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();
    expect(find.text('PRINT Rent agreement'), findsOneWidget);
  });

  testWidgets('Split document opens a chooser and splits at the chosen page', (tester) async {
    docs.splits.clear();
    await open(tester, pages: 3);
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Split document'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split document'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: 'the chooser must lay out without framework errors');
    expect(find.text('Choose where the new document starts. Earlier pages stay here.'), findsOneWidget);
    expect(find.text('Pages 2 to 3'), findsOneWidget);
    expect(find.text('Page 3 only'), findsOneWidget);

    await tester.tap(find.text('Pages 2 to 3'));
    await tester.pumpAndSettle();
    expect(docs.splits, [('d1', 2)]);
  });

  testWidgets('a one-page document explains why it cannot be split instead of doing nothing', (tester) async {
    docs.splits.clear();
    await open(tester, pages: 1);
    await tester.ensureVisible(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Split document'));
    await tester.pumpAndSettle();
    expect(find.text('Needs at least 2 pages'), findsOneWidget);
    await tester.tap(find.text('Split document'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where the new document starts. Earlier pages stay here.'), findsNothing);
    expect(docs.splits, isEmpty);
  });

  testWidgets('Add to favourites saves the change', (tester) async {
    docs.metaCalls.clear();
    await open(tester);
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Add to favourites'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to favourites'));
    await tester.pumpAndSettle();
    expect(docs.metaCalls, ['fav=true pin=null']);
  });

  test('compress levels describe themselves', () {
    for (final level in CompressLevel.values) {
      expect(level.label, isNotEmpty);
      expect(level.maxSide, greaterThan(0));
    }
  });

  testWidgets('Set expiry date: choose a day and it is saved at midday of that day', (tester) async {
    docs.expiryCalls.clear();
    await open(tester);
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set expiry date'));
    await tester.tap(find.text('Set expiry date'));
    await tester.pumpAndSettle();
    expect(find.text('When does it expire?'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final call = docs.expiryCalls.single;
    final now = DateTime.now();
    expect(call.clear, isFalse);
    expect(call.expires, DateTime(now.year + 1, now.month, now.day, 12));
  });

  testWidgets('a document with an expiry date can have it changed or removed', (tester) async {
    docs.expiryCalls.clear();
    await open(tester, expires: DateTime(2027, 5, 9, 12));
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Expiry:'));
    await tester.tap(find.textContaining('Expiry:'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expiry-change')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expiry-remove')));
    await tester.pumpAndSettle();
    expect(docs.expiryCalls.single, (expires: null, clear: true));
  });

  Future<void> setDate(WidgetTester tester) async {
    await tester.ensureVisible(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set expiry date'));
    await tester.tap(find.text('Set expiry date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('the first expiry date explains the reminders and asks for notification permission', (tester) async {
    docs.expiryCalls.clear();
    await open(tester);
    await setDate(tester);
    expect(docs.expiryCalls, hasLength(1), reason: 'the date is saved first');
    expect(find.text('Get a reminder?'), findsOneWidget);
    expect(find.textContaining('30 days before, 7 days before and on the day'), findsOneWidget);
    expect(reminders.requests, 0, reason: 'nothing is asked before the person agrees');

    await tester.tap(find.byKey(const ValueKey('reminder-allow')));
    await tester.pumpAndSettle();
    expect(reminders.requests, 1);
  });

  testWidgets('"Not now" asks nothing, and the question does not come back for the next date', (tester) async {
    docs.expiryCalls.clear();
    await open(tester);
    await setDate(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(reminders.requests, 0);
    expect(docs.expiryCalls, hasLength(1));
  });

  testWidgets('when the system will not ask again, or reminders are already allowed, no question is shown', (tester) async {
    for (final access in [ReminderAccess.granted, ReminderAccess.blocked, ReminderAccess.unsupported]) {
      reminders.access = access;
      docs.expiryCalls.clear();
      await open(tester);
      await setDate(tester);
      expect(find.text('Get a reminder?'), findsNothing, reason: access.name);
      expect(docs.expiryCalls, hasLength(1), reason: access.name);
      await tester.pumpWidget(const SizedBox());
    }
  });
}

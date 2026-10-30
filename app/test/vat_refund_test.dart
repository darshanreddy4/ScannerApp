import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/core/theme/app_colors.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/export/domain/repositories/export_repository.dart';
import 'package:doculoom/features/vat_refund/data/vat_refund_store.dart';
import 'package:doculoom/features/vat_refund/domain/vat_refund.dart';
import 'package:doculoom/features/vat_refund/presentation/vat_refund_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Share implements ShareService {
  String? path;
  String? content;

  @override
  Future<Result<void>> shareFile({required String path, required String mimeType, String? subject}) async {
    this.path = path;
    content = File(path).readAsStringSync();
    return const Ok(null);
  }

  @override
  Future<Result<void>> shareFiles({required List<String> paths, required String mimeType, String? subject}) async => const Ok(null);

  @override
  Future<Result<void>> shareText({required String text, String? subject}) async => const Ok(null);
}

/// Pictures are copied at once, so a widget test need not wait on real files and a second thread.
class _FakeStore extends VatRefundStore {
  _FakeStore(this.dir) : super(appDir: () async => dir);
  final Directory dir;
  var copies = 0;

  @override
  Future<String?> addPhoto(String sourcePath) async {
    final f = File(p.join(dir.path, 'copy_${copies++}.jpg'))..writeAsBytesSync(File(sourcePath).readAsBytesSync());
    return f.path;
  }
}

VatReceipt _r(
  String id,
  DateTime date, {
  int total = 10000,
  int vat = 1667,
  RefundStatus status = RefundStatus.toStamp,
  String currency = 'EUR',
  String store = 'Shop',
  String country = 'DE',
}) => VatReceipt(id: id, store: store, country: country, date: date, totalCents: total, vatCents: vat, currency: currency, status: status);

void main() {
  group('amounts and dates', () {
    test('the VAT inside a price', () {
      expect(vatInPrice(12000, 20), 2000);
      expect(vatInPrice(24990, 19), 3990);
      expect(vatInPrice(10000, 25.5), 2032);
      expect(vatInPrice(0, 19), 0);
      expect(vatInPrice(100, 0), 0);
    });

    test('the deadline is the end of the third month after the purchase', () {
      expect(exportDeadline(DateTime(2025, 1, 15)), DateTime(2025, 4, 30));
      expect(exportDeadline(DateTime(2025, 10, 31)), DateTime(2026, 1, 31));
      expect(exportDeadline(DateTime(2025, 12, 1)), DateTime(2026, 3, 31));
      expect(exportDeadline(DateTime(2023, 11, 20)), DateTime(2024, 2, 29));
    });

    test('days left count down to zero on the last day and then go negative', () {
      final purchase = DateTime(2025, 1, 15);
      expect(daysLeft(purchase, DateTime(2025, 4, 30, 23, 59)), 0);
      expect(daysLeft(purchase, DateTime(2025, 4, 29)), 1);
      expect(daysLeft(purchase, DateTime(2025, 5, 1)), -1);
      expect(daysLeft(purchase, DateTime(2025, 1, 15)), 105);
    });

    test('only an unstamped receipt can expire', () {
      final late = DateTime(2025, 5, 1);
      expect(isExpired(_r('a', DateTime(2025, 1, 15)), late), isTrue);
      expect(isExpired(_r('b', DateTime(2025, 1, 15), status: RefundStatus.stamped), late), isFalse);
      expect(isExpired(_r('c', DateTime(2025, 3, 15)), late), isFalse);
    });
  });

  group('summary and spreadsheet', () {
    test('adds the VAT up per currency and state', () {
      final now = DateTime(2025, 5, 1);
      final t = summarize([
        _r('1', DateTime(2025, 4, 1), vat: 1000),
        _r('2', DateTime(2025, 4, 2), vat: 500, status: RefundStatus.stamped),
        _r('3', DateTime(2025, 4, 3), vat: 250, status: RefundStatus.sent),
        _r('4', DateTime(2025, 4, 4), vat: 100, status: RefundStatus.refunded),
        _r('5', DateTime(2025, 1, 4), vat: 75),
        _r('6', DateTime(2025, 4, 5), vat: 900, currency: 'SEK'),
      ], now);
      expect(t.map((e) => e.currency), ['EUR', 'SEK']);
      final eur = t.first;
      expect((eur.waitingCents, eur.stampedCents, eur.refundedCents, eur.lostCents), (1000, 750, 100, 75));
      expect(t.last.waitingCents, 900);
      expect(summarize(const [], now), isEmpty);
    });

    test('the CSV has a header, quotes where needed and the newest first', () {
      final csv = receiptsCsv([
        _r('1', DateTime(2025, 3, 1), store: 'Old, "Shop"', total: 12345, vat: 2000),
        VatReceipt(
          id: '2',
          store: 'New',
          country: 'FR',
          date: DateTime(2025, 4, 5),
          totalCents: 5000,
          vatCents: 833,
          status: RefundStatus.refunded,
          formNumber: 'F-7',
          note: 'gift',
        ),
      ]);
      final lines = csv.trim().split('\n');
      expect(lines.first, 'Date,Store,Country,Currency,Total,VAT,Status,Deadline,Form number,Note');
      expect(lines[1], '2025-04-05,New,FR,EUR,50.00,8.33,refunded,2025-07-31,F-7,gift');
      expect(lines[2], '2025-03-01,"Old, ""Shop""",DE,EUR,123.45,20.00,toStamp,2025-06-30,,');
    });
  });

  group('country table', () {
    test('finds countries in any letter case and has usable data', () {
      expect(refundCountry('de')!.name, 'Germany');
      expect(refundCountry('XX'), isNull);
      for (final c in refundCountries) {
        expect(c.code.length, 2);
        expect(c.vatRate, greaterThan(0));
        expect(c.currency.length, 3);
      }
      expect(refundCountries.map((c) => c.code).toSet().length, refundCountries.length);
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('sv_vat');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('keeps receipts, and survives damaged data', () async {
      final store = VatRefundStore(appDir: () async => dir);
      expect(await store.load(), isEmpty);
      await store.save([_r('a', DateTime(2025, 3, 1), store: 'Zürich Shop', total: 9900)]);
      final back = (await store.load()).single;
      expect((back.id, back.store, back.totalCents, back.status), ('a', 'Zürich Shop', 9900, RefundStatus.toStamp));
      await store.save(const []);
      expect(await store.load(), isEmpty);
      SharedPreferences.setMockInitialValues({'vat_refund_receipts': '[{"id":"x","date":1700000000000,"status":"nonsense"},5,{"nodate":1}]'});
      final loaded = await VatRefundStore(appDir: () async => dir).load();
      expect(loaded.single.status, RefundStatus.toStamp);
      SharedPreferences.setMockInitialValues({'vat_refund_receipts': 'not json'});
      expect(await VatRefundStore(appDir: () async => dir).load(), isEmpty);
    });

    test('pictures are made smaller, refused when they are not pictures, and cleared', () async {
      final store = VatRefundStore(appDir: () async => dir);
      final big = img.Image(width: 3200, height: 2400);
      img.fill(big, color: img.ColorRgb8(200, 100, 50));
      final source = File(p.join(dir.path, 'big.png'))..writeAsBytesSync(img.encodePng(big));
      final saved = (await store.addPhoto(source.path))!;
      final out = img.decodeJpg(File(saved).readAsBytesSync())!;
      expect((out.width, out.height), (1600, 1200));
      final junk = File(p.join(dir.path, 'junk.png'))..writeAsBytesSync([1, 2, 3]);
      expect(await store.addPhoto(junk.path), isNull);
      await store.save([_r('a', DateTime(2025, 3, 1))]);
      await store.clear();
      expect(File(saved).existsSync(), isFalse);
      expect(await store.load(), isEmpty);
      await store.clear();
    });
  });

  group('page', () {
    late Directory dir;
    late _FakeStore store;
    late _Share share;
    final now = DateTime(2025, 3, 1);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('sv_vat_ui');
      store = _FakeStore(dir);
      share = _Share();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> settle(WidgetTester tester, {int rounds = 4}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.pump();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
      }
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, {double width = 400, Future<String?> Function(bool)? pick}) async {
      tester.view.physicalSize = Size(width * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await sl.reset();
      sl.registerSingleton<ShareService>(share);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: VatRefundPage(store: store, pickPhoto: pick ?? (_) async => null, now: () => now, workDir: () async => dir),
        ),
      );
      await settle(tester);
    }

    testWidgets('an empty page explains what to do', (tester) async {
      await open(tester);
      expect(find.textContaining('No receipts yet'), findsOneWidget);
      expect(find.byTooltip('Share the list as a spreadsheet'), findsNothing);
    });

    testWidgets('adds a receipt with an estimate and a picture, shows its deadline and moves it along', (tester) async {
      final photo = File(p.join(dir.path, 'receipt.png'));
      final pic = img.Image(width: 400, height: 300);
      img.fill(pic, color: img.ColorRgb8(10, 20, 30));
      photo.writeAsBytesSync(img.encodePng(pic));
      await open(tester, pick: (_) async => photo.path);

      await tester.tap(find.byKey(const ValueKey('add-receipt')));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Shop'), 'Galeria');
      await tester.tap(find.byKey(const ValueKey('country')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Germany').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Total paid, with VAT'), '249,90');
      await tester.tap(find.text('Estimate'));
      await tester.pump();
      expect(find.text('39.90'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-camera')));
      await settle(tester, rounds: 10);
      expect(find.byType(Image), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('save-receipt')));
      await tester.tap(find.byKey(const ValueKey('save-receipt')));
      await settle(tester);

      expect(find.text('Galeria'), findsOneWidget);
      expect(find.textContaining('121 days left to stamp'), findsOneWidget);
      expect(find.textContaining('249,90'), findsOneWidget);
      expect(find.text('VAT in EUR'), findsOneWidget);
      final saved = (await tester.runAsync(store.load))!.single;
      expect((saved.totalCents, saved.vatCents, saved.country, saved.currency), (24990, 3990, 'DE', 'EUR'));
      expect(File(saved.photoPath!).existsSync(), isTrue);

      await tester.tap(find.byKey(ValueKey('advance-${saved.id}')));
      await settle(tester);
      expect(find.text('Stamped at the border'), findsWidgets);
      expect(find.textContaining('days left to stamp'), findsNothing);
      expect(find.text('Stamped, refund on its way'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('advance-${saved.id}')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('advance-${saved.id}')));
      await settle(tester);
      expect(find.text('Refunded'), findsWidgets);
      expect(find.byKey(ValueKey('advance-${saved.id}')), findsNothing);
    });

    testWidgets('saving needs a total and a sensible VAT amount', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('add-receipt')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('save-receipt')));
      await tester.tap(find.byKey(const ValueKey('save-receipt')));
      await tester.pump();
      expect(find.textContaining('Enter the total you paid'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Total paid, with VAT'), '100');
      await tester.enterText(find.widgetWithText(TextField, 'VAT to refund (from the form)'), '150');
      await tester.tap(find.byKey(const ValueKey('save-receipt')));
      await tester.pump();
      expect(find.textContaining('cannot be more than the total'), findsOneWidget);
      await tester.tap(find.text('Estimate'));
      await tester.pump();
      expect(find.textContaining('choose the country first'), findsOneWidget);
    });

    testWidgets('colours the deadline and says when it has passed', (tester) async {
      await store.save([
        _r('late', DateTime(2024, 10, 1), store: 'Old shop'),
        _r('soon', DateTime(2024, 12, 5), store: 'Soon shop'),
        _r('fine', DateTime(2025, 2, 20), store: 'Fresh shop'),
      ]);
      await open(tester);
      expect(find.text('Deadline passed'), findsNWidgets(2), reason: 'one on the receipt and one in the summary');
      expect(find.textContaining('days left to stamp'), findsNWidgets(2));
      final lateText = tester.widget<Text>(find.byKey(const ValueKey('deadline-late')));
      expect(lateText.style!.color, AppColors.danger);
    });

    testWidgets('filters by where a receipt stands', (tester) async {
      await store.save([
        _r('a', DateTime(2025, 2, 1), store: 'Todo shop'),
        _r('b', DateTime(2025, 2, 2), store: 'Road shop', status: RefundStatus.sent),
        _r('c', DateTime(2025, 2, 3), store: 'Done shop', status: RefundStatus.refunded),
      ]);
      await open(tester);
      expect(find.text('Todo shop'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Needs stamp'));
      await tester.pump();
      expect((find.text('Todo shop').evaluate().length, find.text('Road shop').evaluate().length, find.text('Done shop').evaluate().length), (1, 0, 0));
      await tester.tap(find.widgetWithText(ChoiceChip, 'On its way'));
      await tester.pump();
      expect((find.text('Todo shop').evaluate().length, find.text('Road shop').evaluate().length), (0, 1));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Refunded'));
      await tester.pump();
      expect(find.text('Done shop'), findsOneWidget);
    });

    testWidgets('edits and deletes a receipt together with its picture', (tester) async {
      final photo = File(p.join(dir.path, 'kept.jpg'))..writeAsBytesSync([1]);
      await store.save([_r('a', DateTime(2025, 2, 1), store: 'Edit shop').copyWith(photoPath: photo.path)]);
      await open(tester);
      await tester.tap(find.text('Edit shop'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Shop'), 'Renamed shop');
      await tester.ensureVisible(find.byKey(const ValueKey('save-receipt')));
      await tester.tap(find.byKey(const ValueKey('save-receipt')));
      await settle(tester);
      expect(find.text('Renamed shop'), findsOneWidget);
      expect((await tester.runAsync(store.load))!.single.photoPath, photo.path);

      await tester.tap(find.text('Renamed shop'));
      await settle(tester);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await settle(tester);
      expect(find.textContaining('No receipts yet'), findsOneWidget);
      expect(photo.existsSync(), isFalse);
      expect((await tester.runAsync(store.load))!, isEmpty);
    });

    testWidgets('shares the list as a spreadsheet', (tester) async {
      await store.save([_r('a', DateTime(2025, 2, 1), store: 'CSV shop')]);
      await open(tester);
      await tester.tap(find.byTooltip('Share the list as a spreadsheet'));
      await settle(tester);
      expect(p.basename(share.path!), 'vat_refund_receipts.csv');
      expect(share.content, contains('CSV shop'));
    });

    for (final width in [320.0, 400.0, 900.0]) {
      testWidgets('fits at ${width.toInt()} px, with long names', (tester) async {
        await store.save([
          _r('a', DateTime(2025, 2, 1), store: 'A shop with a really very long name that goes on and on and on', total: 123456789, vat: 20576132),
          _r('b', DateTime(2024, 9, 1), status: RefundStatus.stamped, currency: 'SEK', country: 'SE'),
        ]);
        await open(tester, width: width);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('add-receipt')));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

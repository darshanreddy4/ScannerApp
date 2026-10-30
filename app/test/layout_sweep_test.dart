import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/cards/data/card_store.dart';
import 'package:doculoom/features/cards/domain/cards.dart';
import 'package:doculoom/features/cards/presentation/card_edit_page.dart';
import 'package:doculoom/features/checklists/data/checklist_store.dart';
import 'package:doculoom/features/checklists/domain/checklists.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:doculoom/features/office/convert/office_converter.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_page.dart';
import 'package:doculoom/app/app.dart';
import 'package:doculoom/app/di.dart';
import 'package:doculoom/app/router.dart';
import 'package:doculoom/core/i18n/tr.dart';
import 'package:doculoom/core/theme/app_icons.dart';
import 'package:doculoom/features/documents/data/datasources/document_local_data_source.dart';
import 'package:doculoom/features/documents/data/repositories/document_repository_impl.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/monetization/domain/repositories/monetization_contracts.dart';
import 'package:doculoom/features/ocr/data/text_repository_impl.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/qr/domain/share_sessions.dart';
import 'package:doculoom/features/qr/presentation/qr_share_page.dart';
import 'package:doculoom/features/scanner/domain/entities/filter_settings.dart';
import 'package:doculoom/features/markup/presentation/markup_page.dart';
import 'package:doculoom/features/scanner/presentation/bloc/scan_session_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/coins_fakes.dart';

const _sizes = <(double, double)>[(320, 568), (360, 640), (360, 800), (393, 852), (412, 915), (430, 932)];
// The app caps text at 1.3, so 2.0 behaves like 1.3.
const _scales = <double>[1.0, 1.3, 2.0];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('every screen fits every phone size and font scale', (tester) => sweep(tester, null));

  // The same screens written from right to left, which mirrors them.
  testWidgets('every screen fits every phone size and font scale in Arabic', (tester) => sweep(tester, 'ar'));

  // Russian and German have the longest words and phrases of the European languages.
  testWidgets('every screen fits every phone size and font scale in Russian', (tester) => sweep(tester, 'ru'));
  testWidgets('every screen fits every phone size and font scale in German', (tester) => sweep(tester, 'de'));
}

Future<void> sweep(WidgetTester tester, String? language) async {
  {
    // The test font is far wider than real text, so measure with Roboto, which Android phones use.
    final fonts = '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final f in ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(Future.value(File('$fonts/Roboto-$f.ttf').readAsBytesSync().buffer.asByteData()));
    }
    await roboto.load();
    SharedPreferences.setMockInitialValues({if (language != null) 'app_language': language});
    final root = Directory.systemTemp.createTempSync('sv_sweep');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => root.path);
    addTearDown(() => root.deleteSync(recursive: true));
    final local = DocumentLocalDataSource(rootDir: root);
    final repo = DocumentRepositoryImpl(local);

    NewPage page(int i) {
      final f = File(p.join(root.path, 'src$i.jpg'))..writeAsBytesSync(img.encodeJpg(img.Image(width: 300, height: 420)));
      return NewPage(imagePath: f.path, rawPath: f.path, width: 300, height: 420);
    }

    final folder = (await tester.runAsync(() => repo.createFolder('Tax documents and receipts for the financial year 2025-2026')))!.valueOrNull!;
    late ScannedDocument doc;
    await tester.runAsync(() async {
      doc = (await repo.saveDocument(
        title: 'Scan documents 20 Oct 2026 - Rent agreement for the flat at Koramangala',
        pages: [page(1), page(2), page(3)],
        folderId: folder.id,
      )).valueOrNull!;
      await repo.updateMeta(doc.id, favorite: true, tags: ['rent', 'a-very-long-tag-name', 'legal']);
      await repo.saveDocument(title: 'Receipt', pages: [page(4)]);
      await TextRepositoryImpl(local).saveText(doc.id, const [
        PageText(
          position: 0,
          script: OcrScript.latin,
          markdown:
              '# Annual Report\n\nThe area is \$A = 25\$ and grows with a very long unbroken word such as Supercalifragilisticexpialidocious_Supercalifragilisticexpialidocious.\n\n- first point\n- second point\n\n\$\$a^{2} + b^{2} = c^{2}\$\$',
          plain: 'Annual Report',
        ),
      ]);
    });
    final pdf = File(p.join(root.path, 'contract.pdf'))..writeAsStringSync('%PDF');
    final problems = <String>[];

    await sl.reset();
    configureDependencies();
    sl
      ..unregister<AdService>()
      ..registerSingleton<AdService>(ScriptedAds())
      ..unregister<DocumentLocalDataSource>()
      ..registerSingleton<DocumentLocalDataSource>(local);

    final original = FlutterError.onError;
    FlutterError.onError = (d) => problems.add(d.exceptionAsString().split('\n').first);

    Future<void> settle({bool load = false}) async {
      for (var i = 0; i < (load ? 6 : 3); i++) {
        if (load) await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 150));
      }
    }

    Future<void> visit(String name, String where, Future<void> Function() go) async {
      problems.clear();
      await go();
      await settle(load: true);
      final seen = problems.toSet().toList();
      tester.takeException();
      if (seen.isNotEmpty) report.add('$where | $name | ${seen.take(2).join(' || ')}');
    }

    try {
      for (final (w, h) in _sizes) {
        for (final scale in _scales) {
          tester.view.physicalSize = Size(w * 3, h * 3);
          tester.view.devicePixelRatio = 3;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          final where = '${w.toInt()}x${h.toInt()} @${scale}x';

          appRouter.go('/');
          await tester.pumpWidget(const DoculoomApp());
          await settle(load: true);

          await visit('Documents tab', where, () async {});
          await visit('Tools tab', where, () async {
            await tester.tap(find.byType(NavigationDestination).at(1));
          });
          await visit('Settings tab', where, () async {
            await tester.tap(find.byType(NavigationDestination).at(2));
          });
          await visit('Documents again + search', where, () async {
            await tester.tap(find.byType(NavigationDestination).at(0));
            await settle();
          });
          await visit('Actions sheet', where, () async {
            await tester.tap(find.byIcon(AppIcons.more).first);
            await settle();
            await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -2000));
            await settle();
          });
          appRouter.go('/');
          await tester.pumpWidget(const DoculoomApp());
          await visit('Folder', where, () async => appRouter.go('/folder/${folder.id}'));
          await visit('Document detail', where, () async => appRouter.go('/document/${doc.id}'));
          await visit('OCR start', where, () async => appRouter.go('/ocr', extra: doc));
          await visit('QR generator', where, () async => appRouter.go('/qr'));
          await visit('Payment QR', where, () async => appRouter.go('/qr-payment'));
          await visit('UPI payment QR', where, () async => appRouter.go('/qr-upi'));
          await visit('E-invoice viewer', where, () async => appRouter.go('/einvoice'));
          await visit('Invoice maker', where, () async => appRouter.go('/invoice'));
          await visit('CV maker', where, () async => appRouter.go('/cv'));
          await visit('VAT refund receipts', where, () async => appRouter.go('/vat-refund'));
          await visit('Sign with certificate', where, () async => appRouter.go('/pdf-certificate'));
          await visit('Amount in words', where, () async => appRouter.go('/amount-words'));
          await visit('Loyalty cards (empty)', where, () async => appRouter.go('/cards'));
          await visit('Add a card', where, () async => appRouter.go('/card-edit'));
          const sweepCard = LoyaltyCard(
            id: 'sweep',
            name: 'A shop with a rather long name for a loyalty card',
            number: '4006381333931',
            type: CardCodeType.ean13,
            note: 'Member since 2019',
          );
          await tester.runAsync(() => const CardStore().put(sweepCard));
          await visit('Loyalty cards', where, () async => appRouter.go('/cards'));
          await visit('Show a card', where, () async => appRouter.go('/card-view', extra: 'sweep'));
          await visit('Edit a card', where, () async => appRouter.go('/card-edit', extra: const CardEditArgs(card: sweepCard)));
          await tester.runAsync(const CardStore().clear);
          await visit('Checklists (empty)', where, () async => appRouter.go('/checklists'));
          const sweepList = Checklist(
            id: 'sweep-list',
            title: 'Moving to a new apartment across the city next month',
            templateId: 'move',
            items: [
              ChecklistItem(
                id: 0,
                text: 'Tell your bank and card providers the new address and update the address on your ID and licence',
                note: 'Branch visit on Monday',
              ),
              ChecklistItem(id: 1, text: 'Set up mail forwarding', done: true, docId: 'gone'),
            ],
          );
          await tester.runAsync(() => const ChecklistStore().put(sweepList));
          await visit('Checklists', where, () async => appRouter.go('/checklists'));
          await visit('One checklist', where, () async => appRouter.go('/checklist', extra: 'sweep-list'));
          await tester.runAsync(const ChecklistStore().clear);
          await visit('Application packet', where, () async => appRouter.go('/packet'));
          await visit('GST invoice', where, () async => appRouter.go('/gst-invoice'));
          await visit('US invoice', where, () async => appRouter.go('/us-invoice'));
          await visit('Saudi VAT invoice', where, () async => appRouter.go('/zatca-invoice'));
          await visit('Safe ID copy', where, () async => appRouter.go('/safe-id'));
          await visit('Hijri calendar', where, () async => appRouter.go('/hijri'));
          await visit('Reminder help', where, () async => appRouter.go('/reminder-help'));
          await visit(
            'QR share',
            where,
            () async => appRouter.go(
              '/qr-share',
              extra: QrShareArgs(filePath: pdf.path, fileName: 'contract.pdf', mimeType: 'application/pdf'),
            ),
          );
          // The share keeps running after its screen closes, so end it before the next screen.
          await tester.runAsync(sl<ShareSessions>().stopAll);
          await visit('Print', where, () async => appRouter.go('/print', extra: doc));
          await visit('Paywall', where, () async => appRouter.go('/paywall'));
          await visit('Privacy', where, () async => appRouter.go('/privacy'));
          await visit('Terms', where, () async => appRouter.go('/terms'));
          await visit('Support', where, () async => appRouter.go('/support'));
          await visit('Compress photos', where, () async => appRouter.go('/compress-photo'));
          await visit('Passport photo', where, () async => appRouter.go('/passport-photo'));
          await visit('Watermark', where, () async => appRouter.go('/watermark'));
          await visit('Remove photo data', where, () async => appRouter.go('/privacy-clean'));
          await visit('Compress PDF', where, () async => appRouter.go('/compress-pdf'));
          await visit('PDF pages', where, () async => appRouter.go('/pdf-pages'));
          await visit('PDF password', where, () async => appRouter.go('/pdf-password'));
          await visit('ID card', where, () async => appRouter.go('/id-card'));
          await visit('Signature', where, () async => appRouter.go('/signature'));
          await visit('Signature draw', where, () async => appRouter.go('/signature-draw'));
          await visit('Signature photo', where, () async => appRouter.go('/signature-photo'));
          await visit('Sign document', where, () async => appRouter.go('/sign-document'));
          await visit('Office sheets hub', where, () async => appRouter.go('/office-sheets'));
          await visit('Office slides hub', where, () async => appRouter.go('/office-slides'));
          await visit('Convert Excel to PDF', where, () async => appRouter.go('/office-convert', extra: OfficeConversion.xlsxToPdf));
          await visit('Convert images to PowerPoint', where, () async => appRouter.go('/office-convert', extra: OfficeConversion.imagesToPptx));
          await visit('New spreadsheet', where, () async => appRouter.go('/sheet', extra: const SheetArgs()));
          await visit('New presentation', where, () async => appRouter.go('/slides'));

          appRouter.go('/');
          await settle();
          final session = tester.element(find.byType(Scaffold).first).read<ScanSessionCubit>();
          session.start(defaultFilter: ScanFilter.values.first);
          await tester.runAsync(() => session.beginDraft(page(9).imagePath));
          await visit('Crop', where, () async => appRouter.go('/scan/crop'));
          await visit('Markup', where, () async => appRouter.go('/scan/markup', extra: const MarkupArgs(width: 600, height: 800)));
          await tester.runAsync(session.commitDraft);
          await tester.runAsync(() => session.beginDraft(page(8).imagePath));
          await tester.runAsync(session.commitDraft);
          await visit('Edit pages', where, () async => appRouter.go('/scan/edit'));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
          await tester.pump(const Duration(milliseconds: 300));
          tester.takeException();
        }
      }
    } finally {
      tester.platformDispatcher.clearAllTestValues();
      FlutterError.onError = original;
      Strings.code = 'en';
    }
    tester.platformDispatcher.clearAllTestValues();
    FlutterError.onError = original;
    // ignore: avoid_print
    print('SWEEP REPORT ($language ${report.length})\n${report.join('\n')}');
    expect(report, isEmpty);
  }
}

final report = <String>[];

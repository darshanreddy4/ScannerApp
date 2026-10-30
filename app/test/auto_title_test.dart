import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/scanner/domain/auto_title.dart';
import 'package:doculoom/features/scanner/domain/entities/scan_mode.dart';
import 'package:doculoom/features/scanner/domain/smart_folders.dart';

/// A page 1000 x 1400 with lines given as (text, top, height); lines start at the left.
OcrPageResult page(List<(String, double, double)> lines, {double width = 1000, double height = 1400, double left = 100}) => OcrPageResult(
  width: width,
  height: height,
  blocks: [
    OcrBlock(
      lines: [for (final (t, top, h) in lines) OcrLine(text: t, left: left, top: top, right: left + t.length * h * 0.5, bottom: top + h)],
    ),
  ],
);

void main() {
  group('default names', () {
    test('only the names the app made are replaced', () {
      expect(isDefaultScanTitle('Scan 2026-10-25 14.07'), isTrue);
      expect(isDefaultScanTitle('Receipt 2026-10-25 14.07'), isTrue);
      expect(isDefaultScanTitle('Whiteboard 2026-01-02 09.05'), isTrue);
      expect(isDefaultScanTitle('Rent agreement'), isFalse);
      expect(isDefaultScanTitle('Scan 2026-10-25 14.07 copy'), isFalse);
      expect(isDefaultScanTitle('IMG_20261025_140700'), isFalse);
      expect(isDefaultScanTitle(''), isFalse);
    });

    test('every mode makes a name that counts as default', () {
      for (final m in ScanMode.values) {
        expect(isDefaultScanTitle(m.title(DateTime(2026, 3, 4, 5, 6))), isTrue, reason: m.name);
      }
    });
  });

  group('heading of a page', () {
    test('the biggest line near the top is the name', () {
      final t = suggestTitle(
        page([('Acme Corp', 80, 30), ('Rental Agreement', 140, 64), ('This agreement is made between the parties', 260, 28), ('Landlord and tenant', 300, 28)]),
      );
      expect(t, 'Rental Agreement');
    });

    test('with no bigger line, the first line is the name', () {
      final t = suggestTitle(page([('Meeting notes', 80, 30), ('Agenda for Monday', 140, 30), ('Budget review', 200, 30)]));
      expect(t, 'Meeting notes');
    });

    test('a heading on two lines is joined', () {
      final t = suggestTitle(
        page([('ANNUAL REPORT', 100, 70), ('AND ACCOUNTS 2025', 180, 68), ('Prepared by the finance team for the board', 400, 28), ('Confidential', 440, 28)]),
      );
      expect(t, 'Annual Report and Accounts 2025');
    });

    test('lines that are only numbers, dates, emails, web addresses or page numbers are not names', () {
      final t = suggestTitle(
        page([
          ('12/03/2025', 60, 60),
          ('Page 1 of 3', 100, 60),
          ('info@acme.com', 140, 60),
          ('www.acme.com', 180, 60),
          ('+91 98765 43210', 220, 60),
          ('Electricity Bill', 280, 40),
          ('Account no 123456', 340, 28),
        ]),
      );
      expect(t, 'Electricity Bill');
    });

    test('a page of only numbers and a blank page have no name', () {
      expect(suggestTitle(page([('1234 5678 9012', 100, 40), ('42', 160, 40)])), isNull);
      expect(suggestTitle(const OcrPageResult(width: 1000, height: 1400, blocks: [])), isNull);
      expect(suggestTitle(page([('   ', 100, 40)])), isNull);
    });

    test('text that is only far down the page is not a heading', () {
      expect(suggestTitle(page([('A line in the lower half of the page', 1000, 40)])), isNull);
    });

    test('SHOUTING headings become title case, short acronyms stay', () {
      expect(suggestTitle(page([('TERMS OF SERVICE', 100, 60), ('some small print follows here', 300, 24)])), 'Terms of Service');
      expect(suggestTitle(page([('ID CARD COPY', 100, 60), ('some small print follows here', 300, 24)])), 'ID Card Copy');
    });

    test('decoration around a heading is dropped and long ones are cut at a word', () {
      expect(suggestTitle(page([('--- Invoice ---', 100, 60), ('rows of the table follow', 300, 24)])), 'Invoice');
      final long = suggestTitle(page([('Quarterly statement of the regional operations committee meeting', 100, 60), ('rows of the table follow', 300, 24)]))!;
      expect(long.length, lessThanOrEqualTo(50));
      expect(long.endsWith(' '), isFalse);
      expect('Quarterly statement of the regional operations committee meeting', startsWith(long));
    });

    test('accented and non-Latin headings are kept', () {
      expect(suggestTitle(page([('Résumé de réunion', 100, 60), ('texte', 300, 24)])), 'Résumé de réunion');
      expect(suggestTitle(page([('किराया समझौता', 100, 60), ('पाठ', 300, 24)])), 'किराया समझौता');
    });

    test('a page whose lines have no size is ignored instead of failing', () {
      final flat = OcrPageResult(
        width: 1000,
        height: 1400,
        blocks: [
          OcrBlock(lines: [const OcrLine(text: 'Heading', left: 0, top: 0, right: 10, bottom: 0)]),
        ],
      );
      expect(suggestTitle(flat), isNull);
    });
  });

  group('date as a name', () {
    test('a date in the text gives a short name', () {
      expect(suggestTitleFromDate('Paid on 12 March 2026 at the counter', now: DateTime(2026, 10, 25)), 'Scan 12 Mar 2026');
      expect(suggestTitleFromDate('2026-01-09', now: DateTime(2026, 10, 25)), 'Scan 9 Jan 2026');
    });

    test('no date, or a date that cannot be right, gives nothing', () {
      expect(suggestTitleFromDate('no numbers here'), isNull);
      expect(suggestTitleFromDate('31/02/2026', now: DateTime(2026, 10, 25)), isNull);
    });
  });

  group('folders for kinds of scan', () {
    test('each special kind has its own folder and plain documents have none', () {
      expect(smartFolderFor(ScanMode.document), isNull);
      expect(smartFolderFor(ScanMode.receipt)!.name, 'Receipts');
      expect(smartFolderFor(ScanMode.id)!.name, 'IDs');
      expect(smartFolderFor(ScanMode.card)!.name, 'Business cards');
      expect(smartFolderFor(ScanMode.book)!.name, 'Books');
      expect(smartFolderFor(ScanMode.whiteboard)!.name, 'Whiteboards');
      expect(smartFolderFor(ScanMode.table)!.name, 'Tables');
      final names = [for (final m in ScanMode.values) smartFolderFor(m)?.name].whereType<String>();
      expect(names.toSet().length, names.length);
    });
  });
}

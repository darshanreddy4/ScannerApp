import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:scanvault/core/error/failures.dart';
import 'package:scanvault/core/error/result.dart';
import 'package:scanvault/features/importer/domain/importer.dart';
import 'package:scanvault/features/office/convert/office_converter.dart';
import 'package:scanvault/features/office/sheets/data/xlsx_reader.dart';
import 'package:scanvault/features/office/slides/data/deck_editor.dart';
import 'package:scanvault/features/office/slides/data/pptx_package.dart';
import 'package:scanvault/features/office/slides/data/slide_export.dart';
import 'package:scanvault/features/office/sheets/domain/sheet_model.dart';

class _Importer implements DocumentImporter {
  _Importer(this.pages);
  final List<String> pages;

  @override
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress}) async =>
      Ok(ImportedDocument(title: 'x', imagePaths: pages));
}

String fixture(String name) => File('test/fixtures/office/$name').absolute.path;

int pageCount(File f) => RegExp(r'/Type\s*/Page(?![a-z])').allMatches(String.fromCharCodes(f.readAsBytesSync())).length;

void main() {
  late Directory work;
  late OfficeConverter converter;
  late String photo;

  setUp(() {
    work = Directory.systemTemp.createTempSync('office_conv');
    final image = img.Image(width: 64, height: 48)..clear(img.ColorRgb8(200, 40, 40));
    photo = p.join(work.path, 'photo.png');
    File(photo).writeAsBytesSync(img.encodePng(image));
    converter = OfficeConverter(
      workDir: () async => work,
      slideConversions: SlideConverter(importer: _Importer([photo, photo])).convert,
    );
  });

  tearDown(() => work.deleteSync(recursive: true));

  testWidgets('Excel to PDF and Excel to CSV', (tester) async {
    await tester.runAsync(() async {
      final pdf = (await converter.convert(OfficeConversion.xlsxToPdf, [fixture('basic.xlsx')])).single;
      expect(pdf.name, 'basic.pdf');
      expect(pageCount(File(pdf.path)), 2, reason: 'one page for each visible sheet');

      final csvs = await converter.convert(OfficeConversion.xlsxToCsv, [fixture('basic.xlsx')]);
      expect(csvs.map((c) => c.name), ['basic_Sales.csv', 'basic_Notes.csv']);
      expect(File(csvs.first.path).readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF], reason: 'a byte-order mark so Excel reads accents correctly');
      final sales = File(csvs.first.path).readAsStringSync();
      expect(sales, contains('Item,Qty,Price,Total,Date,TRUE\r\n'));
      expect(sales, contains('Apple,3,1.50,4.5,2024-03-02,#DIV/0!'), reason: 'formulas without stored results are calculated');
      expect(sales, contains('Sum,,,'));
      expect(File(csvs.last.path).readAsStringSync(), contains('"line1\nline2 & <tag>"'));
    });
  });

  testWidgets('CSV to Excel gives a workbook that opens again', (tester) async {
    await tester.runAsync(() async {
      final csv = File(p.join(work.path, 'data.csv'))..writeAsStringSync('a;b\n1;2,5\nx;2024-01-31\n');
      final result = (await converter.convert(OfficeConversion.csvToXlsx, [csv.path])).single;
      expect(result.openAs, 'sheet');
      final wb = readXlsx(File(result.path).readAsBytesSync());
      expect((wb.sheets.first.cellAt(1, 0).value as NumberValue).number, 1);
      expect((wb.sheets.first.cellAt(2, 1).value as NumberValue).number, 45322);
    });
  });

  testWidgets('PowerPoint to PDF and to pictures', (tester) async {
    await tester.runAsync(() async {
      final pdf = (await converter.convert(OfficeConversion.pptxToPdf, [fixture('deck.pptx')])).single;
      expect(pageCount(File(pdf.path)), 3);
      final images = await converter.convert(OfficeConversion.pptxToImages, [fixture('deck.pptx')]);
      expect(images.map((i) => i.name), ['deck_slide_1.jpg', 'deck_slide_2.jpg', 'deck_slide_3.jpg']);
      final decoded = img.decodeJpg(File(images.first.path).readAsBytesSync())!;
      expect(decoded.width, 1600);
      expect(decoded.height, closeTo(900, 2));
    });
  });

  testWidgets('pictures and PDF pages to PowerPoint', (tester) async {
    await tester.runAsync(() async {
      final fromPictures = (await converter.convert(OfficeConversion.imagesToPptx, [photo, photo, photo])).single;
      expect(fromPictures.openAs, 'slides');
      final deck = await PptxDeck.open(File(fromPictures.path).readAsBytesSync());
      expect(deck.slides, hasLength(3));
      final editor = DeckEditor(deck);
      final shapes = editor.view(deck.slides.first).shapes;
      expect(shapes, hasLength(1));
      expect(shapes.single.media, isNotNull);
      expect(shapes.single.frame.w / shapes.single.frame.h, closeTo(64 / 48, 0.01));

      final fromPdf = (await converter.convert(OfficeConversion.pdfToPptx, [fixture('basic.xlsx')])).single;
      expect((await PptxDeck.open(File(fromPdf.path).readAsBytesSync())).slides, hasLength(2));
    });
  });

  testWidgets('bad input gives a clear failure', (tester) async {
    await tester.runAsync(() async {
      final bad = File(p.join(work.path, 'bad.xlsx'))..writeAsBytesSync([1, 2, 3]);
      await expectLater(converter.convert(OfficeConversion.xlsxToPdf, [bad.path]), throwsA(isA<ImportFailure>()));
      final badPptx = File(p.join(work.path, 'bad.pptx'))..writeAsBytesSync([1, 2, 3]);
      await expectLater(converter.convert(OfficeConversion.pptxToPdf, [badPptx.path]), throwsA(isA<ImportFailure>()));
      await expectLater(converter.convert(OfficeConversion.xlsxToPdf, const []), throwsA(isA<ImportFailure>()));
    });
  });
}

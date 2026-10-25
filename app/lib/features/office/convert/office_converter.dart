import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../sheets/data/csv.dart';
import '../sheets/data/sheet_renderer.dart';
import '../sheets/data/xlsx_reader.dart';
import '../sheets/data/xlsx_writer.dart';
import '../sheets/domain/formula.dart';
import '../sheets/domain/sheet_model.dart';

/// A file a conversion produced.
class ConvertedFile {
  const ConvertedFile({required this.path, required this.name, required this.mimeType, this.openAs});
  final String path;
  final String name;
  final String mimeType;

  /// "sheet" or "slides" when the result can be opened in the matching editor.
  final String? openAs;
}

enum OfficeConversion {
  xlsxToPdf(
    title: 'Excel to PDF',
    description: 'Turn every sheet of an Excel workbook into pages of a PDF.',
    extensions: ['xlsx'],
    pickLabel: 'Choose an Excel file',
  ),
  xlsxToCsv(
    title: 'Excel to CSV',
    description: 'Save each sheet of an Excel workbook as a CSV text file that any app can read.',
    extensions: ['xlsx'],
    pickLabel: 'Choose an Excel file',
  ),
  csvToXlsx(
    title: 'CSV to Excel',
    description: 'Turn a CSV file into an Excel workbook, with numbers and dates recognised.',
    extensions: ['csv', 'tsv', 'txt'],
    pickLabel: 'Choose a CSV file',
  ),
  pptxToPdf(
    title: 'PowerPoint to PDF',
    description: 'Turn every slide of a presentation into a page of a PDF.',
    extensions: ['pptx'],
    pickLabel: 'Choose a PowerPoint file',
  ),
  pptxToImages(title: 'PowerPoint to images', description: 'Save every slide as a JPG picture.', extensions: ['pptx'], pickLabel: 'Choose a PowerPoint file'),
  imagesToPptx(
    title: 'Images to PowerPoint',
    description: 'Put photos or scans on slides, one per slide, in a new presentation.',
    extensions: ['jpg', 'jpeg', 'png'],
    pickLabel: 'Choose pictures',
    multiple: true,
  ),
  pdfToPptx(
    title: 'PDF to PowerPoint',
    description: 'Turn every page of a PDF into a slide. Pages become pictures, so the text is not editable.',
    extensions: ['pdf'],
    pickLabel: 'Choose a PDF',
  );

  const OfficeConversion({required this.title, required this.description, required this.extensions, required this.pickLabel, this.multiple = false});
  final String title;
  final String description;
  final List<String> extensions;
  final String pickLabel;
  final bool multiple;

  bool get isSlides => index >= OfficeConversion.pptxToPdf.index;
}

const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Runs the Office conversions. Everything happens on the device.
class OfficeConverter {
  OfficeConverter({required Future<Directory> Function() workDir, this.slideConversions}) : _workDir = workDir;

  final Future<Directory> Function() _workDir;

  /// Handles the slide conversions; set once the slide module is registered.
  final Future<List<ConvertedFile>> Function(OfficeConversion kind, List<String> inputs, Directory out, void Function(String progress) onProgress)?
  slideConversions;

  Future<Directory> _outDir() async =>
      Directory(p.join((await _workDir()).path, 'office_out', '${DateTime.now().microsecondsSinceEpoch}')).create(recursive: true);

  Future<List<ConvertedFile>> convert(OfficeConversion kind, List<String> inputs, {void Function(String progress)? onProgress}) async {
    if (inputs.isEmpty) throw const ImportFailure('Choose a file first.');
    final out = await _outDir();
    void progress(String s) => onProgress?.call(s);
    try {
      switch (kind) {
        case OfficeConversion.xlsxToPdf:
          final wb = await _readWorkbook(inputs.first);
          final target = p.join(out.path, '${p.basenameWithoutExtension(inputs.first)}.pdf');
          final sheets = wb.visibleSheets;
          await SheetRenderer(
            workbook: wb,
          ).exportPdf(sheets, workDir: Directory(p.join(out.path, 'pages')), outputPath: target, onProgress: (d, t) => progress('Drawing page $d of $t'));
          return [ConvertedFile(path: target, name: p.basename(target), mimeType: 'application/pdf')];
        case OfficeConversion.xlsxToCsv:
          final wb = await _readWorkbook(inputs.first);
          final base = p.basenameWithoutExtension(inputs.first);
          final files = <ConvertedFile>[];
          for (final s in wb.visibleSheets) {
            final safe = s.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
            final name = wb.visibleSheets.length == 1 ? '$base.csv' : '${base}_$safe.csv';
            final path = p.join(out.path, name);
            await File(path).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(sheetToCsv(s, wb.styles, date1904: wb.date1904))], flush: true);
            files.add(ConvertedFile(path: path, name: name, mimeType: 'text/csv'));
          }
          return files;
        case OfficeConversion.csvToXlsx:
          final bytes = await File(inputs.first).readAsBytes();
          final data = await Isolate.run(() => writeXlsx(workbookFromCsv(parseCsv(decodeCsvBytes(bytes)))));
          final name = '${p.basenameWithoutExtension(inputs.first)}.xlsx';
          final path = p.join(out.path, name);
          await File(path).writeAsBytes(data, flush: true);
          return [ConvertedFile(path: path, name: name, mimeType: _xlsxMime, openAs: 'sheet')];
        default:
          final handler = slideConversions;
          if (handler == null) throw const ExportFailure('This conversion is not available.');
          return await handler(kind, inputs, out, progress);
      }
    } on Failure {
      rethrow;
    } on XlsxFormatException catch (e) {
      throw ImportFailure(e.message);
    } on SheetTooLargeException catch (e) {
      throw ExportFailure('This workbook would make ${e.pages} pages, which is too many for one PDF. Try Excel to CSV instead.');
    } catch (e) {
      throw ExportFailure('The conversion did not work. The file may be damaged or in an unsupported format.', cause: e);
    }
  }

  Future<Workbook> _readWorkbook(String path) async {
    final bytes = await File(path).readAsBytes();
    final wb = await Isolate.run(() => readXlsx(bytes));
    calculateMissingResults(wb);
    return wb;
  }
}

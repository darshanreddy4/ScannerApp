import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../tables/domain/table_reader.dart';
import '../data/expense_export.dart';
import '../domain/expense_summary.dart';
import '../domain/receipt_reader.dart';
import '../domain/receipt_record.dart';

enum ExpensesStatus { idle, reading, ready }

/// One bill to read: a name to show, and the pictures of its pages.
typedef BillSource = ({String label, List<String> pages});

class ExpensesState extends Equatable {
  const ExpensesState({
    this.status = ExpensesStatus.idle,
    this.records = const [],
    this.done = 0,
    this.total = 0,
    this.label = '',
    this.notes = const [],
    this.failure,
    this.defaultCurrency = '',
  });

  final ExpensesStatus status;
  final List<ReceiptRecord> records;
  final int done;
  final int total;
  final String label;

  /// Things that went wrong with single files, shown under the list.
  final List<String> notes;
  final Failure? failure;

  /// The currency taken for bills that do not print one.
  final String defaultCurrency;

  bool get reading => status == ExpensesStatus.reading;
  bool get hasRecords => records.isNotEmpty;
  ExpenseSummary get summary => summarize(records);
  Set<String> get duplicates => duplicateIds(records);

  ExpensesState copyWith({
    ExpensesStatus? status,
    List<ReceiptRecord>? records,
    int? done,
    int? total,
    String? label,
    List<String>? notes,
    Object? failure = _keep,
    String? defaultCurrency,
  }) => ExpensesState(
    status: status ?? this.status,
    records: records ?? this.records,
    done: done ?? this.done,
    total: total ?? this.total,
    label: label ?? this.label,
    notes: notes ?? this.notes,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [status, records, done, total, label, notes, failure, defaultCurrency];
}

/// Reads many bills with the on-device text reader, turns each into a row (shop, date, subtotal, tax, total), lets the rows be corrected,
/// adds them up by month and by kind of spending, and writes Excel and CSV files.
class ExpensesCubit extends Cubit<ExpensesState> {
  ExpensesCubit({
    required OcrEngine engine,
    required Future<Directory> Function() outputDir,
    OcrScript script = OcrScript.latin,
    String defaultCurrency = '',
    PdfPicturePages Function()? pdfPages,
    this.maxPdfPages = 60,
    DateTime Function() now = DateTime.now,
  }) : _engine = engine,
       _outputDir = outputDir,
       _script = script,
       _pdfPages = pdfPages ?? PdfxPicturePages.new,
       _now = now,
       super(ExpensesState(defaultCurrency: defaultCurrency));

  final OcrEngine _engine;
  final Future<Directory> Function() _outputDir;
  final PdfPicturePages Function() _pdfPages;
  final DateTime Function() _now;
  final OcrScript _script;

  /// Longer PDFs are read up to this many pages.
  final int maxPdfPages;
  var _cancelled = false;
  var _counter = 0;

  static const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic'];

  /// Reads pictures (one bill each) and PDFs (one bill for each page) and adds the bills to the list.
  Future<void> addFiles(List<String> paths) async {
    if (state.reading || paths.isEmpty) return;
    await _run(total: paths.length, (notes, add, progress) async {
      for (var i = 0; i < paths.length; i++) {
        if (_cancelled || isClosed) break;
        final path = paths[i];
        final name = p.basename(path);
        final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
        progress(i, name);
        try {
          if (imageExtensions.contains(ext)) {
            await _readBill(name, [path], notes, add);
          } else if (ext == 'pdf') {
            await _readPdf(path, name, i, notes, add, progress);
          } else {
            notes.add('"$name" is not a picture or a PDF, so it was skipped.');
          }
        } catch (_) {
          notes.add('Could not open "$name". It may be damaged or protected.');
        }
      }
    });
  }

  /// Reads saved scans: all pages of a scan are one bill.
  Future<void> addScans(List<BillSource> sources) async {
    if (state.reading || sources.isEmpty) return;
    await _run(total: sources.length, (notes, add, progress) async {
      for (var i = 0; i < sources.length; i++) {
        if (_cancelled || isClosed) break;
        progress(i, sources[i].label);
        try {
          await _readBill(sources[i].label, sources[i].pages, notes, add);
        } catch (_) {
          notes.add('Could not open "${sources[i].label}".');
        }
      }
    });
  }

  Future<void> _run(
    Future<void> Function(List<String> notes, void Function(ReceiptRecord) add, void Function(int, String) progress) body, {
    required int total,
  }) async {
    _cancelled = false;
    emit(state.copyWith(status: ExpensesStatus.reading, done: 0, total: total, label: '', notes: const [], failure: null));
    final notes = <String>[];
    final fresh = <ReceiptRecord>[];
    await body(notes, fresh.add, (done, label) {
      if (!isClosed) emit(state.copyWith(done: done, label: label));
    });
    if (isClosed) return;
    if (_cancelled) notes.add('Stopped. The bills read so far are kept.');
    emit(
      state.copyWith(
        status: ExpensesStatus.ready,
        records: [...state.records, ...fresh],
        done: total,
        label: '',
        notes: notes,
        failure: fresh.isEmpty && state.records.isEmpty
            ? const OcrFailure('No bill could be read. Try sharper pictures in good light, with the whole bill in the frame.')
            : null,
      ),
    );
  }

  Future<void> _readBill(String name, List<String> pages, List<String> notes, void Function(ReceiptRecord) add) async {
    final rows = <String>[];
    for (final page in pages) {
      final result = await _engine.recognize(page, _script);
      final read = result.valueOrNull;
      if (read == null) {
        notes.add('Could not read "$name": ${result.failureOrNull?.message ?? 'the text could not be read.'}');
        return;
      }
      rows.addAll(readRows(read));
    }
    final record = readReceipt(rows, id: 'b${_counter++}', source: name, now: _now(), defaultCurrency: state.defaultCurrency);
    if (record.total == null && record.vendor.isEmpty && record.date == null && record.items.isEmpty) {
      notes.add('No bill was found on "$name".');
      return;
    }
    add(record);
  }

  Future<void> _readPdf(String path, String name, int index, List<String> notes, void Function(ReceiptRecord) add, void Function(int, String) progress) async {
    final pages = _pdfPages();
    final work = await Directory(p.join((await _outputDir()).path, 'expenses', '${DateTime.now().microsecondsSinceEpoch}_$index')).create(recursive: true);
    try {
      final count = await pages.open(path);
      final use = count > maxPdfPages ? maxPdfPages : count;
      if (count > maxPdfPages) notes.add('"$name" has $count pages; the first $maxPdfPages were read.');
      for (var k = 0; k < use; k++) {
        if (_cancelled || isClosed) break;
        progress(index, '$name, page ${k + 1} of $use');
        final picture = File(p.join(work.path, 'p$k.jpg'));
        await picture.writeAsBytes(await pages.render(k, width: 1654, png: false), flush: true);
        await _readBill(use == 1 ? name : '$name, page ${k + 1}', [picture.path], notes, add);
        await picture.delete().then((_) {}, onError: (_) {});
      }
    } finally {
      await pages.close().then((_) {}, onError: (_) {});
      await work.delete(recursive: true).then((_) {}, onError: (_) {});
    }
  }

  void cancel() => _cancelled = true;

  /// The currency for bills that print none; bills already read without one take it too.
  void setDefaultCurrency(String code) {
    if (code == state.defaultCurrency) return;
    emit(
      state.copyWith(
        defaultCurrency: code,
        records: [for (final r in state.records) r.currency.isEmpty || r.currency == state.defaultCurrency ? r.copyWith(currency: code) : r],
      ),
    );
  }

  /// Puts a corrected bill in place of the one with the same id.
  void replace(ReceiptRecord record) {
    emit(state.copyWith(records: [for (final r in state.records) r.id == record.id ? record : r]));
  }

  void remove(String id) {
    final left = [
      for (final r in state.records)
        if (r.id != id) r,
    ];
    emit(state.copyWith(records: left, status: left.isEmpty ? ExpensesStatus.idle : state.status));
  }

  void clear() {
    if (state.reading) return;
    emit(ExpensesState(defaultCurrency: state.defaultCurrency));
  }

  void clearFailure() {
    if (state.failure != null) emit(state.copyWith(failure: null));
  }

  Future<String?> _write(String extension, List<int> Function() bytes) async {
    if (!state.hasRecords) return null;
    try {
      final dir = await Directory(p.join((await _outputDir()).path, 'expenses')).create(recursive: true);
      final d = _now();
      final day = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final file = File(p.join(dir.path, 'Expenses_${day}_${d.millisecondsSinceEpoch}.$extension'));
      await file.writeAsBytes(bytes(), flush: true);
      return file.path;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(failure: ExportFailure('The file could not be made.', cause: e)));
      return null;
    }
  }

  /// An Excel file with the bills, the months, the kinds of spending and the lines; null when there is nothing or it could not be written.
  Future<String?> writeXlsx() => _write('xlsx', () => expensesToXlsx(state.records));

  Future<String?> writeCsv() => _write('csv', () => expensesToCsv(state.records));
}

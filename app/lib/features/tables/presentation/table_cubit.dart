import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../data/table_export.dart';
import '../domain/table_reader.dart';

enum TableStatus { reading, ready, failed }

/// "A", "B", ... "Z", "AA" for a zero-based column.
String columnLabel(int index) {
  var n = index;
  var s = '';
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}

class TableState extends Equatable {
  const TableState({
    this.status = TableStatus.reading,
    this.rows = const [],
    this.spacing = TableSpacing.normal,
    this.edited = false,
    this.done = 0,
    this.total = 0,
    this.failure,
  });

  final TableStatus status;
  final List<List<String>> rows;
  final TableSpacing spacing;

  /// Cells were corrected or rows or columns were removed by hand.
  final bool edited;

  /// Pages read so far, out of [total].
  final int done;
  final int total;
  final Failure? failure;

  int get columnCount => rows.isEmpty ? 0 : rows.first.length;
  bool get hasTable => rows.isNotEmpty && columnCount > 0;

  TableState copyWith({TableStatus? status, List<List<String>>? rows, TableSpacing? spacing, bool? edited, int? done, int? total, Object? failure = _keep}) =>
      TableState(
        status: status ?? this.status,
        rows: rows ?? this.rows,
        spacing: spacing ?? this.spacing,
        edited: edited ?? this.edited,
        done: done ?? this.done,
        total: total ?? this.total,
        failure: identical(failure, _keep) ? this.failure : failure as Failure?,
      );

  static const _keep = Object();

  @override
  List<Object?> get props => [status, rows, spacing, edited, done, total, failure];
}

/// Reads the pages with the on-device text reader, rebuilds the table, lets it be corrected, and writes Excel and CSV files.
class TableCubit extends Cubit<TableState> {
  TableCubit({
    required OcrEngine engine,
    required List<String> images,
    required OcrScript script,
    required Future<Directory> Function() outputDir,
    required String title,
    DateTime Function() now = DateTime.now,
  }) : _engine = engine,
       _images = images,
       _script = script,
       _outputDir = outputDir,
       _title = title,
       _now = now,
       super(TableState(total: images.length));

  final OcrEngine _engine;
  final List<String> _images;
  final OcrScript _script;
  final Future<Directory> Function() _outputDir;
  final String _title;
  final DateTime Function() _now;
  final _pages = <OcrPageResult>[];

  Future<void> start() async {
    _pages.clear();
    emit(TableState(total: _images.length, spacing: state.spacing));
    if (_images.isEmpty) {
      emit(state.copyWith(status: TableStatus.failed, failure: const OcrFailure('There is no picture to read.')));
      return;
    }
    for (var i = 0; i < _images.length; i++) {
      final result = await _engine.recognize(_images[i], _script);
      if (isClosed) return;
      final page = result.valueOrNull;
      if (page == null) {
        emit(state.copyWith(status: TableStatus.failed, failure: result.failureOrNull));
        return;
      }
      _pages.add(page);
      emit(state.copyWith(done: i + 1));
    }
    _build(state.spacing);
  }

  void _build(TableSpacing spacing) {
    final table = joinTables([for (final page in _pages) readTable(page, spacing: spacing)]);
    emit(state.copyWith(status: TableStatus.ready, rows: table.rows, spacing: spacing, edited: false, failure: null));
  }

  /// Rebuilds the table with another column spacing. Corrections made by hand are lost.
  void setSpacing(TableSpacing spacing) {
    if (state.status != TableStatus.ready || spacing == state.spacing) return;
    _build(spacing);
  }

  void editCell(int row, int column, String text) {
    if (row < 0 || row >= state.rows.length || column < 0 || column >= state.columnCount) return;
    final rows = [
      for (final r in state.rows) [...r],
    ];
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (rows[row][column] == clean) return;
    rows[row][column] = clean;
    emit(state.copyWith(rows: rows, edited: true));
  }

  void deleteRow(int row) {
    if (row < 0 || row >= state.rows.length) return;
    final rows = [
      for (var i = 0; i < state.rows.length; i++)
        if (i != row) [...state.rows[i]],
    ];
    emit(state.copyWith(rows: rows, edited: true));
  }

  void deleteColumn(int column) {
    if (column < 0 || column >= state.columnCount) return;
    final rows = [
      for (final r in state.rows)
        [
          for (var c = 0; c < r.length; c++)
            if (c != column) r[c],
        ],
    ]..removeWhere((r) => r.isEmpty);
    emit(state.copyWith(rows: rows, edited: true));
  }

  String get _baseName {
    final cleaned = _title.replaceAll(RegExp(r'[^\p{L}\p{N}\- ]+', unicode: true), '').trim().replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'table' : cleaned;
  }

  Future<String?> _write(String extension, List<int> Function() bytes) async {
    if (!state.hasTable) return null;
    try {
      final dir = await Directory(p.join((await _outputDir()).path, 'tables')).create(recursive: true);
      final file = File(p.join(dir.path, '${_baseName}_${_now().millisecondsSinceEpoch}.$extension'));
      await file.writeAsBytes(bytes(), flush: true);
      return file.path;
    } catch (e) {
      if (!isClosed) emit(state.copyWith(failure: ExportFailure('The file could not be made.', cause: e)));
      return null;
    }
  }

  /// The table as an Excel file, or null when there is none or it could not be written.
  Future<String?> writeXlsx() => _write('xlsx', () => tableToXlsx(state.rows));

  Future<String?> writeCsv() => _write('csv', () => tableToCsv(state.rows));

  void clearFailure() {
    if (state.failure != null && state.status == TableStatus.ready) emit(state.copyWith(failure: null));
  }
}

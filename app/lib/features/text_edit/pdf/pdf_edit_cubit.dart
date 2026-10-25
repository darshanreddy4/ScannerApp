import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../pdf_tools/data/security/pdf_model.dart';
import '../../pdf_tools/data/security/pdf_security.dart';
import '../../reader/data/pdf_text_edit.dart';

/// What was changed so far, kept as a value so it can be put back by Undo.
class PdfEdits extends Equatable {
  const PdfEdits({this.lines = const {}, this.added = const []});

  /// New text of lines, by "page:line". Empty text means the line is removed.
  final Map<String, String> lines;
  final List<AddedText> added;

  static String keyOf(int page, int line) => '$page:$line';

  String? textOf(int page, int line) => lines[keyOf(page, line)];

  PdfEditPlan toPlan() => PdfEditPlan(
    edits: [for (final e in lines.entries) LineEdit(page: int.parse(e.key.split(':')[0]), line: int.parse(e.key.split(':')[1]), text: e.value)],
    additions: added,
  );

  bool get isEmpty => lines.isEmpty && added.isEmpty;

  @override
  List<Object?> get props => [lines, added.length, ...added.map((a) => '${a.page}${a.x}${a.y}${a.text}${a.sizePt}${a.rgb}${a.bold}${a.italic}${a.family}')];
}

class PdfEditState extends Equatable {
  const PdfEditState({
    this.loading = true,
    this.pages = const [],
    this.edits = const PdfEdits(),
    this.canUndo = false,
    this.canRedo = false,
    this.busy = false,
    this.modified = false,
    this.failure,
  });

  final bool loading;
  final List<PdfPageEditInfo> pages;
  final PdfEdits edits;
  final bool canUndo;
  final bool canRedo;
  final bool busy;
  final bool modified;
  final Failure? failure;

  PdfEditState copyWith({
    bool? loading,
    List<PdfPageEditInfo>? pages,
    PdfEdits? edits,
    bool? canUndo,
    bool? canRedo,
    bool? busy,
    bool? modified,
    Object? failure = _keep,
  }) => PdfEditState(
    loading: loading ?? this.loading,
    pages: pages ?? this.pages,
    edits: edits ?? this.edits,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    busy: busy ?? this.busy,
    modified: modified ?? this.modified,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [loading, pages.length, edits, canUndo, canRedo, busy, modified, failure];
}

const maxEditablePdfBytes = 60 * 1024 * 1024;

/// Holds an open PDF, the lines found in it and the changes made so far.
class PdfEditCubit extends Cubit<PdfEditState> {
  PdfEditCubit({required Future<Directory> Function() workDir}) : _workDir = workDir, super(const PdfEditState());

  final Future<Directory> Function() _workDir;
  Uint8List? _bytes;
  String _name = 'Document';
  final _undo = <PdfEdits>[];
  final _redo = <PdfEdits>[];

  String get name => _name;

  Future<void> open(String path) async {
    try {
      final file = File(path);
      if (await file.length() > maxEditablePdfBytes) {
        emit(state.copyWith(loading: false, failure: const ImportFailure('This PDF is too large to edit on a phone (over 60 MB).')));
        return;
      }
      _name = p.basenameWithoutExtension(path);
      final bytes = await file.readAsBytes();
      _bytes = bytes;
      final pages = await Isolate.run(() => analyzePdfForEditing(bytes));
      emit(state.copyWith(loading: false, pages: pages));
    } on WrongPasswordException {
      emit(
        state.copyWith(
          loading: false,
          failure: const ImportFailure('This PDF is password protected. Remove the password first with Tools > Lock or unlock PDF.'),
        ),
      );
    } on PdfFormatException {
      emit(state.copyWith(loading: false, failure: const ImportFailure('This file is not a readable PDF.')));
    } catch (e) {
      emit(state.copyWith(loading: false, failure: ImportFailure('This PDF could not be opened.', cause: e)));
    }
  }

  void _set(PdfEdits next) {
    if (next == state.edits) return;
    _undo.add(state.edits);
    if (_undo.length > 60) _undo.removeAt(0);
    _redo.clear();
    emit(state.copyWith(edits: next, canUndo: true, canRedo: false, modified: true, failure: null));
  }

  void clearFailure() {
    if (state.failure != null) emit(state.copyWith(failure: null));
  }

  /// Retypes a line. Returns a message when the text cannot be placed, otherwise null.
  String? editLine(int page, int line, String text) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final bad = unsupportedCharacters(clean);
    if (bad.isNotEmpty) return 'These characters cannot be used: $bad. Use Western letters, numbers and common symbols.';
    final original = state.pages[page].lines[line].text;
    final next = Map.of(state.edits.lines);
    final key = PdfEdits.keyOf(page, line);
    if (clean == original) {
      next.remove(key);
    } else {
      next[key] = clean;
    }
    _set(PdfEdits(lines: next, added: state.edits.added));
    return null;
  }

  void deleteLine(int page, int line) {
    final next = Map.of(state.edits.lines)..[PdfEdits.keyOf(page, line)] = '';
    _set(PdfEdits(lines: next, added: state.edits.added));
  }

  /// Puts a line back as it was in the file.
  void restoreLine(int page, int line) {
    final next = Map.of(state.edits.lines)..remove(PdfEdits.keyOf(page, line));
    _set(PdfEdits(lines: next, added: state.edits.added));
  }

  String? addText(AddedText text) {
    final bad = unsupportedCharacters(text.text);
    if (bad.isNotEmpty) return 'These characters cannot be used: $bad. Use Western letters, numbers and common symbols.';
    if (text.text.trim().isEmpty) return null;
    _set(PdfEdits(lines: state.edits.lines, added: [...state.edits.added, text]));
    return null;
  }

  String? replaceAdded(int index, AddedText text) {
    final bad = unsupportedCharacters(text.text);
    if (bad.isNotEmpty) return 'These characters cannot be used: $bad. Use Western letters, numbers and common symbols.';
    final next = [...state.edits.added];
    if (text.text.trim().isEmpty) {
      next.removeAt(index);
    } else {
      next[index] = text;
    }
    _set(PdfEdits(lines: state.edits.lines, added: next));
    return null;
  }

  void removeAdded(int index) {
    final next = [...state.edits.added]..removeAt(index);
    _set(PdfEdits(lines: state.edits.lines, added: next));
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(state.edits);
    final prev = _undo.removeLast();
    emit(state.copyWith(edits: prev, canUndo: _undo.isNotEmpty, canRedo: true, modified: true));
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(state.edits);
    final next = _redo.removeLast();
    emit(state.copyWith(edits: next, canUndo: true, canRedo: _redo.isNotEmpty, modified: true));
  }

  /// Writes the edited PDF to a temporary place and returns its path.
  Future<String?> export() async {
    final bytes = _bytes;
    if (bytes == null || state.busy) return null;
    emit(state.copyWith(busy: true, failure: null));
    try {
      final plan = state.edits.toPlan();
      final out = plan.isEmpty ? bytes : await Isolate.run(() => applyPdfEdits(bytes, plan));
      final dir = await Directory(p.join((await _workDir()).path, 'text_edit')).create(recursive: true);
      final path = p.join(dir.path, '${_name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}_edited.pdf');
      await File(path).writeAsBytes(out, flush: true);
      emit(state.copyWith(busy: false, modified: false));
      return path;
    } on PdfEditException catch (e) {
      emit(state.copyWith(busy: false, failure: ExportFailure(e.message)));
    } catch (e) {
      emit(state.copyWith(busy: false, failure: ExportFailure('The PDF could not be saved.', cause: e)));
    }
    return null;
  }
}

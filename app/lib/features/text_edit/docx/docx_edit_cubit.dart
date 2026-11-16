import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import 'docx_builder.dart';
import 'docx_document.dart';

class DocxEditState extends Equatable {
  const DocxEditState({
    this.loading = true,
    this.blocks = const [],
    this.version = 0,
    this.canUndo = false,
    this.canRedo = false,
    this.modified = false,
    this.busy = false,
    this.query = '',
    this.matchCase = false,
    this.matches = const [],
    this.current = -1,
    this.failure,
    this.notice,
  });

  final bool loading;
  final List<DocBlock> blocks;

  /// Changes with every edit, so the page redraws.
  final int version;
  final bool canUndo;
  final bool canRedo;
  final bool modified;
  final bool busy;
  final String query;
  final bool matchCase;
  final List<DocMatch> matches;
  final int current;
  final Failure? failure;
  final String? notice;

  DocxEditState copyWith({
    bool? loading,
    List<DocBlock>? blocks,
    int? version,
    bool? canUndo,
    bool? canRedo,
    bool? modified,
    bool? busy,
    String? query,
    bool? matchCase,
    List<DocMatch>? matches,
    int? current,
    Object? failure = _keep,
    Object? notice = _keep,
  }) => DocxEditState(
    loading: loading ?? this.loading,
    blocks: blocks ?? this.blocks,
    version: version ?? this.version,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
    modified: modified ?? this.modified,
    busy: busy ?? this.busy,
    query: query ?? this.query,
    matchCase: matchCase ?? this.matchCase,
    matches: matches ?? this.matches,
    current: current ?? this.current,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
    notice: identical(notice, _keep) ? this.notice : notice as String?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [loading, version, canUndo, canRedo, modified, busy, query, matchCase, matches.length, current, failure, notice];
}

const maxDocxBytes = 40 * 1024 * 1024;

/// Folder (inside the temporary one) that holds documents started from a template; they are saved under their own name.
const newDocsFolder = 'new_docs';

/// Holds an open Word file and the changes made to it.
class DocxEditCubit extends Cubit<DocxEditState> {
  DocxEditCubit({required Future<Directory> Function() workDir}) : _workDir = workDir, super(const DocxEditState());

  final Future<Directory> Function() _workDir;
  DocxDocument? _doc;
  String _name = 'Document';
  var _isNew = false;

  String get name => _name;

  /// The name the saved file gets: a new document keeps its name, an opened one is saved as a copy.
  String get fileName => '$_name${_isNew ? '' : '_edited'}.docx';
  DocxDocument get document => _doc!;

  Future<void> open(String path) async {
    try {
      final file = File(path);
      if (await file.length() > maxDocxBytes) {
        emit(state.copyWith(loading: false, failure: const ImportFailure('This file is too large to edit on a phone (over 40 MB).')));
        return;
      }
      _name = p.basenameWithoutExtension(path);
      _isNew = p.basename(p.dirname(path)) == newDocsFolder;
      _doc = DocxDocument.open(await file.readAsBytes());
      _publish(modified: false);
      emit(state.copyWith(loading: false));
    } on DocxFormatException catch (e) {
      emit(state.copyWith(loading: false, failure: ImportFailure(e.message)));
    } catch (e) {
      emit(state.copyWith(loading: false, failure: ImportFailure('This document could not be opened.', cause: e)));
    }
  }

  void _publish({bool? modified, int? current}) {
    final d = _doc!;
    final matches = state.query.isEmpty ? const <DocMatch>[] : d.findAll(state.query, matchCase: state.matchCase);
    emit(
      state.copyWith(
        blocks: d.view(),
        version: state.version + 1,
        canUndo: d.canUndo,
        canRedo: d.canRedo,
        modified: modified ?? true,
        matches: matches,
        current: matches.isEmpty ? -1 : (current ?? state.current).clamp(0, matches.length - 1),
        failure: null,
        notice: null,
      ),
    );
  }

  void clearMessages() {
    if (state.failure != null || state.notice != null) emit(state.copyWith(failure: null, notice: null));
  }

  void _run(void Function() op) {
    try {
      op();
      _publish();
    } catch (e) {
      emit(state.copyWith(failure: UnexpectedFailure('That change could not be made.', cause: e)));
    }
  }

  // ------------------------------------------------------------------ editing

  String paragraphText(int index) => _doc!.paragraphText(index);

  /// Makes the paragraph read [text]; does nothing when it already does.
  void commitText(int index, String text) {
    if (_doc!.paragraphText(index) == text) return;
    _run(() => _doc!.setParagraphText(index, text));
  }

  void format(int index, int start, int end, FormatChange change) => _run(() => _doc!.formatRange(index, start, end, change));
  void setAlign(int index, String align) => _run(() => _doc!.setAlign(index, align));
  void setStyle(int index, DocStyle style) => _run(() => _doc!.setStyle(index, style));
  void setList(int index, DocList kind) => _run(() => _doc!.setList(index, kind));
  DocStyle? styleOf(int index) => _doc!.styleOf(index);
  DocList listOf(int index) => _doc!.listKindOf(index);

  FormatState formatOf(int index, int start, int end) => _doc!.formatOf(index, start, end);

  /// Adds a paragraph after [index] and returns where it is.
  int addAfter(int index) {
    var created = index + 1;
    _run(() => created = _doc!.insertParagraphAfter(index));
    return created;
  }

  void delete(int index) => _run(() => _doc!.deleteParagraph(index));

  /// Adds a picture in its own paragraph after [index]; returns where it is.
  int addPicture(int index, Uint8List bytes, {required String extension, required int pixelWidth, required int pixelHeight}) {
    var created = index + 1;
    _run(() => created = _doc!.insertPictureAfter(index, bytes, extension: extension, pixelWidth: pixelWidth, pixelHeight: pixelHeight));
    return created;
  }

  ({String header, String footer, bool pageNumbers}) get headerFooter => _doc!.headerFooter();

  void setHeaderFooter({required String header, required String footer, required bool pageNumbers, String pageWord = 'Page', String ofWord = 'of'}) =>
      _run(() => _doc!.setHeaderFooter(header: header, footer: footer, pageNumbers: pageNumbers, pageWord: pageWord, ofWord: ofWord));

  void undo() {
    _doc!.undo();
    _publish();
  }

  void redo() {
    _doc!.redo();
    _publish();
  }

  // ------------------------------------------------------------------ find and replace

  void find(String query, {bool? matchCase}) {
    emit(state.copyWith(query: query, matchCase: matchCase ?? state.matchCase, current: 0));
    final matches = query.isEmpty ? const <DocMatch>[] : _doc!.findAll(query, matchCase: matchCase ?? state.matchCase);
    emit(state.copyWith(matches: matches, current: matches.isEmpty ? -1 : 0));
  }

  void step(int delta) {
    if (state.matches.isEmpty) return;
    final n = state.matches.length;
    emit(state.copyWith(current: ((state.current + delta) % n + n) % n));
  }

  void endFind() => emit(state.copyWith(query: '', matches: const [], current: -1));

  /// Replaces every match of the search text; returns how many were replaced.
  int replaceAll(String replacement) {
    var count = 0;
    try {
      count = _doc!.replaceAll(state.query, replacement, matchCase: state.matchCase);
      _publish(current: 0);
    } catch (e) {
      emit(state.copyWith(failure: UnexpectedFailure('The text could not be replaced.', cause: e)));
    }
    return count;
  }

  /// Replaces the match that is current, keeping the others.
  void replaceCurrent(String replacement) {
    if (state.current < 0 || state.current >= state.matches.length) return;
    final m = state.matches[state.current];
    final text = _doc!.paragraphText(m.paragraph);
    _run(() => _doc!.setParagraphText(m.paragraph, text.replaceRange(m.start, m.end, replacement)));
  }

  // ------------------------------------------------------------------ saving

  /// Writes the changed file to a temporary place and returns its path.
  Future<String?> export() async {
    if (_doc == null || state.busy) return null;
    emit(state.copyWith(busy: true, failure: null));
    try {
      final dir = await Directory(p.join((await _workDir()).path, 'text_edit')).create(recursive: true);
      final safe = _name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final out = p.join(dir.path, '$safe${_isNew ? '' : '_edited'}.docx');
      final Uint8List bytes = _doc!.save();
      await File(out).writeAsBytes(bytes, flush: true);
      emit(state.copyWith(busy: false, modified: false));
      return out;
    } catch (e) {
      emit(state.copyWith(busy: false, failure: ExportFailure('The file could not be saved.', cause: e)));
      return null;
    }
  }
}

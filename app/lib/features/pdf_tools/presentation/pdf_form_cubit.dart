import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/failures.dart';
import '../../text_edit/pdf/pdf_page_renderer.dart';
import '../domain/pdf_forms.dart';

/// What a tap on the page does.
enum FormTool { fields, text, date, tick, cross }

enum FormStatus { idle, loading, ready, saving, done }

class PdfFormState extends Equatable {
  const PdfFormState({
    this.path,
    this.info,
    this.values = const {},
    this.marks = const [],
    this.tool = FormTool.fields,
    this.flatten = false,
    this.status = FormStatus.idle,
    this.result,
    this.failure,
  });

  final String? path;
  final PdfFormInfo? info;

  /// Values typed or chosen, by field number. Fields not in here keep what the file has.
  final Map<int, String> values;
  final List<PdfMark> marks;
  final FormTool tool;
  final bool flatten;
  final FormStatus status;
  final FilledPdf? result;
  final Failure? failure;

  bool get busy => status == FormStatus.loading || status == FormStatus.saving;
  bool get hasChanges => values.isNotEmpty || marks.isNotEmpty || flatten;

  /// The value of one box of a field as it should be shown now.
  String valueOf(FormFieldInfo f) => values[f.id] ?? f.value;

  PdfFormState copyWith({
    Object? path = _keep,
    Object? info = _keep,
    Map<int, String>? values,
    List<PdfMark>? marks,
    FormTool? tool,
    bool? flatten,
    FormStatus? status,
    Object? result = _keep,
    Object? failure = _keep,
  }) => PdfFormState(
    path: identical(path, _keep) ? this.path : path as String?,
    info: identical(info, _keep) ? this.info : info as PdfFormInfo?,
    values: values ?? this.values,
    marks: marks ?? this.marks,
    tool: tool ?? this.tool,
    flatten: flatten ?? this.flatten,
    status: status ?? this.status,
    result: identical(result, _keep) ? this.result : result as FilledPdf?,
    failure: identical(failure, _keep) ? this.failure : failure as Failure?,
  );

  static const _keep = Object();

  @override
  List<Object?> get props => [path, info, values, marks, tool, flatten, status, result, failure];
}

String formDate(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

class PdfFormCubit extends Cubit<PdfFormState> {
  PdfFormCubit({
    required PdfFormService service,
    required Future<Directory> Function() outputDir,
    Future<PdfPageRenderer> Function(String path) openRenderer = PdfxPageRenderer.open,
    DateTime Function() now = DateTime.now,
    this.flattenOnly = false,
  }) : _service = service,
       _outputDir = outputDir,
       _openRenderer = openRenderer,
       _now = now,
       super(const PdfFormState());

  final PdfFormService _service;
  final Future<Directory> Function() _outputDir;
  final Future<PdfPageRenderer> Function(String path) _openRenderer;
  final DateTime Function() _now;

  /// Only makes notes and form boxes part of the pages; nothing can be typed.
  final bool flattenOnly;

  PdfPageRenderer? _renderer;
  final _pages = <int, Future<Uint8List>>{};

  DateTime get today => _now();

  Future<void> pick(String path) async {
    if (state.busy) return;
    await _closeRenderer();
    emit(PdfFormState(path: path, status: FormStatus.loading, flatten: flattenOnly));
    final result = await _service.inspect(path);
    if (isClosed) return;
    final info = result.valueOrNull;
    if (info == null) {
      emit(PdfFormState(failure: result.failureOrNull));
      return;
    }
    try {
      _renderer = await _openRenderer(path);
    } catch (e) {
      if (isClosed) return;
      emit(PdfFormState(failure: ExportFailure('This PDF could not be shown.', cause: e)));
      return;
    }
    if (isClosed) {
      await _closeRenderer();
      return;
    }
    emit(PdfFormState(path: path, info: info, flatten: flattenOnly, status: FormStatus.ready));
  }

  void clear() {
    if (state.busy) return;
    _closeRenderer();
    emit(const PdfFormState());
  }

  /// The picture of a page, drawn once.
  Future<Uint8List> page(int index) {
    final renderer = _renderer;
    if (renderer == null) return Future.error(StateError('No PDF is open'));
    return _pages.putIfAbsent(index, () => renderer.render(index, width: 1100));
  }

  void setTool(FormTool tool) {
    if (!flattenOnly && !state.busy) emit(state.copyWith(tool: tool));
  }

  void setFlatten(bool on) {
    if (!flattenOnly && !state.busy) emit(state.copyWith(flatten: on, result: null));
  }

  void setValue(FormFieldInfo field, String value) {
    if (state.busy || flattenOnly) return;
    emit(state.copyWith(values: {...state.values, field.id: value}, status: FormStatus.ready, result: null, failure: null));
  }

  /// A check box flips; a radio button picks its own value.
  void tapField(FormFieldInfo f) {
    if (f.kind == FormFieldKind.checkbox) {
      setValue(f, state.valueOf(f) == 'on' ? 'off' : 'on');
    } else if (f.kind == FormFieldKind.radio && f.option != null) {
      setValue(f, f.option!);
    }
  }

  void addMark(int page, double u, double v, MarkKind kind, {String text = ''}) {
    final info = state.info;
    if (state.busy || flattenOnly || info == null || page < 0 || page >= info.pages.length) return;
    final width = info.pages[page].widthPt;
    final size = kind == MarkKind.text ? width * 0.022 : width * 0.032;
    emit(
      state.copyWith(
        marks: [
          ...state.marks,
          PdfMark(page: page, u: u.clamp(0.0, 1.0), v: v.clamp(0.0, 1.0), kind: kind, text: text, sizePt: size),
        ],
        status: FormStatus.ready,
        result: null,
        failure: null,
      ),
    );
  }

  void removeMark(PdfMark mark) {
    if (state.busy) return;
    emit(state.copyWith(marks: [...state.marks]..remove(mark), result: null));
  }

  void undoMark() {
    if (state.busy || state.marks.isEmpty) return;
    emit(state.copyWith(marks: [...state.marks]..removeLast(), result: null));
  }

  Future<void> save() async {
    final path = state.path;
    if (path == null || state.busy || state.info == null) return;
    if (!state.hasChanges) {
      emit(state.copyWith(failure: const ExportFailure('Nothing has been changed yet. Fill a box, add a mark or choose to flatten.')));
      return;
    }
    emit(state.copyWith(status: FormStatus.saving, result: null, failure: null));
    final dir = await Directory(p.join((await _outputDir()).path, 'pdf_forms')).create(recursive: true);
    final name = '${p.basenameWithoutExtension(path)}_${flattenOnly ? 'flattened' : 'filled'}_${_now().millisecondsSinceEpoch}.pdf';
    final result = await _service.save(
      sourcePath: path,
      outputPath: p.join(dir.path, name),
      plan: PdfFormPlan(values: state.values, marks: state.marks, flatten: state.flatten),
    );
    if (isClosed) return;
    emit(state.copyWith(status: FormStatus.done, result: result.valueOrNull, failure: result.failureOrNull));
  }

  Future<void> _closeRenderer() async {
    final r = _renderer;
    _renderer = null;
    _pages.clear();
    if (r != null) {
      try {
        await r.dispose();
      } catch (_) {}
    }
  }

  @override
  Future<void> close() async {
    await _closeRenderer();
    return super.close();
  }
}

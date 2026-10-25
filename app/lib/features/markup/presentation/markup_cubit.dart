import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/markup.dart';

class MarkupState extends Equatable {
  const MarkupState({
    this.items = const [],
    this.draft,
    this.tool = MarkupTool.pen,
    this.color = 0xE53935,
    this.widths = defaultWidths,
    this.opacities = defaultOpacities,
    this.filled = false,
    this.emoji = '✅',
    this.textSize = MarkupText.defaultSize,
    this.textBold = false,
    this.selectedId,
    this.undoDepth = 0,
    this.redoDepth = 0,
  });

  final List<MarkupItem> items;

  /// The line or shape being drawn right now.
  final MarkupItem? draft;
  final MarkupTool tool;

  /// RGB without opacity.
  final int color;
  final Map<MarkupTool, double> widths;
  final Map<MarkupTool, double> opacities;
  final bool filled;
  final String emoji;

  /// Font size of new text, a share of the page width.
  final double textSize;
  final bool textBold;
  final int? selectedId;
  final int undoDepth;
  final int redoDepth;

  static const defaultWidths = <MarkupTool, double>{
    MarkupTool.pen: 0.005,
    MarkupTool.pencil: 0.0035,
    MarkupTool.highlighter: 0.03,
    MarkupTool.line: 0.005,
    MarkupTool.arrow: 0.005,
    MarkupTool.rectangle: 0.005,
    MarkupTool.ellipse: 0.005,
  };

  static const defaultOpacities = <MarkupTool, double>{
    MarkupTool.pen: 1,
    MarkupTool.pencil: 0.85,
    MarkupTool.highlighter: 0.4,
    MarkupTool.line: 1,
    MarkupTool.arrow: 1,
    MarkupTool.rectangle: 1,
    MarkupTool.ellipse: 1,
  };

  static const minWidth = 0.0015;
  static const maxWidth = 0.06;

  double widthOf(MarkupTool t) => widths[t] ?? 0.005;
  double opacityOf(MarkupTool t) => opacities[t] ?? 1;

  /// ARGB of what the current tool draws.
  int argbFor(MarkupTool t) => (((opacityOf(t) * 255).round().clamp(0, 255)) << 24) | (color & 0xFFFFFF);

  MarkupItem? get selected {
    final id = selectedId;
    if (id == null) return null;
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool get canUndo => undoDepth > 0;
  bool get canRedo => redoDepth > 0;
  bool get hasMarks => items.isNotEmpty;

  MarkupState copyWith({
    List<MarkupItem>? items,
    Object? draft = _keep,
    MarkupTool? tool,
    int? color,
    Map<MarkupTool, double>? widths,
    Map<MarkupTool, double>? opacities,
    bool? filled,
    String? emoji,
    double? textSize,
    bool? textBold,
    Object? selectedId = _keep,
    int? undoDepth,
    int? redoDepth,
  }) => MarkupState(
    items: items ?? this.items,
    draft: identical(draft, _keep) ? this.draft : draft as MarkupItem?,
    tool: tool ?? this.tool,
    color: color ?? this.color,
    widths: widths ?? this.widths,
    opacities: opacities ?? this.opacities,
    filled: filled ?? this.filled,
    emoji: emoji ?? this.emoji,
    textSize: textSize ?? this.textSize,
    textBold: textBold ?? this.textBold,
    selectedId: identical(selectedId, _keep) ? this.selectedId : selectedId as int?,
    undoDepth: undoDepth ?? this.undoDepth,
    redoDepth: redoDepth ?? this.redoDepth,
  );

  static const _keep = Object();

  /// Identity of the lists lets the page repaint exactly when something was drawn.
  @override
  List<Object?> get props => [
    identityHashCode(items),
    draft == null ? null : identityHashCode(draft),
    tool,
    color,
    widths,
    opacities,
    filled,
    emoji,
    textSize,
    textBold,
    selectedId,
    undoDepth,
    redoDepth,
  ];
}

class MarkupCubit extends Cubit<MarkupState> {
  MarkupCubit({required this.page}) : super(const MarkupState());

  /// Size of the page picture in pixels; touches are shares of it.
  final Size page;

  var _nextId = 1;
  final _undo = <List<MarkupItem>>[];
  final _redo = <List<MarkupItem>>[];
  List<MarkupItem>? _before;
  var _changedInGesture = false;
  Offset _lastStroke = Offset.zero;

  /// Everything above a hair's width counts as a move, in page pixels.
  static const _minStep = 1.5;

  void _pushHistory(List<MarkupItem> previous) {
    _undo.add(previous);
    if (_undo.length > 100) _undo.removeAt(0);
    _redo.clear();
  }

  MarkupState _withDepths(MarkupState s) => s.copyWith(undoDepth: _undo.length, redoDepth: _redo.length);

  void _commit(List<MarkupItem> items, {Object? selectedId = _unset, bool recordHistory = true}) {
    if (recordHistory) _pushHistory(state.items);
    emit(_withDepths(state.copyWith(items: items, selectedId: identical(selectedId, _unset) ? state.selectedId : selectedId)));
  }

  static const _unset = Object();

  void selectTool(MarkupTool tool) {
    emit(state.copyWith(tool: tool, draft: null, selectedId: tool == MarkupTool.select ? state.selectedId : null));
  }

  void setColor(int rgb) {
    emit(state.copyWith(color: rgb & 0xFFFFFF));
    _restyleSelected();
    endStyleChange();
  }

  void setOpacity(double value) {
    final tool = _inkTool;
    emit(state.copyWith(opacities: {...state.opacities, tool: value.clamp(0.05, 1.0)}));
    _restyleSelected();
  }

  void setWidth(double value) {
    final tool = _inkTool;
    emit(state.copyWith(widths: {...state.widths, tool: value.clamp(MarkupState.minWidth, MarkupState.maxWidth)}));
    _restyleSelected();
  }

  void setFilled(bool value) {
    emit(state.copyWith(filled: value));
    _restyleSelected();
    endStyleChange();
  }

  void setEmoji(String emoji) {
    final text = emoji.trim();
    if (text.isEmpty) return;
    emit(state.copyWith(emoji: text));
    final s = state.selected;
    if (s is MarkupSticker && state.tool == MarkupTool.select) {
      _commit([
        for (final i in state.items)
          if (i.id == s.id) MarkupSticker(id: s.id, text: text, center: s.center, size: s.size, rotation: s.rotation) else i,
      ]);
    }
  }

  /// The tool whose width and opacity the controls show: the selected item's kind while moving, otherwise the current tool.
  MarkupTool get _inkTool {
    if (state.tool.hasInk) return state.tool;
    final s = state.selected;
    if (s is MarkupStroke)
      return switch (s.kind) {
        PenKind.pen => MarkupTool.pen,
        PenKind.pencil => MarkupTool.pencil,
        PenKind.highlighter => MarkupTool.highlighter,
      };
    if (s is MarkupShape)
      return switch (s.kind) {
        ShapeKind.line => MarkupTool.line,
        ShapeKind.arrow => MarkupTool.arrow,
        ShapeKind.rectangle => MarkupTool.rectangle,
        ShapeKind.ellipse => MarkupTool.ellipse,
      };
    return MarkupTool.pen;
  }

  /// Colour, opacity and thickness changes also apply to the item that is selected.
  void _restyleSelected() {
    final s = state.selected;
    if (s == null || state.tool != MarkupTool.select) return;
    final tool = _inkTool;
    final argb = state.argbFor(tool);
    final width = state.widthOf(tool);
    final changed = switch (s) {
      MarkupStroke() => s.copyWith(color: argb, width: width),
      MarkupShape() => s.copyWith(color: argb, width: width, filled: state.filled),
      MarkupSticker() => s,
      MarkupText() => s.copyWith(color: 0xFF000000 | state.color),
    };
    if (identical(changed, s)) return;
    _replace(s.id, changed, record: !_changedInGesture);
    _changedInGesture = true;
  }

  void _replace(int id, MarkupItem item, {bool record = true}) {
    final items = [
      for (final i in state.items)
        if (i.id == id) item else i,
    ];
    if (record) {
      _pushHistory(state.items);
    }
    emit(_withDepths(state.copyWith(items: items)));
  }

  /// Ends a run of control changes (a slider drag) so it counts as one step for Undo.
  void endStyleChange() => _changedInGesture = false;

  // region touches

  void pointerDown(Offset at) {
    final tool = state.tool;
    switch (tool) {
      case MarkupTool.pen:
      case MarkupTool.pencil:
      case MarkupTool.highlighter:
        _lastStroke = at;
        emit(
          state.copyWith(
            draft: MarkupStroke(id: -1, kind: tool.penKind!, points: [at], color: state.argbFor(tool), width: state.widthOf(tool)),
            selectedId: null,
          ),
        );
      case MarkupTool.line:
      case MarkupTool.arrow:
      case MarkupTool.rectangle:
      case MarkupTool.ellipse:
        emit(
          state.copyWith(
            draft: MarkupShape(id: -1, kind: tool.shapeKind!, from: at, to: at, color: state.argbFor(tool), width: state.widthOf(tool), filled: state.filled),
            selectedId: null,
          ),
        );
      case MarkupTool.eraser:
        _before = state.items;
        _eraseAt(at);
      case MarkupTool.sticker:
        final sticker = MarkupSticker(id: _nextId++, text: state.emoji, center: at, size: 0.12);
        _commit([...state.items, sticker], selectedId: sticker.id);
        emit(state.copyWith(tool: MarkupTool.select));
      case MarkupTool.select:
        _before = state.items;
        _changedInGesture = false;
        MarkupItem? found;
        for (final i in state.items.reversed) {
          if (MarkupGeometry.hit(i, at, page)) {
            found = i;
            break;
          }
        }
        emit(state.copyWith(selectedId: found?.id));
        _syncControlsTo(found);
      case MarkupTool.text:
      case MarkupTool.hand:
        break;
    }
  }

  void pointerMove(Offset at) {
    final d = state.draft;
    switch (state.tool) {
      case MarkupTool.pen:
      case MarkupTool.pencil:
      case MarkupTool.highlighter:
        if (d is! MarkupStroke) return;
        final step = Offset((at.dx - _lastStroke.dx) * page.width, (at.dy - _lastStroke.dy) * page.height).distance;
        if (step < _minStep) return;
        _lastStroke = at;
        emit(state.copyWith(draft: d.copyWith(points: [...d.points, at])));
      case MarkupTool.line:
      case MarkupTool.arrow:
      case MarkupTool.rectangle:
      case MarkupTool.ellipse:
        if (d is! MarkupShape) return;
        emit(state.copyWith(draft: d.copyWith(to: at)));
      case MarkupTool.eraser:
        _eraseAt(at);
      default:
        break;
    }
  }

  void pointerUp() {
    final d = state.draft;
    if (d is MarkupStroke) {
      _commit([...state.items, d.copyWith(id: _nextId++)], recordHistory: true);
      emit(state.copyWith(draft: null));
    } else if (d is MarkupShape) {
      final size = Offset((d.to.dx - d.from.dx) * page.width, (d.to.dy - d.from.dy) * page.height).distance;
      if (size >= page.width * 0.01) _commit([...state.items, d.copyWith(id: _nextId++)]);
      emit(state.copyWith(draft: null));
    } else if (state.tool == MarkupTool.eraser) {
      _finishGesture();
    }
  }

  /// A second finger came down: the line being drawn is dropped.
  void cancelDraft() {
    if (state.draft != null) emit(state.copyWith(draft: null));
  }

  void _eraseAt(Offset at) {
    final keep = [
      for (final i in state.items)
        if (!MarkupGeometry.hit(i, at, page, tolerance: 0.015)) i,
    ];
    if (keep.length == state.items.length) return;
    _changedInGesture = true;
    emit(_withDepths(state.copyWith(items: keep, selectedId: state.selected != null && keep.any((i) => i.id == state.selectedId) ? state.selectedId : null)));
  }

  void _finishGesture() {
    final before = _before;
    if (before != null && _changedInGesture) {
      _pushHistory(before);
      emit(_withDepths(state));
    }
    _before = null;
    _changedInGesture = false;
  }

  // endregion

  // region moving the selected item

  /// Moves, scales and turns the selected item. Values are changes since the last call; [delta] is a share of the page.
  void transformSelected({Offset delta = Offset.zero, double scale = 1, double rotation = 0}) {
    final s = state.selected;
    if (s == null) return;
    final moved = MarkupGeometry.transform(s, page, delta: delta, scale: scale, rotation: rotation);
    _changedInGesture = true;
    final items = [
      for (final i in state.items)
        if (i.id == s.id) moved else i,
    ];
    emit(state.copyWith(items: items));
  }

  /// Called when the finger lifts after moving the selected item.
  void endTransform() => _finishGesture();

  /// Sets the size of the selected sticker directly (a share of the page width).
  void resizeSelectedSticker(double size) {
    final s = state.selected;
    if (s is! MarkupSticker) return;
    final next = s.copyWith(size: size.clamp(MarkupSticker.minSize, MarkupSticker.maxSize));
    _replace(s.id, next, record: !_changedInGesture);
    _changedInGesture = true;
  }

  /// Puts [text] on the page at [at] and selects it so it can be moved or resized right away.
  void addText(Offset at, String text) {
    if (text.trim().isEmpty) return;
    final item = MarkupText(id: _nextId++, text: text.trim(), center: at, size: state.textSize, color: 0xFF000000 | state.color, bold: state.textBold);
    _commit([...state.items, item], selectedId: item.id);
    emit(state.copyWith(tool: MarkupTool.select));
  }

  /// Changes the words of a text mark; empty text removes it.
  void editText(int id, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      emit(state.copyWith(selectedId: id));
      deleteSelected();
      return;
    }
    for (final i in state.items) {
      if (i is MarkupText && i.id == id) {
        if (i.text == t) return;
        _commit([
          for (final j in state.items)
            if (j.id == id) i.copyWith(text: t) else j,
        ], selectedId: id);
        return;
      }
    }
  }

  /// The size of new text, and of the selected text mark.
  void setTextSize(double value) {
    final size = value.clamp(MarkupText.minSize, 0.2);
    emit(state.copyWith(textSize: size));
    final s = state.selected;
    if (s is MarkupText && state.tool == MarkupTool.select) {
      _replace(s.id, s.copyWith(size: size), record: !_changedInGesture);
      _changedInGesture = true;
    }
  }

  void setTextBold(bool bold) {
    emit(state.copyWith(textBold: bold));
    final s = state.selected;
    if (s is MarkupText && state.tool == MarkupTool.select) _replace(s.id, s.copyWith(bold: bold));
  }

  /// Picking a text mark loads its look into the controls.
  void _syncControlsTo(MarkupItem? item) {
    if (item is MarkupText) emit(state.copyWith(textSize: item.size.clamp(MarkupText.minSize, 0.2), textBold: item.bold));
  }

  void deleteSelected() {
    final id = state.selectedId;
    if (id == null) return;
    _commit([
      for (final i in state.items)
        if (i.id != id) i,
    ], selectedId: null);
  }

  // endregion

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(state.items);
    final previous = _undo.removeLast();
    emit(_withDepths(state.copyWith(items: previous, draft: null, selectedId: previous.any((i) => i.id == state.selectedId) ? state.selectedId : null)));
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(state.items);
    final next = _redo.removeLast();
    emit(_withDepths(state.copyWith(items: next, draft: null, selectedId: next.any((i) => i.id == state.selectedId) ? state.selectedId : null)));
  }

  void clearAll() {
    if (state.items.isEmpty) return;
    _commit(const [], selectedId: null);
  }
}

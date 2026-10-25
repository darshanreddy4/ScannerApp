import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/markup.dart';
import '../markup_paint.dart';
import 'markup_cubit.dart';

/// The page with the marks on it. Drawing tools draw, the move tool moves marks, the zoom tool zooms the page.
class MarkupCanvas extends StatefulWidget {
  const MarkupCanvas({super.key, required this.base, required this.pageSize, this.onTextTap});

  /// The picture of the page; null while it loads.
  final ui.Image? base;
  final Size pageSize;

  /// A tap on the page while the Text tool is chosen, as a share of the page.
  final ValueChanged<Offset>? onTextTap;

  @override
  State<MarkupCanvas> createState() => _MarkupCanvasState();
}

class _MarkupCanvasState extends State<MarkupCanvas> {
  final _pointers = <int>{};
  var _ignoring = false;
  var _lastScale = 1.0;
  var _lastRotation = 0.0;
  var _lastFocal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MarkupCubit>();
    return BlocBuilder<MarkupCubit, MarkupState>(
      builder: (context, state) {
        return LayoutBuilder(
          builder: (context, box) {
            final aspect = widget.pageSize.width / widget.pageSize.height;
            var w = box.maxWidth, h = w / aspect;
            if (h > box.maxHeight) {
              h = box.maxHeight;
              w = h * aspect;
            }
            Offset norm(Offset local) => Offset((local.dx / w).clamp(0.0, 1.0), (local.dy / h).clamp(0.0, 1.0));

            final selected = state.tool == MarkupTool.select ? state.selected : null;
            Widget layer = CustomPaint(
              key: const ValueKey('markup-canvas'),
              size: Size(w, h),
              painter: _MarkupPainter(base: widget.base, items: state.items, draft: state.draft, selected: selected),
            );
            if (state.tool == MarkupTool.text) {
              layer = GestureDetector(
                key: const ValueKey('text-tap-area'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => widget.onTextTap?.call(norm(d.localPosition)),
                child: layer,
              );
            } else if (state.tool == MarkupTool.select) {
              layer = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (d) {
                  _lastScale = 1;
                  _lastRotation = 0;
                  _lastFocal = d.localFocalPoint;
                  cubit.pointerDown(norm(d.localFocalPoint));
                },
                onScaleUpdate: (d) {
                  final move = d.localFocalPoint - _lastFocal;
                  cubit.transformSelected(delta: Offset(move.dx / w, move.dy / h), scale: d.scale / _lastScale, rotation: d.rotation - _lastRotation);
                  _lastFocal = d.localFocalPoint;
                  _lastScale = d.scale;
                  _lastRotation = d.rotation;
                },
                onScaleEnd: (_) => cubit.endTransform(),
                child: layer,
              );
            } else if (state.tool != MarkupTool.hand) {
              layer = Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  _pointers.add(e.pointer);
                  if (_pointers.length > 1) {
                    _ignoring = true;
                    cubit.cancelDraft();
                  } else {
                    cubit.pointerDown(norm(e.localPosition));
                  }
                },
                onPointerMove: (e) {
                  if (!_ignoring) cubit.pointerMove(norm(e.localPosition));
                },
                onPointerUp: (e) => _lift(e.pointer, cubit),
                onPointerCancel: (e) => _lift(e.pointer, cubit),
                child: layer,
              );
            }
            final hand = state.tool == MarkupTool.hand;
            return Center(
              child: SizedBox(
                width: w,
                height: h,
                child: DecoratedBox(
                  decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 12)]),
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 6,
                    panEnabled: hand,
                    scaleEnabled: hand,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(width: w, height: h, child: layer),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _lift(int pointer, MarkupCubit cubit) {
    _pointers.remove(pointer);
    if (_pointers.isNotEmpty) return;
    if (!_ignoring) cubit.pointerUp();
    _ignoring = false;
  }
}

class _MarkupPainter extends CustomPainter {
  _MarkupPainter({required this.base, required this.items, required this.draft, required this.selected});

  final ui.Image? base;
  final List<MarkupItem> items;
  final MarkupItem? draft;
  final MarkupItem? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = Colors.white);
    final image = base;
    if (image != null) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), rect, Paint()..filterQuality = FilterQuality.medium);
    }
    canvas.clipRect(rect);
    paintMarkup(canvas, size, draft == null ? items : [...items, draft!]);
    if (selected != null) paintSelection(canvas, size, selected!);
  }

  @override
  bool shouldRepaint(_MarkupPainter old) =>
      !identical(old.items, items) || !identical(old.draft, draft) || !identical(old.selected, selected) || old.base != base;
}

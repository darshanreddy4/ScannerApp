import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../data/slide_painter.dart';
import '../domain/slide_model.dart';

/// Draws one slide, scaled to fit. With [interactive] set, shapes can be selected, moved and resized by touch.
class SlideCanvas extends StatefulWidget {
  const SlideCanvas({
    super.key,
    required this.view,
    required this.images,
    required this.widthEmu,
    required this.heightEmu,
    this.selected,
    this.interactive = false,
    this.hitTest,
    this.onSelect,
    this.onFrame,
    this.onEditText,
    this.imagesVersion = 0,
  });

  final SlideView view;
  final Map<String, ui.Image> images;
  final double widthEmu;
  final double heightEmu;
  final ShapeView? selected;
  final bool interactive;
  final ShapeView? Function(double xEmu, double yEmu)? hitTest;
  final ValueChanged<String?>? onSelect;
  final void Function(String id, Frame frame)? onFrame;
  final VoidCallback? onEditText;
  final int imagesVersion;

  @override
  State<SlideCanvas> createState() => _SlideCanvasState();
}

enum _Drag { none, move, resize }

class _SlideCanvasState extends State<SlideCanvas> {
  _Drag _mode = _Drag.none;
  Frame? _live;
  String? _liveId;
  int _corner = 0;
  Offset _grab = Offset.zero;
  Frame? _origin;

  double _scale(Size s) => s.width / widget.widthEmu;

  Offset _emu(Offset local, Size s) => local / _scale(s);

  /// Corner handle under [local], 0 top-left, 1 top-right, 2 bottom-right, 3 bottom-left, or -1.
  int _handleAt(Offset local, Size size, Frame f) {
    final k = _scale(size);
    final corners = [Offset(f.x, f.y), Offset(f.x + f.w, f.y), Offset(f.x + f.w, f.y + f.h), Offset(f.x, f.y + f.h)];
    for (var i = 0; i < 4; i++) {
      if ((corners[i] * k - local).distance <= 22) return i;
    }
    return -1;
  }

  void _start(DragStartDetails d, Size size) {
    final sel = widget.selected;
    final local = d.localPosition;
    if (sel != null && sel.editable && sel.frame.rot == 0) {
      final h = _handleAt(local, size, sel.frame);
      if (h >= 0) {
        _mode = _Drag.resize;
        _corner = h;
        _origin = sel.frame;
        _liveId = sel.id;
        _live = sel.frame;
        return;
      }
    }
    final e = _emu(local, size);
    final target = widget.hitTest?.call(e.dx, e.dy);
    if (target == null) {
      _mode = _Drag.none;
      return;
    }
    if (target.id != sel?.id) widget.onSelect?.call(target.id);
    _mode = _Drag.move;
    _origin = target.frame;
    _liveId = target.id;
    _live = target.frame;
    _grab = e;
  }

  void _update(DragUpdateDetails d, Size size) {
    final origin = _origin;
    if (origin == null || _mode == _Drag.none) return;
    final e = _emu(d.localPosition, size);
    if (_mode == _Drag.move) {
      final dx = e.dx - _grab.dx, dy = e.dy - _grab.dy;
      setState(() => _live = origin.copyWith(x: origin.x + dx, y: origin.y + dy));
      return;
    }
    // Resize: the corner opposite the one being dragged stays where it is.
    final fixed = switch (_corner) {
      0 => Offset(origin.x + origin.w, origin.y + origin.h),
      1 => Offset(origin.x, origin.y + origin.h),
      2 => Offset(origin.x, origin.y),
      _ => Offset(origin.x + origin.w, origin.y),
    };
    var dx = e.dx - fixed.dx, dy = e.dy - fixed.dy;
    final keepShape = widget.selected?.kind == ShapeKind.picture;
    if (keepShape && origin.h > 0 && origin.w > 0) {
      final ratio = origin.w / origin.h;
      if (dx.abs() / ratio > dy.abs()) {
        dy = dx.abs() / ratio * (dy < 0 ? -1 : 1);
      } else {
        dx = dy.abs() * ratio * (dx < 0 ? -1 : 1);
      }
    }
    const minSize = 150000.0;
    final w = math.max(minSize, dx.abs()), h = math.max(minSize, dy.abs());
    final left = dx < 0 ? fixed.dx - w : fixed.dx, top = dy < 0 ? fixed.dy - h : fixed.dy;
    setState(() => _live = origin.copyWith(x: left, y: top, w: w, h: h));
  }

  void _end() {
    final id = _liveId, frame = _live, origin = _origin;
    final moved = frame != null && origin != null && (frame.x != origin.x || frame.y != origin.y || frame.w != origin.w || frame.h != origin.h);
    if (id != null && frame != null && moved) widget.onFrame?.call(id, frame);
    setState(() {
      _mode = _Drag.none;
      _live = null;
      _liveId = null;
      _origin = null;
    });
  }

  void _tap(TapUpDetails d, Size size) {
    final e = _emu(d.localPosition, size);
    final target = widget.hitTest?.call(e.dx, e.dy);
    if (target != null && target.id == widget.selected?.id && target.canHaveText) {
      widget.onEditText?.call();
      return;
    }
    widget.onSelect?.call(target?.id);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.widthEmu / widget.heightEmu;
    return AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          final paint = CustomPaint(
            size: size,
            painter: _SlidePainter(
              view: widget.view,
              images: widget.images,
              imagesVersion: widget.imagesVersion,
              widthEmu: widget.widthEmu,
              heightEmu: widget.heightEmu,
              selected: widget.interactive ? widget.selected : null,
              liveId: _liveId,
              liveFrame: _live,
            ),
          );
          if (!widget.interactive) return RepaintBoundary(child: paint);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d, size),
            onPanStart: (d) => _start(d, size),
            onPanUpdate: (d) => _update(d, size),
            onPanEnd: (_) => _end(),
            onPanCancel: _end,
            child: RepaintBoundary(child: paint),
          );
        },
      ),
    );
  }
}

class _SlidePainter extends CustomPainter {
  _SlidePainter({
    required this.view,
    required this.images,
    required this.imagesVersion,
    required this.widthEmu,
    required this.heightEmu,
    this.selected,
    this.liveId,
    this.liveFrame,
  });

  final SlideView view;
  final Map<String, ui.Image> images;
  final int imagesVersion;
  final double widthEmu;
  final double heightEmu;
  final ShapeView? selected;
  final String? liveId;
  final Frame? liveFrame;

  @override
  void paint(Canvas canvas, Size size) {
    final wPt = widthEmu / emuPerPt, hPt = heightEmu / emuPerPt;
    final k = size.width / wPt;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(k);
    if (liveId == null || liveFrame == null) {
      paintSlide(canvas, view, images, wPt, hPt);
    } else {
      paintSlide(
        canvas,
        SlideView(
          background: view.background,
          template: view.template,
          shapes: [for (final s in view.shapes) s.id == liveId && s.element != null ? s.withFrame(liveFrame!) : s],
        ),
        images,
        wPt,
        hPt,
      );
    }
    canvas.restore();

    final sel = selected;
    if (sel == null) return;
    final f = liveId == sel.id && liveFrame != null ? liveFrame! : sel.frame;
    final kEmu = size.width / widthEmu;
    canvas.save();
    canvas.translate(f.cx * kEmu, f.cy * kEmu);
    if (f.rot != 0) canvas.rotate(f.rot * math.pi / 180);
    final r = Rect.fromCenter(center: Offset.zero, width: f.w * kEmu, height: f.h * kEmu);
    canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.primary,
    );
    if (sel.editable && f.rot == 0) {
      for (final c in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) {
        canvas.drawCircle(c, 7, Paint()..color = Colors.white);
        canvas.drawCircle(
          c,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = AppColors.primary,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SlidePainter old) => true;
}

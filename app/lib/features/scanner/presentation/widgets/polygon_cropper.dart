import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/quad.dart';

/// Image with a draggable 4-corner polygon (plus edge handles) and a magnifier loupe.
class PolygonCropper extends StatefulWidget {
  const PolygonCropper({
    super.key,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.quad,
    required this.onChanged,
    this.previewBytes,
  });

  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final Quad quad;
  final ValueChanged<Quad> onChanged;

  /// Filtered rendering of the same image; shown instead of the file when available.
  final Uint8List? previewBytes;

  @override
  State<PolygonCropper> createState() => _PolygonCropperState();
}

enum _HandleKind { corner, edge }

class _PolygonCropperState extends State<PolygonCropper> {
  static const _hitRadius = 40.0;

  _HandleKind? _kind;
  int _index = -1;
  Offset? _finger;
  Rect _rect = Rect.zero;

  Offset _toScreen(NormPoint p) => Offset(_rect.left + p.x * _rect.width, _rect.top + p.y * _rect.height);

  NormPoint _edgeMid(Quad q, int i) {
    final a = q.points[i], b = q.points[(i + 1) % 4];
    return NormPoint((a.x + b.x) / 2, (a.y + b.y) / 2);
  }

  void _onStart(Offset pos) {
    final q = widget.quad;
    var best = double.infinity;
    _kind = null;

    for (var i = 0; i < 4; i++) {
      final d = (_toScreen(q.points[i]) - pos).distance;
      if (d < _hitRadius && d < best) {
        best = d;
        _kind = _HandleKind.corner;
        _index = i;
      }
    }
    if (_kind == null) {
      for (var i = 0; i < 4; i++) {
        final d = (_toScreen(_edgeMid(q, i)) - pos).distance;
        if (d < _hitRadius && d < best) {
          best = d;
          _kind = _HandleKind.edge;
          _index = i;
        }
      }
    }
    setState(() => _finger = _kind == null ? null : pos);
  }

  void _onUpdate(Offset pos, Offset delta) {
    if (_kind == null || _rect.isEmpty) return;
    final q = widget.quad;
    if (_kind == _HandleKind.corner) {
      final local = pos - _rect.topLeft;
      widget.onChanged(q.withPoint(_index, NormPoint(local.dx / _rect.width, local.dy / _rect.height)));
    } else {
      widget.onChanged(q.withEdgeShift(_index, delta.dx / _rect.width, delta.dy / _rect.height));
    }
    setState(() => _finger = pos);
  }

  void _onEnd() => setState(() {
    _kind = null;
    _finger = null;
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final fitted = applyBoxFit(BoxFit.contain, Size(widget.imageWidth.toDouble(), widget.imageHeight.toDouble()), c.biggest).destination;
        _rect = Rect.fromLTWH((c.maxWidth - fitted.width) / 2, (c.maxHeight - fitted.height) / 2, fitted.width, fitted.height);

        final finger = _finger;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _onStart(d.localPosition),
          onPanUpdate: (d) => _onUpdate(d.localPosition, d.delta),
          onPanEnd: (_) => _onEnd(),
          onPanCancel: _onEnd,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _rect,
                child: widget.previewBytes != null
                    ? Image.memory(widget.previewBytes!, fit: BoxFit.fill, gaplessPlayback: true)
                    : Image.file(File(widget.imagePath), fit: BoxFit.fill, gaplessPlayback: true),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _CropPainter(
                    quad: widget.quad,
                    rect: _rect,
                    activeCorner: _kind == _HandleKind.corner ? _index : null,
                    activeEdge: _kind == _HandleKind.edge ? _index : null,
                  ),
                ),
              ),
              if (finger != null && _kind == _HandleKind.corner) _Loupe(finger: finger, bounds: c.biggest),
            ],
          ),
        );
      },
    );
  }
}

class _Loupe extends StatelessWidget {
  const _Loupe({required this.finger, required this.bounds});
  final Offset finger;
  final Size bounds;

  static const _size = 100.0;

  @override
  Widget build(BuildContext context) {
    // Keep the loupe clear of the finger; flip below it near the top edge.
    final above = finger.dy > _size + 40;
    final top = above ? finger.dy - _size - 40 : finger.dy + 40;
    final left = (finger.dx - _size / 2).clamp(0.0, bounds.width - _size);
    return Positioned(
      left: left,
      top: top,
      child: RawMagnifier(
        size: const Size(_size, _size),
        magnificationScale: 2.2,
        focalPointOffset: Offset(finger.dx - (left + _size / 2), finger.dy - (top + _size / 2)),
        decoration: const MagnifierDecoration(
          shape: CircleBorder(side: BorderSide(color: Colors.white, width: 2)),
          shadows: [BoxShadow(color: Colors.black54, blurRadius: 8)],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.quad, required this.rect, this.activeCorner, this.activeEdge});

  final Quad quad;
  final Rect rect;
  final int? activeCorner;
  final int? activeEdge;

  Offset _pt(NormPoint p) => Offset(rect.left + p.x * rect.width, rect.top + p.y * rect.height);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = quad.points.map(_pt).toList();
    final path = Path()..addPolygon(pts, true);

    final outside = Path.combine(PathOperation.difference, Path()..addRect(rect), path);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.scannerOverlay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    for (var i = 0; i < 4; i++) {
      final mid = Offset.lerp(pts[i], pts[(i + 1) % 4], 0.5)!;
      canvas.drawCircle(mid, activeEdge == i ? 9 : 6, Paint()..color = AppColors.scannerOverlay);
    }

    for (var i = 0; i < 4; i++) {
      final active = activeCorner == i;
      canvas.drawCircle(pts[i], active ? 15 : 12, Paint()..color = Colors.white);
      canvas.drawCircle(
        pts[i],
        active ? 15 : 12,
        Paint()
          ..color = AppColors.scannerOverlay
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.quad != quad || old.rect != rect || old.activeCorner != activeCorner || old.activeEdge != activeEdge;
}

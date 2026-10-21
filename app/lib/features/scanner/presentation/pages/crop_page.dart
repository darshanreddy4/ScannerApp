import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../domain/entities/quad.dart';
import '../bloc/scan_session_cubit.dart';

class CropPage extends StatelessWidget {
  const CropPage({super.key});

  Future<void> _next(BuildContext context) async {
    final session = context.read<ScanSessionCubit>();
    final ok = await session.confirmCrop();
    if (!context.mounted) return;
    if (ok) {
      context.push('/scan/enhance');
    } else if (session.state.error != null) {
      showFailure(context, session.state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.select((ScanSessionCubit c) => c.state.draft);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);
    if (draft == null) return const Scaffold(backgroundColor: AppColors.scannerBackdrop);

    return Scaffold(
      backgroundColor: AppColors.scannerBackdrop,
      appBar: AppBar(
        backgroundColor: AppColors.scannerBackdrop,
        foregroundColor: Colors.white,
        title: const Text('Adjust corners', style: TextStyle(color: Colors.white, fontSize: 17)),
        leading: IconButton(
          tooltip: 'Discard',
          icon: const Icon(AppIcons.close),
          onPressed: () {
            context.read<ScanSessionCubit>().discardDraft();
            context.pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => _next(context),
            child: const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: PolygonCropper(
                      imagePath: draft.rawPath,
                      imageWidth: draft.rawWidth,
                      imageHeight: draft.rawHeight,
                      quad: draft.quad,
                      onChanged: context.read<ScanSessionCubit>().updateQuad,
                    ),
                  ),
                ),
                _CropToolbar(busy: busy),
              ],
            ),
            BusyOverlay(visible: busy, label: 'Working'),
          ],
        ),
      ),
    );
  }
}

class _CropToolbar extends StatelessWidget {
  const _CropToolbar({required this.busy});
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScanSessionCubit>();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      color: const Color(0xFF111827),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ToolButton(icon: AppIcons.rotate, label: 'Rotate', onTap: busy ? null : cubit.rotateRaw),
          _ToolButton(icon: AppIcons.fullFrame, label: 'Full page', onTap: cubit.useFullFrame),
          _ToolButton(icon: AppIcons.reset, label: 'Reset', onTap: () => cubit.updateQuad(Quad.defaultInset)),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: onTap == null ? Colors.white30 : Colors.white, size: 24),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: onTap == null ? Colors.white30 : Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      );
}

/// Image with a draggable 4-corner polygon (plus edge handles) and a magnifier loupe.
class PolygonCropper extends StatefulWidget {
  const PolygonCropper({
    super.key,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.quad,
    required this.onChanged,
  });

  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final Quad quad;
  final ValueChanged<Quad> onChanged;

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
    return LayoutBuilder(builder: (context, c) {
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(widget.imageWidth.toDouble(), widget.imageHeight.toDouble()),
        c.biggest,
      ).destination;
      _rect = Rect.fromLTWH((c.maxWidth - fitted.width) / 2, (c.maxHeight - fitted.height) / 2, fitted.width, fitted.height);

      final q = widget.quad;
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
              child: Image.file(File(widget.imagePath), fit: BoxFit.fill, gaplessPlayback: true),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _CropPainter(
                  quad: q,
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
    });
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

    // Dim everything outside the selection.
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
      final active = activeEdge == i;
      canvas.drawCircle(mid, active ? 9 : 6, Paint()..color = AppColors.scannerOverlay);
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
  bool shouldRepaint(_CropPainter old) =>
      old.quad != quad || old.rect != rect || old.activeCorner != activeCorner || old.activeEdge != activeEdge;
}

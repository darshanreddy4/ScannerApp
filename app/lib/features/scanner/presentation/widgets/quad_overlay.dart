import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/quad.dart';

/// Draws the detected document outline over the live preview.
class QuadOverlayPainter extends CustomPainter {
  QuadOverlayPainter({required this.quad, required this.locked});

  final Quad? quad;
  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final q = quad;
    if (q == null) return;

    final color = locked ? AppColors.success : AppColors.scannerOverlay;
    final path = Path()
      ..moveTo(q.tl.x * size.width, q.tl.y * size.height)
      ..lineTo(q.tr.x * size.width, q.tr.y * size.height)
      ..lineTo(q.br.x * size.width, q.br.y * size.height)
      ..lineTo(q.bl.x * size.width, q.bl.y * size.height)
      ..close();

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = color;
    for (final p in q.points) {
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), 5, dot);
    }
  }

  @override
  bool shouldRepaint(QuadOverlayPainter old) => old.quad != quad || old.locked != locked;
}

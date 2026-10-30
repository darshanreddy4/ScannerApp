import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/quad.dart';
import '../../domain/entities/scan_mode.dart';

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

/// Frame to fit a card in, drawn with the same rectangle that becomes the first crop when no outline is detected.
class CardGuidePainter extends CustomPainter {
  CardGuidePainter(this.mode);

  final ScanMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    final q = mode.guideQuad(size.width / size.height);
    if (q == null) return;
    final rect = Rect.fromLTRB(q.tl.x * size.width, q.tl.y * size.height, q.br.x * size.width, q.br.y * size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(CardGuidePainter old) => old.mode != mode;
}

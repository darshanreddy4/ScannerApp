import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A gold coin with the app's page-and-grid symbol pressed into its face. [dim] turns it grey, for "not enough".
/// [glint] (0 to 1) slides the shine across the face; null keeps it at rest.
class GoldCoin extends StatelessWidget {
  const GoldCoin({super.key, this.size = 32, this.dim = false, this.glint});

  final double size;
  final bool dim;
  final double? glint;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(size),
      painter: _CoinPainter(dim: dim, glint: glint),
    ),
  );
}

const _greyscale = ColorFilter.matrix(<double>[0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 0.8, 0]);

class _CoinPainter extends CustomPainter {
  const _CoinPainter({required this.dim, required this.glint});
  final bool dim;
  final double? glint;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 * 0.92;
    if (dim) canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = _greyscale);

    canvas.drawCircle(
      c.translate(0, r * 0.09),
      r * 0.97,
      Paint()
        ..color = const Color(0x44000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.12),
    );

    final rimRect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF3B0), Color(0xFFF7C600), Color(0xFFB77900), Color(0xFFF8D54E)],
          stops: [0, 0.4, 0.75, 1],
        ).createShader(rimRect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04
        ..color = const Color(0x998A5A00),
    );

    if (size.width >= 28) {
      final ticks = Paint()
        ..color = const Color(0x558A5A00)
        ..strokeWidth = math.max(0.6, r * 0.018);
      for (var i = 0; i < 56; i++) {
        final a = i / 56 * math.pi * 2;
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r * 0.9), c + Offset(math.cos(a), math.sin(a)) * (r * 0.97), ticks);
      }
    }

    final face = r * 0.82;
    final faceRect = Rect.fromCircle(center: c, radius: face);
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [Color(0xFFFFE98A), Color(0xFFF9C21C), Color(0xFFE19A00), Color(0xFFC98100)],
          stops: [0, 0.45, 0.8, 1],
        ).createShader(faceRect),
    );
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..color = const Color(0xCCA66A00),
    );
    canvas.drawCircle(
      c,
      face - r * 0.03,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.022
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCCFFF6C8), Color(0x00FFF6C8)],
        ).createShader(faceRect),
    );

    _symbol(canvas, c, r);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: face)));
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-0.6);
    final shift = glint == null ? -0.1 : (-1.3 + 2.6 * glint!.clamp(0.0, 1.0));
    final band = Rect.fromLTRB(-r * 1.4, r * (shift - 0.22), r * 1.4, r * (shift + 0.22));
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: glint == null ? 0.28 : 0.5),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.restore();

    if (dim) canvas.restore();
  }

  /// The page with a folded corner and a grid of cells, pressed into the metal: light on the upper left, shade on the lower right.
  void _symbol(Canvas canvas, Offset c, double r) {
    final s = r * 0.76;
    final w = 1.0, h = 1.25;
    canvas.save();
    canvas.translate(c.dx - w * s / 2, c.dy - h * s / 2);
    canvas.scale(s);

    final body = Path.combine(
      PathOperation.difference,
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(0.12))),
      Path()
        ..moveTo(0.64, 0)
        ..lineTo(1.02, 0)
        ..lineTo(1.02, 0.38)
        ..close(),
    );
    final flap = Path()
      ..moveTo(0.64, 0)
      ..lineTo(1, 0.36)
      ..lineTo(0.64, 0.36)
      ..close();
    final cells = <RRect>[
      for (final rect in const [
        Rect.fromLTWH(0.13, 0.5, 0.44, 0.17),
        Rect.fromLTWH(0.61, 0.5, 0.26, 0.17),
        Rect.fromLTWH(0.13, 0.74, 0.26, 0.17),
        Rect.fromLTWH(0.43, 0.74, 0.44, 0.17),
        Rect.fromLTWH(0.13, 0.98, 0.44, 0.17),
        Rect.fromLTWH(0.61, 0.98, 0.26, 0.17),
        Rect.fromLTWH(0.13, 0.15, 0.4, 0.07),
        Rect.fromLTWH(0.13, 0.28, 0.28, 0.07),
      ])
        RRect.fromRectAndRadius(rect, const Radius.circular(0.04)),
    ];

    final d = 0.025;
    canvas.save();
    canvas.translate(d, d);
    canvas.drawPath(body, Paint()..color = const Color(0xAA7A4A00));
    canvas.restore();
    canvas.save();
    canvas.translate(-d, -d);
    canvas.drawPath(body, Paint()..color = const Color(0xCCFFF3B8));
    canvas.restore();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE27A), Color(0xFFF2B100)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(flap, Paint()..color = const Color(0xFFE09A00));
    for (final cell in cells) {
      canvas.drawRRect(cell.shift(const Offset(0.012, 0.012)), Paint()..color = const Color(0x99FFF3B8));
      canvas.drawRRect(cell, Paint()..color = const Color(0xFFB77900));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoinPainter old) => old.dim != dim || old.glint != glint;
}

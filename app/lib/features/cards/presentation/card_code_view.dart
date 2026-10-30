import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart' hide Text;

import '../../../core/widgets/text.dart';
import '../domain/cards.dart';

/// The code of a card as black bars or squares on white, with the quiet margin scanners need.
class CardCodeView extends StatelessWidget {
  const CardCodeView({super.key, required this.type, required this.number, this.maxHeight = 130});
  final CardCodeType type;
  final String number;
  final double maxHeight;

  static const _margin = 14.0;

  @override
  Widget build(BuildContext context) {
    final barcode = type.barcode;
    if (barcode == null || number.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final inner = box.maxWidth - _margin * 2;
        final side = inner < 240 ? inner : 240.0;
        final width = type.isSquare ? side : inner;
        final height = type.isSquare ? side : (type == CardCodeType.pdf417 ? inner * 0.3 : maxHeight).clamp(60.0, maxHeight * 1.6);
        List<BarcodeBar> bars;
        try {
          bars = barcode.make(number, width: width, height: height).whereType<BarcodeBar>().where((b) => b.black).toList();
        } on Object {
          return const Text('This number cannot be drawn as a code.', style: TextStyle(color: Colors.red));
        }
        return Semantics(
          image: true,
          label: 'Code for $number',
          excludeSemantics: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(_margin),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: CustomPaint(size: Size(width, height), painter: _BarsPainter(bars)),
            ),
          ),
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.bars);
  final List<BarcodeBar> bars;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (final b in bars) {
      canvas.drawRect(Rect.fromLTWH(b.left, b.top, b.width, b.height), paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.bars.length != bars.length || (bars.isNotEmpty && old.bars.first.width != bars.first.width);
}

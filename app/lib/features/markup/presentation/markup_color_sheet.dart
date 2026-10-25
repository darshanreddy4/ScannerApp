import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../domain/markup.dart';
import 'markup_cubit.dart';

const _sheetColor = Color(0xFF2B2B2D);

/// Opens the colour picker for the marks. [cubit] is the page's markup state.
Future<void> showMarkupColorSheet(BuildContext context, MarkupCubit cubit) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: _sheetColor,
  showDragHandle: false,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (_) => BlocProvider.value(value: cubit, child: const MarkupColorSheet()),
);

class MarkupColorSheet extends StatefulWidget {
  const MarkupColorSheet({super.key});

  @override
  State<MarkupColorSheet> createState() => _MarkupColorSheetState();
}

class _MarkupColorSheetState extends State<MarkupColorSheet> {
  var _ring = false;

  static const quick = <int>[0xE53935, 0xF57C00, 0xFBC02D, 0x43A047, 0x1E88E5, 0x8E24AA, 0x000000, 0x424242, 0xFFFFFF];

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MarkupCubit>();
    return BlocBuilder<MarkupCubit, MarkupState>(
      builder: (context, state) {
        final tool = state.tool.hasInk ? state.tool : MarkupTool.pen;
        final opacity = state.opacityOf(tool);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 40),
                        Row(
                          children: [
                            _Pill(label: 'Grid', selected: !_ring, onTap: () => setState(() => _ring = false)),
                            const SizedBox(width: 8),
                            _Pill(label: 'Ring', selected: _ring, onTap: () => setState(() => _ring = true)),
                          ],
                        ),
                        IconButton.filled(
                          tooltip: 'Close',
                          style: IconButton.styleFrom(backgroundColor: Colors.white12, foregroundColor: Colors.white),
                          icon: const Icon(AppIcons.close, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_ring) _RingPicker(rgb: state.color, onChanged: cubit.setColor) else _ColorGrid(selected: state.color, onPick: cubit.setColor),
                    const SizedBox(height: 16),
                    _OpacitySlider(rgb: state.color, value: opacity, onChanged: cubit.setOpacity, onEnd: cubit.endStyleChange),
                    const Divider(color: Colors.white12, height: 28),
                    Row(
                      children: [
                        Container(
                          key: const ValueKey('current-color'),
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Color(0xFF000000 | state.color).withValues(alpha: opacity),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: [for (final c in quick) _Swatch(rgb: c, selected: state.color == c, onTap: () => cubit.setColor(c))],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(color: selected ? Colors.white : Colors.white12, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.rgb, required this.selected, required this.onTap});
  final int rgb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkResponse(
    key: ValueKey('swatch-${rgb.toRadixString(16).padLeft(6, '0')}'),
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Color(0xFF000000 | rgb),
        shape: BoxShape.circle,
        border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 3 : 1),
      ),
    ),
  );
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.selected, required this.onPick});
  final int selected;
  final ValueChanged<int> onPick;

  static const _hues = <double>[205, 222, 250, 282, 335, 8, 24, 42, 55, 68, 98, 130];

  static List<List<int>> rows() {
    int rgb(HSLColor c) => c.toColor().toARGB32() & 0xFFFFFF;
    return [
      [for (var i = 0; i < 12; i++) rgb(HSLColor.fromAHSL(1, 0, 0, 1 - i / 11))],
      for (var r = 0; r < 9; r++) [for (final h in _hues) rgb(HSLColor.fromAHSL(1, h, 0.75, 0.22 + r * 0.075))],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final grid = rows();
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          for (final row in grid)
            Row(
              children: [
                for (final c in row)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onPick(c),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color(0xFF000000 | c)),
                          child: c == selected ? const Center(child: Icon(AppIcons.check, size: 14, color: Colors.white)) : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A hue ring with a square for saturation and brightness inside.
class _RingPicker extends StatefulWidget {
  const _RingPicker({required this.rgb, required this.onChanged});
  final int rgb;
  final ValueChanged<int> onChanged;

  @override
  State<_RingPicker> createState() => _RingPickerState();
}

class _RingPickerState extends State<_RingPicker> {
  late HSVColor _hsv = HSVColor.fromColor(Color(0xFF000000 | widget.rgb));
  var _dragRing = true;

  @override
  void didUpdateWidget(_RingPicker old) {
    super.didUpdateWidget(old);
    // Keep the hue while the picked colour is grey or black, where it cannot be read back from the colour.
    final now = HSVColor.fromColor(Color(0xFF000000 | widget.rgb));
    if ((_hsv.toColor().toARGB32() & 0xFFFFFF) != widget.rgb) {
      _hsv = now.saturation == 0 || now.value == 0 ? _hsv.withSaturation(now.saturation).withValue(now.value) : now;
    }
  }

  void _emit() => widget.onChanged(_hsv.toColor().toARGB32() & 0xFFFFFF);

  void _touch(Offset p, double side, {required bool start}) {
    final c = Offset(side / 2, side / 2);
    final d = p - c;
    final outer = side / 2, ringWidth = side * 0.11, inner = outer - ringWidth;
    if (start) _dragRing = d.distance > inner * 0.98;
    if (_dragRing) {
      var deg = math.atan2(d.dy, d.dx) * 180 / math.pi;
      if (deg < 0) deg += 360;
      setState(() => _hsv = _hsv.withHue(deg));
    } else {
      final half = inner * 0.74;
      final x = ((d.dx + half) / (half * 2)).clamp(0.0, 1.0), y = ((d.dy + half) / (half * 2)).clamp(0.0, 1.0);
      setState(() => _hsv = _hsv.withSaturation(x).withValue(1 - y));
    }
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxWidth, 300.0);
        return Center(
          child: GestureDetector(
            key: const ValueKey('ring-picker'),
            onPanStart: (d) => _touch(d.localPosition, side, start: true),
            onPanUpdate: (d) => _touch(d.localPosition, side, start: false),
            onTapDown: (d) => _touch(d.localPosition, side, start: true),
            child: CustomPaint(size: Size.square(side), painter: _RingPainter(_hsv)),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.hsv);
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final c = Offset(side / 2, side / 2);
    final ringWidth = side * 0.11;
    final radius = side / 2 - ringWidth / 2;
    final sweep = SweepGradient(colors: [for (var h = 0; h <= 360; h += 30) HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor()]);
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth
        ..shader = sweep.createShader(Rect.fromCircle(center: c, radius: radius)),
    );
    final inner = side / 2 - ringWidth;
    final half = inner * 0.74;
    final box = Rect.fromCenter(center: c, width: half * 2, height: half * 2);
    final rrect = RRect.fromRectAndRadius(box, const Radius.circular(8));
    canvas.drawRRect(rrect, Paint()..shader = LinearGradient(colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()]).createShader(box));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black]).createShader(box),
    );

    final angle = hsv.hue * math.pi / 180;
    final hueDot = c + Offset(math.cos(angle), math.sin(angle)) * radius;
    _marker(canvas, hueDot, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(), ringWidth * 0.62);
    final svDot = Offset(box.left + hsv.saturation * box.width, box.top + (1 - hsv.value) * box.height);
    _marker(canvas, svDot, hsv.toColor(), 11);
  }

  void _marker(Canvas canvas, Offset at, Color fill, double r) {
    canvas.drawCircle(at, r, Paint()..color = fill);
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.hsv != hsv;
}

class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({required this.rgb, required this.value, required this.onChanged, required this.onEnd});
  final int rgb;
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CustomPaint(painter: _CheckerPainter(Color(0xFF000000 | rgb))),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 36,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              key: const ValueKey('opacity-slider'),
              value: value.clamp(0.05, 1.0),
              min: 0.05,
              max: 1,
              onChanged: onChanged,
              onChangeEnd: (_) => onEnd(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 9.0;
    final light = Paint()..color = const Color(0xFFEDEDED), dark = Paint()..color = const Color(0xFF9A9A9A);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), (x + y).isEven ? light : dark);
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..shader = LinearGradient(colors: [color.withValues(alpha: 0.05), color]).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => old.color != color;
}

/// Colours used by the markup screens.
abstract final class MarkupColors {
  static const surface = Color(0xFF1C1C1E);
  static const raised = Color(0xFF2B2B2D);
  static const accent = AppColors.primary;
}

import 'package:flutter/material.dart' hide Text;

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/text.dart';
import '../domain/cv.dart';

/// A small drawing of a CV design in the colour chosen: where the header, the columns and the headings go.
class CvThumb extends StatelessWidget {
  const CvThumb({super.key, required this.design, required this.accent, this.width = 88});
  final CvDesign design;
  final int accent;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 1.414,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.border),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: CustomPaint(painter: _ThumbPainter(design, effectiveAccent(design, accent))),
    ),
  );
}

class _ThumbPainter extends CustomPainter {
  _ThumbPainter(this.d, this.accentInt);
  final CvDesign d;
  final int accentInt;

  static const _grey = Color(0xFFCBD5E1);
  static const _ink = Color(0xFF475569);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final accent = Color(accentInt);
    final soft = Color(tintOf(accentInt, 0.85));
    final deep = Color(shadeOf(accentInt, 0.35));
    final fill = Paint();

    void rect(double x, double y, double rw, double rh, Color c, {double r = 0}) {
      fill.color = c;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x * w, y * h, rw * w, rh * h), Radius.circular(r)), fill);
    }

    void bar(double x, double y, double len, Color c, {double th = 0.012}) => rect(x, y, len, th, c, r: 1);

    void dot(double cx, double cy, double r, Color c) {
      fill.color = c;
      canvas.drawCircle(Offset(cx * w, cy * h), r * w, fill);
    }

    if (d.pageTint) rect(0, 0, 1, 1, Color(tintOf(accentInt, 0.94)));

    // A section title as this design draws it.
    double title(double x, double y, double maxW, {Color? on, bool side = false}) {
      final style = side && d.heading != CvHeading.bar ? CvHeading.underline : d.heading;
      switch (style) {
        case CvHeading.underline:
          bar(x, y, maxW * 0.5, on ?? accent);
          bar(x, y + 0.016, maxW, (on ?? accent).withValues(alpha: 0.5), th: 0.004);
        case CvHeading.caps:
          bar(x, y, maxW * 0.45, on ?? _ink);
          bar(x, y + 0.016, maxW, _grey, th: 0.004);
        case CvHeading.bar:
          rect(x, y - 0.004, 0.012, 0.02, on ?? accent);
          bar(x + 0.025, y, maxW * 0.4, on ?? accent);
        case CvHeading.pill:
          rect(x, y - 0.006, maxW * 0.5, 0.026, accent, r: 4);
        case CvHeading.boxed:
          rect(x, y - 0.006, maxW, 0.026, soft);
          bar(x + 0.02, y + 0.002, maxW * 0.35, accent, th: 0.01);
        case CvHeading.plain:
          bar(x, y, maxW * 0.4, _ink, th: 0.016);
          bar(x, y + 0.02, maxW, _grey, th: 0.004);
      }
      return y + 0.045;
    }

    // A few lines of body text, or entries with a date on the left.
    double lines(double x, double y, double maxW, int count, {Color c = _grey, bool dates = false, bool dots = false}) {
      var yy = y;
      for (var i = 0; i < count; i++) {
        if (dates) {
          bar(x, yy, maxW * 0.2, _grey, th: 0.01);
          bar(x + maxW * 0.26, yy, maxW * 0.5, _ink, th: 0.011);
          bar(x + maxW * 0.26, yy + 0.02, maxW * 0.7, c, th: 0.008);
          yy += 0.05;
        } else {
          bar(x, yy, i == count - 1 ? maxW * 0.6 : maxW, c, th: 0.01);
          yy += 0.022;
        }
      }
      return yy + 0.012;
    }

    double entries(double x, double y, double maxW, int count) {
      var yy = y;
      for (var i = 0; i < count; i++) {
        switch (d.entries) {
          case CvEntries.dateLeft:
            yy = lines(x, yy, maxW, 1, dates: true);
          case CvEntries.inline:
            bar(x, yy, maxW * 0.45, _ink, th: 0.011);
            bar(x + maxW * 0.78, yy, maxW * 0.22, _grey, th: 0.009);
            bar(x, yy + 0.02, maxW * 0.8, _grey, th: 0.008);
            yy += 0.048;
          case CvEntries.timeline:
            rect(x, yy - 0.004, 0.004, 0.06, soft);
            dot(x + 0.002, yy + 0.004, 0.012, accent);
            bar(x + 0.03, yy, maxW * 0.4, accent, th: 0.009);
            bar(x + 0.03, yy + 0.02, maxW * 0.6, _ink, th: 0.011);
            yy += 0.062;
        }
      }
      return yy + 0.006;
    }

    void chips(double x, double y, double maxW, Color c) {
      var cx = x, cy = y;
      for (final f in [0.2, 0.28, 0.16, 0.24]) {
        if (cx + f * maxW > x + maxW) {
          cx = x;
          cy += 0.03;
        }
        rect(cx, cy, f * maxW, 0.022, c, r: 4);
        cx += f * maxW + 0.012;
      }
    }

    void photo(double cx, double cy, double r, {Color? c}) {
      if (!d.hasPhoto) return;
      if (d.photo == CvPhoto.circle) {
        dot(cx, cy, r, c ?? _grey);
      } else {
        rect(cx - r, cy - r * 1.1, r * 2, r * 2.2, c ?? _grey, r: 3);
      }
    }

    const m = 0.08;
    double top = 0.05;

    if (d.isSidebar) {
      final left = d.layout == CvLayout.sidebarLeft;
      const sw = 0.34;
      final sideColor = switch (d.sidebar) {
        CvSidebar.accent => accent,
        CvSidebar.dark => const Color(0xFF1F2937),
        CvSidebar.tint => Color(tintOf(accentInt, 0.9)),
      };
      final onSide = d.sidebar == CvSidebar.tint ? _ink : Colors.white;
      final sx = left ? 0.0 : 1 - sw;
      rect(sx, 0, sw, 1, sideColor);
      photo(sx + sw / 2, 0.13, 0.11, c: d.sidebar == CvSidebar.tint ? _grey : Colors.white.withValues(alpha: 0.7));
      var y = 0.27;
      for (var i = 0; i < 3; i++) {
        y = title(sx + 0.04, y, sw - 0.08, on: d.sidebar == CvSidebar.tint ? accent : onSide, side: true);
        if (i == 2 && d.skills == CvSkills.chips) {
          chips(sx + 0.04, y, sw - 0.08, onSide.withValues(alpha: 0.25));
          y += 0.07;
        } else if (i == 1 && d.levelBars) {
          for (var k = 0; k < 3; k++) {
            bar(sx + 0.04, y, sw - 0.08, onSide.withValues(alpha: 0.25), th: 0.008);
            bar(sx + 0.04, y, (sw - 0.08) * (0.9 - k * 0.2), onSide.withValues(alpha: 0.85), th: 0.008);
            y += 0.026;
          }
        } else {
          y = lines(sx + 0.04, y, sw - 0.08, 3, c: onSide.withValues(alpha: 0.55));
        }
      }
      final mx = left ? sw + 0.07 : 0.07;
      final mw = 1 - sw - 0.14;
      bar(mx, 0.07, mw * 0.7, _ink, th: 0.028);
      bar(mx, 0.115, mw * 0.4, accent, th: 0.012);
      var my = 0.16;
      my = title(mx, my, mw);
      my = lines(mx, my, mw, 2);
      my = title(mx, my, mw);
      my = entries(mx, my, mw, 2);
      my = title(mx, my, mw);
      entries(mx, my, mw, 1);
      return;
    }

    // Headers
    switch (d.header) {
      case CvHeader.plain:
        bar(m, top + 0.01, 0.4, _ink, th: 0.028);
        bar(m, top + 0.055, 0.25, accent, th: 0.012);
        if (d.layout != CvLayout.table) bar(m, top + 0.085, 0.6, _grey, th: 0.009);
        if (d.layout != CvLayout.twoColumn) photo(1 - m - 0.09, top + 0.05, 0.075);
        top += 0.14;
      case CvHeader.centered:
        bar(0.3, top + 0.01, 0.4, _ink, th: 0.028);
        bar(0.38, top + 0.055, 0.24, accent, th: 0.012);
        bar(0.2, top + 0.085, 0.6, _grey, th: 0.009);
        bar(m, top + 0.108, 1 - 2 * m, accent, th: 0.005);
        top += 0.14;
      case CvHeader.band:
        rect(m, top, 1 - 2 * m, 0.14, accent);
        bar(m + 0.04, top + 0.035, 0.38, Colors.white, th: 0.026);
        bar(m + 0.04, top + 0.075, 0.25, Colors.white.withValues(alpha: 0.7), th: 0.011);
        bar(m + 0.04, top + 0.1, 0.5, Colors.white.withValues(alpha: 0.7), th: 0.008);
        photo(1 - m - 0.1, top + 0.07, 0.055, c: Colors.white.withValues(alpha: 0.7));
        top += 0.17;
      case CvHeader.banner:
        rect(m, top, 1 - 2 * m, 0.2, accent);
        rect(m, top + 0.2, 1 - 2 * m, 0.012, deep);
        bar(m + 0.04, top + 0.06, 0.4, Colors.white, th: 0.032);
        bar(m + 0.04, top + 0.115, 0.25, Colors.white.withValues(alpha: 0.7), th: 0.012);
        bar(m + 0.04, top + 0.15, 0.5, Colors.white.withValues(alpha: 0.7), th: 0.008);
        photo(1 - m - 0.13, top + 0.1, 0.08, c: Colors.white.withValues(alpha: 0.85));
        top += 0.24;
      case CvHeader.twoTone:
        rect(m, top, 1 - 2 * m, 0.11, accent);
        rect(m, top + 0.11, 1 - 2 * m, 0.04, deep);
        bar(m + 0.04, top + 0.03, 0.38, Colors.white, th: 0.026);
        bar(m + 0.04, top + 0.07, 0.25, Colors.white.withValues(alpha: 0.7), th: 0.01);
        bar(m + 0.04, top + 0.125, 0.5, Colors.white.withValues(alpha: 0.7), th: 0.008);
        photo(1 - m - 0.09, top + 0.055, 0.045, c: Colors.white.withValues(alpha: 0.7));
        top += 0.19;
      case CvHeader.bigName:
        bar(m, top + 0.01, 0.55, accent, th: 0.04);
        bar(m, top + 0.065, 0.3, _ink, th: 0.012);
        rect(m, top + 0.09, 1 - 2 * m, 0.012, accent);
        bar(m, top + 0.115, 0.6, _grey, th: 0.009);
        photo(1 - m - 0.08, top + 0.05, 0.065);
        top += 0.15;
    }

    // Body
    switch (d.layout) {
      case CvLayout.single:
        var y = top;
        y = title(m, y, 1 - 2 * m);
        y = lines(m, y, 1 - 2 * m, 2);
        y = title(m, y, 1 - 2 * m);
        y = entries(m, y, 1 - 2 * m, 2);
        y = title(m, y, 1 - 2 * m);
        y = entries(m, y, 1 - 2 * m, 1);
        y = title(m, y, 1 - 2 * m);
        if (d.skills == CvSkills.chips) {
          chips(m, y, 1 - 2 * m, soft);
        } else {
          lines(m, y, 1 - 2 * m, 1);
        }
      case CvLayout.twoColumn:
        const lw = 0.26;
        final rx = m + lw + 0.05, rw = 1 - rx - m;
        var ly = top;
        if (d.header == CvHeader.plain) {
          photo(m + lw / 2, ly + 0.07, 0.07);
          ly += 0.16;
        }
        ly = title(m, ly, lw);
        ly = lines(m, ly, lw, 3);
        ly = title(m, ly, lw);
        if (d.levelBars) {
          for (var k = 0; k < 3; k++) {
            bar(m, ly, lw, _grey, th: 0.008);
            bar(m, ly, lw * (0.9 - k * 0.2), accent, th: 0.008);
            ly += 0.026;
          }
          ly += 0.02;
        } else {
          ly = lines(m, ly, lw, 2);
        }
        ly = title(m, ly, lw);
        if (d.skills == CvSkills.chips) {
          chips(m, ly, lw, soft);
        } else {
          lines(m, ly, lw, 3);
        }
        var ry = top;
        ry = title(rx, ry, rw);
        ry = lines(rx, ry, rw, 2);
        ry = title(rx, ry, rw);
        ry = entries(rx, ry, rw, 2);
        ry = title(rx, ry, rw);
        entries(rx, ry, rw, 1);
      case CvLayout.table:
        var y = top;
        y = title(m, y, 1 - 2 * m);
        for (var i = 0; i < 4; i++) {
          bar(m, y, 0.18, _grey, th: 0.009);
          bar(m + 0.26, y, 0.4, _ink, th: 0.009);
          y += 0.026;
        }
        y = title(m, y + 0.01, 1 - 2 * m);
        y = entries(m, y, 1 - 2 * m, 2);
        y = title(m, y, 1 - 2 * m);
        entries(m, y, 1 - 2 * m, 1);
      case CvLayout.sidebarLeft || CvLayout.sidebarRight:
        break;
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) => old.d.id != d.id || old.accentInt != accentInt;
}

/// The designs to choose from, in two groups, each shown as a small drawing with its name, and the colour to use.
class CvDesignPicker extends StatelessWidget {
  const CvDesignPicker({super.key, required this.selected, required this.accent, required this.onDesign, required this.onAccent});
  final String selected;
  final int accent;
  final ValueChanged<String> onDesign;
  final ValueChanged<int> onAccent;

  @override
  Widget build(BuildContext context) {
    final current = cvDesignOf(selected);
    Widget group(String title, CvGroup g) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
          child: Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkMuted),
          ),
        ),
        Wrap(
          spacing: AppSpacing.sm + 2,
          runSpacing: AppSpacing.md,
          children: [
            for (final d in cvDesigns.where((x) => x.group == g))
              Semantics(
                button: true,
                selected: d.id == selected,
                label: tr(d.name),
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey('template-${d.id}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onDesign(d.id),
                  child: SizedBox(
                    width: 92,
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: d.id == selected ? AppColors.primary : Colors.transparent, width: 2.5),
                              ),
                              child: CvThumb(design: d, accent: accent),
                            ),
                            if (d.id == selected)
                              const PositionedDirectional(
                                top: 4,
                                end: 4,
                                child: CircleAvatar(
                                  radius: 9,
                                  backgroundColor: AppColors.primary,
                                  child: Icon(AppIcons.check, size: 12, color: Colors.white),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: d.id == selected ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group('Plain and professional', CvGroup.plain),
        group('Colourful', CvGroup.colourful),
        const SizedBox(height: AppSpacing.md),
        Container(
          key: const ValueKey('design-hint'),
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.sm + 4),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${tr(current.name)}: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: tr(current.hint)),
                if (!current.personal) TextSpan(text: ' ${tr('The birth date and nationality are left out.')}'),
              ],
            ),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(tr('Colour'), style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
        const SizedBox(height: 6),
        if (current.mono)
          const Text(
            'This design is black and white, so it has no colour to choose.',
            key: ValueKey('mono-note'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          )
        else
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final c in cvAccents)
                Semantics(
                  button: true,
                  selected: accent == c,
                  label: tr('Colour'),
                  child: InkResponse(
                    key: ValueKey('accent-$c'),
                    onTap: () => onAccent(c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: accent == c ? AppColors.ink : Colors.transparent, width: 2.5),
                      ),
                      child: accent == c ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

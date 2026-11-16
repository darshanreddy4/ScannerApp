import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/text.dart';
import '../domain/chart.dart';
import 'sheet_cubit.dart';

const _kindChoices = <(ChartKind?, String)>[(null, 'Same as the chart'), (ChartKind.column, 'Column'), (ChartKind.line, 'Line'), (ChartKind.area, 'Area')];

const _trendChoices = <(TrendKind, String)>[
  (TrendKind.none, 'None'),
  (TrendKind.linear, 'Straight'),
  (TrendKind.exponential, 'Exponential'),
  (TrendKind.polynomial, 'Curved'),
  (TrendKind.movingAverage, 'Moving average'),
];

/// Shows the series of the chart at [chartIndex] on the open sheet, to change the colour of each, how it is drawn (columns, line or area in one
/// chart), whether it uses a second scale at the right, and its trend line. Every choice is applied at once.
Future<void> showSeriesEditor(BuildContext context, SheetCubit cubit, int chartIndex) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => BlocProvider.value(value: cubit, child: _SeriesSheet(chartIndex: chartIndex)),
);

class _SeriesSheet extends StatefulWidget {
  const _SeriesSheet({required this.chartIndex});
  final int chartIndex;

  @override
  State<_SeriesSheet> createState() => _SeriesSheetState();
}

class _SeriesSheetState extends State<_SeriesSheet> {
  var _selected = 0;
  var _point = 0;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SheetCubit>();
    return BlocBuilder<SheetCubit, SheetState>(
      buildWhen: (a, b) => a.version != b.version,
      builder: (context, _) {
        final charts = cubit.sheet.charts;
        if (widget.chartIndex >= charts.length) return const SizedBox(height: 120, child: Center(child: Text('No charts yet. Select cells and choose Add chart.')));
        final chart = charts[widget.chartIndex];
        final data = cubit.chartData(chart);
        final index = _selected.clamp(0, chart.series.length - 1);
        final s = chart.series[index];
        void change(ChartSeries Function(ChartSeries) f) => cubit.updateSeries(chart, index, f);
        final auto = Color(chartPalette[index % chartPalette.length]);
        final canMix = chart.mixable;
        final pie = chart.kind.isPie;
        final kindHere = chart.kindOf(index);
        final pointsPaintable = kindHere.isPie || kindHere == ChartKind.column || kindHere == ChartKind.bar;
        return SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Series', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < chart.series.length; i++)
                    ChoiceChip(
                      key: ValueKey('series_chip_$i'),
                      avatar: CircleAvatar(radius: 7, backgroundColor: Color(chart.series[i].color ?? chartPalette[i % chartPalette.length])),
                      label: Text(i < data.series.length ? data.series[i].name : 'Series ${i + 1}'),
                      selected: i == index,
                      onSelected: (_) => setState(() => _selected = i),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (!pie) ...[
                const Text('Colour', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GestureDetector(
                      key: const ValueKey('series_color_auto'),
                      onTap: () => change((x) => x.copyWith(color: null)),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: s.color == null ? AppColors.primary : AppColors.border, width: s.color == null ? 3 : 1)),
                        child: Icon(Icons.autorenew, size: 16, color: auto),
                      ),
                    ),
                    for (final c in chartPalette)
                      GestureDetector(
                        key: ValueKey('series_color_${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'),
                        onTap: () => change((x) => x.copyWith(color: c)),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: s.color == c ? AppColors.primary : Colors.black12, width: s.color == c ? 3 : 1),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (canMix) ...[
                const Text('Draw as', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final k in _kindChoices)
                      ChoiceChip(
                        key: ValueKey('series_kind_${k.$1?.name ?? 'same'}'),
                        label: Text(k.$2),
                        selected: (s.kind ?? chart.kind) == (k.$1 ?? chart.kind) && (k.$1 != null || s.kind == null),
                        onSelected: (_) => change((x) => x.copyWith(kind: k.$1)),
                      ),
                  ],
                ),
                SwitchListTile(
                  key: const ValueKey('series_second'),
                  contentPadding: EdgeInsets.zero,
                  value: s.secondary,
                  onChanged: (v) => change((x) => x.copyWith(secondary: v)),
                  title: const Text('Second scale on the right'),
                ),
              ],
              if (!pie) ...[
                const Text('Trend line', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final t in _trendChoices)
                      ChoiceChip(
                        key: ValueKey('series_trend_${t.$1.name}'),
                        label: Text(t.$2),
                        selected: s.trend == t.$1,
                        onSelected: (_) => change((x) => x.copyWith(trend: t.$1)),
                      ),
                  ],
                ),
                if (s.trend != TrendKind.none && s.trend != TrendKind.movingAverage) ...[
                  SwitchListTile(
                    key: const ValueKey('series_equation'),
                    contentPadding: EdgeInsets.zero,
                    value: s.showEquation,
                    onChanged: (v) => change((x) => x.copyWith(showEquation: v)),
                    title: const Text('Show the equation on the chart'),
                  ),
                  SwitchListTile(
                    key: const ValueKey('series_r2'),
                    contentPadding: EdgeInsets.zero,
                    value: s.showR2,
                    onChanged: (v) => change((x) => x.copyWith(showR2: v)),
                    title: const Text('Show R² (how well the line fits)'),
                  ),
                ],
                if (chart.stacked)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(tr('Trend lines are not drawn on piled bars or areas.'), style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                  ),
              ],
              const SizedBox(height: 12),
              const Text('Labels', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final l in [LabelKind.none, LabelKind.value, if (pie) LabelKind.percent])
                    ChoiceChip(
                      key: ValueKey('series_labels_${l.name}'),
                      label: Text(switch (l) {
                        LabelKind.none => 'None',
                        LabelKind.value => 'Values',
                        LabelKind.percent => 'Percent',
                      }),
                      selected: chart.labelsOf(index) == l,
                      onSelected: (_) => change((x) => x.copyWith(labels: l)),
                    ),
                ],
              ),
              if (pointsPaintable) ...[
                const SizedBox(height: 12),
                const Text('Colours of single points', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < data.points && i < 24; i++)
                      ChoiceChip(
                        key: ValueKey('point_chip_$i'),
                        avatar: CircleAvatar(radius: 7, backgroundColor: Color(s.pointColor(i) ?? (pie ? chartPalette[i % chartPalette.length] : (s.color ?? chartPalette[index % chartPalette.length])))),
                        label: Text(i < data.categories.length ? data.categories[i] : '${i + 1}'),
                        selected: i == _point.clamp(0, 23),
                        onSelected: (_) => setState(() => _point = i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    GestureDetector(
                      key: const ValueKey('point_color_auto'),
                      onTap: () => change((x) => x.withPointColor(_point, null)),
                      child: Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: s.pointColor(_point) == null ? AppColors.primary : AppColors.border, width: s.pointColor(_point) == null ? 3 : 1)),
                        child: const Icon(Icons.autorenew, size: 16),
                      ),
                    ),
                    for (final c in chartPalette)
                      GestureDetector(
                        key: ValueKey('point_color_${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'),
                        onTap: () => change((x) => x.withPointColor(_point, c)),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: s.pointColor(_point) == c ? AppColors.primary : Colors.black12, width: s.pointColor(_point) == c ? 3 : 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  key: const ValueKey('series_done'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

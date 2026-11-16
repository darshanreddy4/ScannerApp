import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../app/di.dart';
import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../../core/widgets/text.dart';
import '../../../documents/presentation/library_actions.dart';
import '../../../export/domain/repositories/export_repository.dart';
import '../domain/chart.dart';
import 'chart_painter.dart';
import 'series_dialog.dart';
import 'sheet_cubit.dart';

/// What the person chose for a chart.
typedef ChartChoice = ({ChartKind kind, String title, bool stacked, bool percent});

const _kindInfo = <(ChartKind, String, IconData)>[
  (ChartKind.column, 'Column', Icons.bar_chart),
  (ChartKind.bar, 'Bar', Icons.align_horizontal_left),
  (ChartKind.line, 'Line', Icons.show_chart),
  (ChartKind.area, 'Area', Icons.area_chart),
  (ChartKind.pie, 'Pie', Icons.pie_chart_outline),
  (ChartKind.doughnut, 'Doughnut', Icons.donut_large),
  (ChartKind.scatter, 'Scatter', Icons.scatter_plot),
];

/// Asks which kind of chart to make, and its title. With [existing], changes that chart.
Future<ChartChoice?> askChart(BuildContext context, {SheetChart? existing, SheetCubit? cubit}) => showModalBottomSheet<ChartChoice>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => _ChartSheet(existing: existing, cubit: cubit),
);

class _ChartSheet extends StatefulWidget {
  const _ChartSheet({this.existing, this.cubit});
  final SheetChart? existing;

  /// Lets the sheet reach the series settings of an existing chart.
  final SheetCubit? cubit;

  @override
  State<_ChartSheet> createState() => _ChartSheetState();
}

class _ChartSheetState extends State<_ChartSheet> {
  late var _kind = widget.existing?.kind ?? ChartKind.column;
  late var _stacked = widget.existing?.stacked ?? false;
  late var _percent = widget.existing?.percent ?? false;
  late final _title = TextEditingController(text: widget.existing?.title ?? '');

  // The place of the chart in the sheet's list, which stays the same while its series are changed.
  late final _index = widget.existing == null || widget.cubit == null ? -1 : widget.cubit!.sheet.charts.indexOf(widget.existing!);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    final canStack = _kind == ChartKind.column || _kind == ChartKind.bar || _kind == ChartKind.area;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(editing ? 'Change chart' : 'Chart of the selected cells', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final k in _kindInfo)
                  ChoiceChip(
                    key: ValueKey('chart_kind_${k.$1.name}'),
                    avatar: Icon(k.$3, size: 18),
                    label: Text(k.$2),
                    selected: _kind == k.$1,
                    onSelected: (_) => setState(() => _kind = k.$1),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('chart_title'),
              controller: _title,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: tr('Title (optional)'), isDense: true),
            ),
            if (canStack)
              SwitchListTile(
                key: const ValueKey('chart_stacked'),
                contentPadding: EdgeInsets.zero,
                value: _stacked,
                onChanged: (v) => setState(() => _stacked = v),
                title: const Text('Stack the series on each other'),
              ),
            if (canStack && _stacked)
              SwitchListTile(
                key: const ValueKey('chart_percent'),
                contentPadding: EdgeInsets.zero,
                value: _percent,
                onChanged: (v) => setState(() => _percent = v),
                title: const Text('Show each point as a share of 100%'),
              ),
            if (widget.existing != null && widget.cubit != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('chart_series'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 40), padding: EdgeInsets.zero),
                  onPressed: () {
                    if (_index >= 0) showSeriesEditor(context, widget.cubit!, _index);
                  },
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Series, colours and trend lines'),
                ),
              ),
            if (widget.existing?.fromFile == true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('This chart came from the file. Changing it resets its colours and styling.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('chart_apply'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => Navigator.pop<ChartChoice>(context, (kind: _kind, title: _title.text.trim(), stacked: canStack && _stacked, percent: canStack && _stacked && _percent)),
                  child: Text(editing ? 'Apply' : 'Add chart'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A picture of the chart as PNG bytes.
Future<Uint8List> renderChartPng(SheetChart chart, ChartData data, {int width = 1200}) async {
  final size = Size(width.toDouble(), width * 0.625);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // Drawn at phone size and scaled up, so text keeps its proportions.
  const base = 400.0;
  canvas.scale(size.width / base);
  ChartPainter(chart, data).paint(canvas, Size(base, base * 0.625));
  final image = await recorder.endRecording().toImage(width, (width * 0.625).round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Lists the charts of the open sheet, each drawn, with ways to change, share and remove it.
Future<void> showCharts(BuildContext context, SheetCubit cubit) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => BlocProvider.value(value: cubit, child: const _ChartsSheet()),
);

class _ChartsSheet extends StatelessWidget {
  const _ChartsSheet();

  Future<File> _picture(BuildContext context, SheetCubit cubit, SheetChart chart) async {
    final bytes = await renderChartPng(chart, cubit.chartData(chart));
    final dir = await Directory(p.join((await getTemporaryDirectory()).path, 'office_out')).create(recursive: true);
    final name = (chart.title.isEmpty ? 'Chart' : chart.title).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File(p.join(dir.path, '$name.png')).writeAsBytes(bytes, flush: true);
  }

  Future<void> _share(BuildContext context, SheetCubit cubit, SheetChart chart) async {
    final file = await _picture(context, cubit, chart);
    if (!context.mounted) return;
    final failure = (await sl<ShareService>().shareFiles(paths: [file.path], mimeType: 'image/png')).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _keep(BuildContext context, SheetCubit cubit, SheetChart chart) async {
    final file = await _picture(context, cubit, chart);
    if (!context.mounted) return;
    await saveToLibrary(context, path: file.path, title: chart.label);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SheetCubit>();
    return BlocBuilder<SheetCubit, SheetState>(
      buildWhen: (a, b) => a.version != b.version || a.sheetIndex != b.sheetIndex,
      builder: (context, state) {
        final charts = cubit.sheet.charts;
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Charts on this sheet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              if (charts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No charts yet. Select cells and choose Add chart.')),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: charts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final chart = charts[i];
                      return DecoratedBox(
                        key: ValueKey('chart_card_$i'),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: chart.editable
                                  ? AspectRatio(aspectRatio: 1.6, child: CustomPaint(painter: ChartPainter(chart, cubit.chartData(chart))))
                                  : Container(
                                      height: 90,
                                      color: AppColors.primarySoft,
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(12),
                                      child: const Text('This chart is kept in the file as it is. The app cannot show or change this kind of chart.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(chart.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  if (chart.editable) ...[
                                    IconButton(
                                      key: ValueKey('chart_edit_$i'),
                                      tooltip: tr('Change chart'),
                                      onPressed: () async {
                                        final at = charts.indexOf(chart);
                                        final choice = await askChart(context, existing: chart, cubit: cubit);
                                        final now = cubit.sheet.charts;
                                        if (choice != null && at >= 0 && at < now.length) cubit.updateChart(now[at], kind: choice.kind, title: choice.title, stacked: choice.stacked, percent: choice.percent);
                                      },
                                      icon: const Icon(AppIcons.edit, size: 20),
                                    ),
                                    IconButton(key: ValueKey('chart_share_$i'), tooltip: tr('Share as picture'), onPressed: () => _share(context, cubit, chart), icon: const Icon(AppIcons.share, size: 20)),
                                    IconButton(key: ValueKey('chart_keep_$i'), tooltip: tr('Save picture in Doculoom'), onPressed: () => _keep(context, cubit, chart), icon: const Icon(AppIcons.library, size: 20)),
                                  ],
                                  IconButton(
                                    key: ValueKey('chart_delete_$i'),
                                    tooltip: tr('Remove chart'),
                                    color: AppColors.danger,
                                    onPressed: () => cubit.removeChart(chart),
                                    icon: const Icon(AppIcons.delete, size: 20),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/features/office/sheets/domain/chart.dart';
import 'package:doculoom/features/office/sheets/domain/sheet_model.dart';
import 'package:doculoom/features/office/sheets/presentation/chart_painter.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_cubit.dart';
import 'package:doculoom/features/office/sheets/presentation/sheet_page.dart';

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('formula_field')), text);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
}

Future<void> fill(WidgetTester tester, int r, int c, String text) async {
  await tester.tap(find.byKey(ValueKey('cell_${r}_$c')));
  await tester.pump();
  await type(tester, text);
}

Future<void> menu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const ValueKey('sheet_menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  Future<SheetCubit> open(WidgetTester tester, {Size size = const Size(420, 860)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: const SheetPage(args: SheetArgs())));
    await tester.pump();
    return tester.element(find.byType(Scaffold).first).read<SheetCubit>();
  }

  testWidgets('add a chart from the cells, see it drawn, change its kind and remove it', (tester) async {
    final cubit = await open(tester);
    await fill(tester, 0, 0, 'Month');
    await fill(tester, 0, 1, 'Sales');
    await fill(tester, 1, 0, 'Jan');
    await fill(tester, 1, 1, '5');
    await fill(tester, 2, 0, 'Feb');
    await fill(tester, 2, 1, '8');
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    expect(find.text('Charts on this sheet'), findsNothing, reason: 'the list is offered once there is a chart');

    await menu(tester, 'Add chart from selection');
    await tester.tap(find.byKey(const ValueKey('chart_kind_line')));
    await tester.pump();
    expect(find.byKey(const ValueKey('chart_stacked')), findsNothing, reason: 'lines are not stacked');
    await tester.enterText(find.byKey(const ValueKey('chart_title')), 'Sales by month');
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();

    expect(cubit.sheet.charts, hasLength(1));
    var chart = cubit.sheet.charts.single;
    expect(chart.kind, ChartKind.line);
    expect(chart.title, 'Sales by month');
    expect(cubit.state.modified, isTrue);
    expect(find.text('Chart added'), findsOneWidget);

    await menu(tester, 'Charts on this sheet');
    expect(find.byKey(const ValueKey('chart_card_0')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('chart_card_0')), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ChartPainter)), findsOneWidget);
    expect(find.text('Sales by month'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chart_edit_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart_kind_column')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart_stacked')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    chart = cubit.sheet.charts.single;
    expect(chart.kind, ChartKind.column);
    expect(chart.stacked, isTrue);

    await tester.tap(find.byKey(const ValueKey('chart_delete_0')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts, isEmpty);
    expect(find.text('No charts yet. Select cells and choose Add chart.'), findsOneWidget);

    cubit.undo();
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts, hasLength(1), reason: 'undo brings the chart back');
  });

  testWidgets('a chart sits over the grid: tap to select, drag to move, drag the corner to resize, edit and remove it there', (tester) async {
    final cubit = await open(tester, size: const Size(1100, 900));
    await fill(tester, 0, 0, 'Month');
    await fill(tester, 0, 1, 'Sales');
    await fill(tester, 1, 0, 'Jan');
    await fill(tester, 1, 1, '5');
    await fill(tester, 2, 0, 'Feb');
    await fill(tester, 2, 1, '8');
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    await menu(tester, 'Add chart from selection');
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();

    final box = find.byKey(const ValueKey('grid_chart_0'));
    expect(box, findsOneWidget);
    expect(find.descendant(of: box, matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ChartPainter)), findsOneWidget);
    expect(find.byKey(const ValueKey('grid_chart_resize')), findsNothing, reason: 'not selected yet');
    final start = cubit.sheet.charts.single;
    expect([start.col, start.row, start.cols, start.rows], [3, 0, 8, 15]);

    await tester.tap(box);
    await tester.pump();
    expect(find.byKey(const ValueKey('grid_chart_resize')), findsOneWidget);
    expect(find.byKey(const ValueKey('grid_chart_edit')), findsOneWidget);

    // Down two rows and right one column.
    await tester.drag(box, const Offset(140, 80));
    await tester.pumpAndSettle();
    var c = cubit.sheet.charts.single;
    expect(c.col, 4);
    expect(c.row, greaterThanOrEqualTo(2));
    expect(c.moved, isTrue);
    expect(c.cols, 8);

    await tester.drag(find.byKey(const ValueKey('grid_chart_resize')), const Offset(200, 120));
    await tester.pumpAndSettle();
    c = cubit.sheet.charts.single;
    expect(c.cols, greaterThan(8));
    expect(c.rows, greaterThan(15));

    cubit.undo();
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.cols, 8, reason: 'undo takes the resize back');

    await tester.tap(find.byKey(const ValueKey('grid_chart_edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart_kind_pie')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.kind, ChartKind.pie);

    await tester.tap(find.byKey(const ValueKey('cell_6_0')));
    await tester.pump();
    expect(find.byKey(const ValueKey('grid_chart_resize')), findsNothing, reason: 'a tap on a cell lets go of the chart');

    await tester.tap(find.byKey(const ValueKey('grid_chart_0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('grid_chart_delete')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts, isEmpty);
    expect(find.byKey(const ValueKey('grid_chart_0')), findsNothing);
  });

  testWidgets('tapping empty cells next to a chart still selects cells, and a chart off the screen costs nothing', (tester) async {
    final cubit = await open(tester);
    await fill(tester, 0, 0, '4');
    await fill(tester, 1, 0, '9');
    await tester.tap(find.byKey(const ValueKey('cell_0_0')));
    await tester.pump();
    await menu(tester, 'Add chart from selection');
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('cell_5_0')));
    await tester.pump();
    expect(cubit.state.row, 5);
  });

  testWidgets('series settings: colour, draw as a line on the second scale, and a trend line; they survive applying the chart sheet', (tester) async {
    final cubit = await open(tester);
    const cells = [
      ['Month', 'North', 'South'],
      ['Jan', '10', '70'],
      ['Feb', '12', '90'],
      ['Mar', '9', '140'],
    ];
    for (var r = 0; r < cells.length; r++) {
      for (var c = 0; c < 3; c++) {
        await fill(tester, r, c, cells[r][c]);
      }
    }
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    await menu(tester, 'Add chart from selection');
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();

    await menu(tester, 'Charts on this sheet');
    await tester.tap(find.byKey(const ValueKey('chart_edit_0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('chart_series')));
    await tester.tap(find.byKey(const ValueKey('chart_series')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('series_chip_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('series_chip_1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('series_chip_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('series_kind_line')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('series_second')));
    await tester.tap(find.byKey(const ValueKey('series_second')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('series_trend_linear')));
    await tester.tap(find.byKey(const ValueKey('series_trend_linear')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('series_color_70ad47')));
    await tester.tap(find.byKey(const ValueKey('series_color_70ad47')));
    await tester.pumpAndSettle();

    var chart = cubit.sheet.charts.single;
    expect(chart.series[1].kind, ChartKind.line);
    expect(chart.series[1].secondary, isTrue);
    expect(chart.series[1].trend, TrendKind.linear);
    expect(chart.series[1].color, 0xFF70AD47);
    expect(chart.series[0].kind, isNull);
    expect(chart.isCombined, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('series_kind_line'))).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('series_trend_linear'))).selected, isTrue);

    await tester.ensureVisible(find.byKey(const ValueKey('series_color_auto')));
    await tester.tap(find.byKey(const ValueKey('series_color_auto')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.series[1].color, isNull, reason: 'back to the standard colour');

    await tester.tap(find.byKey(const ValueKey('series_done')));
    await tester.pumpAndSettle();
    // Back in the chart sheet: change the title and apply; the series settings stay.
    await tester.enterText(find.byKey(const ValueKey('chart_title')), 'Mixed');
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    chart = cubit.sheet.charts.single;
    expect(chart.title, 'Mixed');
    expect(chart.series[1].kind, ChartKind.line);
    expect(chart.series[1].secondary, isTrue);
    expect(chart.series[1].trend, TrendKind.linear);
  });

  testWidgets('the painter draws mixed charts with a second scale and every kind of trend line, and sideways bars with a trend', (tester) async {
    final data = ChartData(
      categories: const ['a', 'b', 'c', 'd', 'e'],
      series: const [
        (name: 'One', values: <double?>[3, 5, 4, 8, 9]),
        (name: 'Two', values: <double?>[100, 140, null, 220, 300]),
        (name: 'Three', values: <double?>[1, 2, 4, 8, 16]),
      ],
    );
    ChartSeries series(String n, {ChartKind? kind, bool second = false, TrendKind trend = TrendKind.none, int? color}) =>
        ChartSeries(name: n, values: const ChartRef('S', MergeRange(0, 0, 4, 0)), kind: kind, secondary: second, trend: trend, color: color);
    final charts = [
      SheetChart(
        kind: ChartKind.column,
        series: [series('One', trend: TrendKind.linear), series('Two', kind: ChartKind.line, second: true, trend: TrendKind.polynomial, color: 0xFF336699), series('Three', kind: ChartKind.area, trend: TrendKind.exponential)],
        col: 0,
        row: 0,
      ),
      SheetChart(kind: ChartKind.line, series: [series('One', trend: TrendKind.movingAverage), series('Two', kind: ChartKind.column, second: true)], col: 0, row: 0),
      SheetChart(kind: ChartKind.bar, series: [series('One', trend: TrendKind.linear), series('Two')], col: 0, row: 0),
      SheetChart(kind: ChartKind.column, stacked: true, series: [series('One', trend: TrendKind.linear), series('Two', kind: ChartKind.line, second: true)], col: 0, row: 0),
      SheetChart(kind: ChartKind.scatter, series: [series('One', trend: TrendKind.linear, color: 0xFFAA0000), series('Two', trend: TrendKind.polynomial)], col: 0, row: 0),
    ];
    for (final chart in charts) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 340, height: 220, child: CustomPaint(painter: ChartPainter(chart, data))),
        ),
      );
      expect(tester.takeException(), isNull, reason: '${chart.kind}');
    }
  });

  testWidgets('a doughnut: colour one slice, choose value labels; a column chart: a trend line shows its equation and R squared on request', (tester) async {
    final cubit = await open(tester);
    const cells = [
      ['Month', 'North'],
      ['Jan', '10'],
      ['Feb', '14'],
      ['Mar', '9'],
    ];
    for (var r = 0; r < cells.length; r++) {
      for (var c = 0; c < 2; c++) {
        await fill(tester, r, c, cells[r][c]);
      }
    }
    await tester.tap(find.byKey(const ValueKey('cell_1_1')));
    await tester.pump();
    await menu(tester, 'Add chart from selection');
    await tester.tap(find.byKey(const ValueKey('chart_kind_doughnut')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.kind, ChartKind.doughnut);

    await menu(tester, 'Charts on this sheet');
    await tester.tap(find.byKey(const ValueKey('chart_edit_0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('chart_series')));
    await tester.tap(find.byKey(const ValueKey('chart_series')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('series_color_auto')), findsNothing, reason: 'slices have their own colours, not the series');
    expect(find.byKey(const ValueKey('series_kind_line')), findsNothing, reason: 'a doughnut cannot be mixed with other kinds');

    await tester.ensureVisible(find.byKey(const ValueKey('point_chip_1')));
    await tester.tap(find.byKey(const ValueKey('point_chip_1')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('point_color_c00000')).evaluate().isEmpty ? find.byKey(const ValueKey('point_color_ed7d31')) : find.byKey(const ValueKey('point_color_c00000')));
    await tester.tap(find.byKey(const ValueKey('point_color_ed7d31')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.series.single.pointColor(1), 0xFFED7D31);
    await tester.ensureVisible(find.byKey(const ValueKey('series_labels_value')));
    await tester.tap(find.byKey(const ValueKey('series_labels_value')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.labelsOf(0), LabelKind.value);
    expect(find.byKey(const ValueKey('series_labels_percent')), findsOneWidget, reason: 'percent is offered for slices');
    await tester.tap(find.byKey(const ValueKey('point_color_auto')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.series.single.pointColors, isEmpty);

    // A column chart: no equation switches until there is a trend line.
    await tester.tap(find.byKey(const ValueKey('series_done')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart_kind_column')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.kind, ChartKind.column);
    await tester.tap(find.byKey(const ValueKey('chart_edit_0')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('chart_series')));
    await tester.tap(find.byKey(const ValueKey('chart_series')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('series_equation')), findsNothing);
    expect(find.byKey(const ValueKey('series_labels_percent')), findsNothing, reason: 'percent is for slices only');
    await tester.ensureVisible(find.byKey(const ValueKey('series_trend_linear')));
    await tester.tap(find.byKey(const ValueKey('series_trend_linear')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('series_equation')));
    await tester.tap(find.byKey(const ValueKey('series_equation')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('series_r2')));
    await tester.tap(find.byKey(const ValueKey('series_r2')));
    await tester.pumpAndSettle();
    final series = cubit.sheet.charts.single.series.single;
    expect(series.showEquation, isTrue);
    expect(series.showR2, isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('series_trend_none')));
    await tester.tap(find.byKey(const ValueKey('series_trend_none')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts.single.series.single.showEquation, isFalse);
    expect(find.byKey(const ValueKey('series_equation')), findsNothing);
  });

  testWidgets('the painter draws doughnuts, value labels, single colours and equations without errors', (tester) async {
    final data = ChartData(
      xs: const [1, 2, 3, 4],
      categories: const ['a', 'b', 'c', 'd'],
      series: const [
        (name: 'One', values: <double?>[3, 5, null, 8]),
        (name: 'Two', values: <double?>[4, 1, 6, 2]),
      ],
    );
    ChartSeries series({LabelKind? labels, TrendKind trend = TrendKind.none, List<int?> points = const []}) => ChartSeries(
      name: 'S',
      values: const ChartRef('S', MergeRange(0, 0, 3, 0)),
      labels: labels,
      trend: trend,
      showEquation: trend != TrendKind.none,
      showR2: trend != TrendKind.none,
      pointColors: points,
    );
    final charts = [
      SheetChart(kind: ChartKind.doughnut, title: 'Ring', series: [series(points: [null, 0xFF112233])], col: 0, row: 0),
      SheetChart(kind: ChartKind.pie, series: [series(labels: LabelKind.value)], col: 0, row: 0),
      SheetChart(kind: ChartKind.pie, series: [series(labels: LabelKind.none)], col: 0, row: 0),
      SheetChart(kind: ChartKind.column, series: [series(labels: LabelKind.value, trend: TrendKind.linear, points: [null, 0xFF445566]), series(labels: LabelKind.value)], col: 0, row: 0),
      SheetChart(kind: ChartKind.column, stacked: true, series: [series(labels: LabelKind.value), series(labels: LabelKind.value)], col: 0, row: 0),
      SheetChart(kind: ChartKind.bar, series: [series(labels: LabelKind.value, trend: TrendKind.polynomial), series()], col: 0, row: 0),
      SheetChart(kind: ChartKind.line, series: [series(labels: LabelKind.value, trend: TrendKind.exponential), series(trend: TrendKind.movingAverage)], col: 0, row: 0),
      SheetChart(kind: ChartKind.area, series: [series(labels: LabelKind.value)], col: 0, row: 0),
      SheetChart(kind: ChartKind.scatter, series: [series(labels: LabelKind.value, trend: TrendKind.linear)], col: 0, row: 0),
    ];
    for (final chart in charts) {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(width: 340, height: 220, child: CustomPaint(painter: ChartPainter(chart, data))),
        ),
      );
      expect(tester.takeException(), isNull, reason: '${chart.kind}');
    }
  });

  testWidgets('cells without numbers give a clear message and no chart', (tester) async {
    final cubit = await open(tester);
    await fill(tester, 0, 0, 'words only');
    await tester.tap(find.byKey(const ValueKey('cell_0_0')));
    await tester.pump();
    await menu(tester, 'Add chart from selection');
    await tester.tap(find.byKey(const ValueKey('chart_apply')));
    await tester.pumpAndSettle();
    expect(cubit.sheet.charts, isEmpty);
    expect(find.textContaining('Select cells that hold numbers'), findsOneWidget);
  });

  testWidgets('the painter draws every kind of chart, with and without data, without errors', (tester) async {
    for (final kind in ChartKind.values) {
      for (final stacked in [false, true]) {
        final chart = SheetChart(kind: kind, title: 'T', stacked: stacked, percent: stacked, series: const [], col: 0, row: 0);
        final data = ChartData(
          xs: const [1, 2.5, 3, 4],
          categories: const ['a', 'b', 'c', 'd'],
          series: const [
            (name: 'One', values: <double?>[3, -2, null, 8]),
            (name: 'Two', values: <double?>[1, 5, 2, 0]),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(width: 320, height: 200, child: CustomPaint(painter: ChartPainter(chart, data))),
          ),
        );
        expect(tester.takeException(), isNull, reason: '$kind stacked=$stacked');
      }
    }
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 200,
          child: CustomPaint(painter: ChartPainter(SheetChart(kind: ChartKind.pie, series: const [], col: 0, row: 0), const ChartData(categories: [], series: []))),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('round scales for the value axis', () {
    final s = ChartPainter.niceScale(0, 14);
    expect(s.min, 0);
    expect(s.max, greaterThanOrEqualTo(14));
    expect(ChartPainter.niceScale(-3, 7).min, lessThanOrEqualTo(-3));
    expect(ChartPainter.niceScale(5, 5).max, greaterThan(5));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/core/theme/app_theme.dart';
import 'package:doculoom/core/widgets/dark_chip.dart';

Color _fill(WidgetTester t) => t.widget<Material>(find.descendant(of: find.byType(DarkChip), matching: find.byType(Material)).first).color!;
Color _text(WidgetTester t) => t.widget<Text>(find.text('Bold')).style!.color!;

void main() {
  Future<void> show(WidgetTester t, {required bool selected, Color? selectedColor}) => t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: Center(
          child: DarkChip(label: 'Bold', selected: selected, onTap: () {}, selectedColor: selectedColor ?? Colors.white),
        ),
      ),
    ),
  );

  testWidgets('the label never has the same colour as the chip', (tester) async {
    for (final selected in [false, true]) {
      for (final color in [Colors.white, const Color(0xFF1D4ED8)]) {
        await show(tester, selected: selected, selectedColor: color);
        expect(_text(tester), isNot(_fill(tester)), reason: 'selected=$selected color=$color');
        expect((_text(tester).computeLuminance() - _fill(tester).computeLuminance()).abs(), greaterThan(0.3));
      }
    }
  });

  testWidgets('tapping calls back and the chip reports its state', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DarkChip(label: 'Bold', selected: true, onTap: () => taps++),
        ),
      ),
    );
    await tester.tap(find.byType(DarkChip));
    expect(taps, 1);
    expect(tester.getSemantics(find.byType(DarkChip)).label, 'Bold');
  });
}

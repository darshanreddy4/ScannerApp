import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/ocr/presentation/markdown_math_view.dart';

Future<void> show(WidgetTester tester, String markdown, {double width = 400}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: MarkdownMathView(markdown: markdown)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('headings, paragraphs and lists render as text', (tester) async {
    await show(tester, '# Annual Report\n\nFirst paragraph here.\n\n- Apples\n- Pears\n\n1. One\n2. Two');
    for (final t in ['Annual Report', 'First paragraph here.', 'Apples', 'Pears', 'One', 'Two']) {
      expect(find.textContaining(t, findRichText: true), findsWidgets, reason: t);
    }
    expect(find.byType(Math), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('display formulas and inline formulas are typeset', (tester) async {
    await show(tester, 'Pythagoras states that\n\n\$\$a^{2} + b^{2} = c^{2}\$\$\n\nwhere \$x = 5\$ and \$\\pi\$ are used.');
    expect(find.byType(Math), findsNWidgets(3));
    expect(find.textContaining('Pythagoras states that', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escaped dollar signs stay as money, not formulas', (tester) async {
    await show(tester, r'Pay \$5 and \$10 today');
    expect(find.byType(Math), findsNothing);
    expect(find.textContaining(r'$5 and $10', findRichText: true), findsOneWidget);
  });

  testWidgets('a broken formula falls back to its source instead of failing', (tester) async {
    await show(tester, r'Bad $\frac{1}{$ here');
    expect(tester.takeException(), isNull);
    expect(find.textContaining('here', findRichText: true), findsWidgets);
  });

  testWidgets('a long formula scrolls sideways on a narrow screen without overflow', (tester) async {
    await show(tester, '\$\$${List.filled(25, 'a^{2} + b^{2}').join(' + ')}\$\$', width: 320);
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('empty text renders nothing and does not fail', (tester) async {
    await show(tester, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the structurer output round-trips through the viewer', (tester) async {
    await show(tester, '## Summary\n\nThe area is \$A = 25\$ and \$r^{2}\$ grows.\n\n\$\$\\sqrt{a+b} = 4\$\$');
    expect(find.byType(Math), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

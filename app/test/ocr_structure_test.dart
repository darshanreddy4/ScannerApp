import 'package:flutter_test/flutter_test.dart';
import 'package:doculoom/features/ocr/domain/math_converter.dart';
import 'package:doculoom/features/ocr/domain/ocr_models.dart';
import 'package:doculoom/features/ocr/domain/text_structurer.dart';

OcrLine line(String text, {double top = 0, double height = 20, double left = 10, double width = 300}) =>
    OcrLine(text: text, left: left, top: top, right: left + width, bottom: top + height);

OcrPageResult page(List<List<OcrLine>> blocks) => OcrPageResult(width: 800, height: 1000, blocks: [for (final b in blocks) OcrBlock(lines: b)]);

void main() {
  group('MathConverter.isFormulaLine', () {
    test('equations and expressions are formulas', () {
      for (final s in [
        'x = 5',
        'a² + b² = c²',
        'E = mc^2',
        'y = (a+b)/2',
        '∑ x_i = 10',
        'x ≤ 3',
        '√(a+b) = 4',
        'a/b = c/d',
        '2 + 3 = 5',
        'f(x) = x^2 - 4x + 4',
      ]) {
        expect(MathConverter.isFormulaLine(s), isTrue, reason: s);
      }
    });

    test('sentences, dates, prices and plain numbers are not', () {
      for (final s in [
        'The total is 5 + 3 = 8 dollars',
        '12/05/2024',
        'Invoice 2024-05-12',
        'Page 3 of 10',
        '1 2 3 4 5',
        'Total: \$45.00',
        'Call 555-0199',
        '= 5',
        'hello world',
      ]) {
        expect(MathConverter.isFormulaLine(s), isFalse, reason: s);
      }
    });
  });

  group('MathConverter.toLatex', () {
    String l(String s) => MathConverter.toLatex(s);

    test('powers and subscripts', () {
      expect(l('x^2'), 'x^{2}');
      expect(l('x²'), 'x^{2}');
      expect(l('x^10 + y^-1'), 'x^{10} + y^{-1}');
      expect(l('x^(n+1)'), 'x^{n+1}');
      expect(l('a_n + b₂'), 'a_{n} + b_{2}');
      expect(l('10⁻³'), '10^{-3}');
    });

    test('roots and fractions', () {
      expect(l('√(a+b)'), r'\sqrt{a+b}');
      expect(l('√x + √16'), r'\sqrt{x} + \sqrt{16}');
      expect(l('a/b'), r'\frac{a}{b}');
      expect(l('(a+b)/(c-d)'), r'\frac{a+b}{c-d}');
      expect(l('x^2/y'), 'x^{2}/y', reason: 'a power over y is left as written, not misread as 2/y');
    });

    test('symbols and Greek letters', () {
      expect(l('a ≤ b ≠ c'), r'a \leq b \neq c');
      expect(l('A = πr²'), r'A = \pi r^{2}');
      expect(l('2 × 3 ± 1'), r'2 \times 3 \pm 1');
      expect(l('∑ x'), r'\sum x');
      expect(l('90°'), r'90^{\circ}');
    });

    test('function names become operators and special characters are escaped', () {
      expect(l('sin x + log y'), r'\sin x + \log y');
      expect(l('5% of 20'), r'5\% of 20');
      expect(l('a * b'), r'a \cdot b');
    });
  });

  group('MathConverter.splitInline', () {
    String join(String s) => MathConverter.splitInline(s).map((p) => p.math ? '[${p.text}]' : p.text).join();

    test('finds formulas inside a sentence', () {
      expect(join('The area is A = 25 and r^2 grows'), 'The area is [A = 25] and [r^2] grows');
      expect(join('Let x² be positive and α small'), 'Let [x²] be positive and [α] small');
      expect(join('Take √(a+b) as given'), 'Take [√(a+b)] as given');
    });

    test('leaves ordinary words, snake_case and prices alone', () {
      expect(join('Open file_name.txt and pay 5 dollars'), 'Open file_name.txt and pay 5 dollars');
      expect(join('max^2 is not split'), 'max^2 is not split');
    });
  });

  group('TextStructurer', () {
    test('a large short line becomes a heading and the rest a paragraph with joined lines', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('Annual Report', height: 44)],
          [line('This is the first line of', top: 80), line('the paragraph that wraps.', top: 102)],
        ]),
      );
      expect(md, '# Annual Report\n\nThis is the first line of the paragraph that wraps.');
    });

    test('a medium heading gets two hashes', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('Summary', height: 30)],
          [line('Body text here.', top: 60), line('More body text.', top: 82), line('Even more text.', top: 104)],
        ]),
      );
      expect(md.startsWith('## Summary'), isTrue);
    });

    test('words split across lines are rejoined', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('This is an exam-', top: 0), line('ple of hyphenation.', top: 22)],
        ]),
      );
      expect(md, 'This is an example of hyphenation.');
    });

    test('bullets and numbers become lists and wrapped items stay together', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('• Apples', top: 0), line('• Pears that are', top: 22), line('quite ripe', top: 44), line('• Plums', top: 66)],
          [line('1. First step', top: 120), line('2) Second step', top: 142)],
        ]),
      );
      expect(md, '- Apples\n- Pears that are quite ripe\n- Plums\n\n1. First step\n2. Second step');
    });

    test('a person\'s initial is not a list', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('J. Smith wrote this.', top: 0)],
        ]),
      );
      expect(md, 'J. Smith wrote this.');
    });

    test('a formula line becomes display math and inline formulas stay in the sentence', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('Pythagoras states that', top: 0)],
          [line('a² + b² = c²', top: 60)],
          [line('where c is the longest side and x = 5 here', top: 120)],
        ]),
      );
      expect(md, contains('\$\$a^{2} + b^{2} = c^{2}\$\$'));
      expect(md, contains('\$x = 5\$'));
      expect(md.indexOf('Pythagoras'), lessThan(md.indexOf('\$\$')));
    });

    test('markdown characters and dollar amounts in ordinary text are escaped', () {
      final md = TextStructurer.toMarkdown(
        page([
          [line('Use *stars* and snake_case, pay \$5 and \$10 [now] #1', top: 0)],
        ]),
      );
      expect(md, r'Use \*stars\* and snake\_case, pay \$5 and \$10 \[now\] \#1');
    });

    test('empty pages give empty text', () {
      expect(TextStructurer.toMarkdown(page([])), '');
      expect(
        TextStructurer.toMarkdown(
          page([
            [line('   ')],
          ]),
        ),
        '',
      );
    });
  });
}

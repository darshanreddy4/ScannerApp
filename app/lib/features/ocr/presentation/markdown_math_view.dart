import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/theme/app_colors.dart';

/// `$...$` inside a sentence.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'(?<!\\)\$([^$\n]+?)(?<!\\)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', match[1]!.trim()));
    return true;
  }
}

/// A line holding only `$$...$$`, shown centred as a display formula.
class MathBlockSyntax extends md.BlockSyntax {
  const MathBlockSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$(.+?)\$\$\s*$');

  @override
  md.Node parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content)!;
    parser.advance();
    // flutter_markdown only lays out known block tags reliably, so a formula goes in a paragraph as a wide inline widget.
    return md.Element('p', [md.Element.text('mathDisplay', match[1]!.trim())]);
  }
}

class _InlineMath extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final tex = element.textContent;
    final style = preferredStyle ?? parentStyle;
    return Math.tex(
      tex,
      textStyle: style,
      onErrorFallback: (_) => Text('\$$tex\$', style: style),
    );
  }
}

class _DisplayMath extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final tex = element.textContent;
    final style = (preferredStyle ?? parentStyle ?? const TextStyle()).copyWith(fontSize: ((preferredStyle ?? parentStyle)?.fontSize ?? 16) * 1.15);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Math.tex(
            tex,
            mathStyle: MathStyle.display,
            textStyle: style,
            onErrorFallback: (_) => Text('\$\$$tex\$\$', style: style),
          ),
        ),
      ),
    );
  }
}

/// Shows recognised text: headings, lists and paragraphs from Markdown (flutter_markdown), and formulas drawn
/// as typeset maths (flutter_math_fork).
class MarkdownMathView extends StatelessWidget {
  const MarkdownMathView({super.key, required this.markdown});
  final String markdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink),
      h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
      h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
      h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink),
      listBullet: const TextStyle(fontSize: 16, color: AppColors.ink),
      blockSpacing: 12,
    );
    return SelectionArea(
      child: MarkdownBody(
        data: markdown,
        softLineBreak: true,
        styleSheet: sheet,
        blockSyntaxes: const [MathBlockSyntax()],
        inlineSyntaxes: [MathInlineSyntax()],
        builders: {'math': _InlineMath(), 'mathDisplay': _DisplayMath()},
      ),
    );
  }
}

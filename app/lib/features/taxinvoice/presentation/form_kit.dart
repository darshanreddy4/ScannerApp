import 'package:flutter/material.dart' hide Text;

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/text.dart';
import '../domain/tax_common.dart';

/// The first problem of each field, so a field can show its own message.
Map<String, TaxIssue> issuesByField(Iterable<TaxIssue> issues) {
  final out = <String, TaxIssue>{};
  for (final i in issues) {
    out.putIfAbsent(i.field, () => i);
  }
  return out;
}

/// A titled card that groups the fields of one part of an invoice.
class TaxSection extends StatelessWidget {
  const TaxSection({super.key, required this.title, required this.children, this.hint});
  final String title;
  final String? hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (hint != null) ...[const SizedBox(height: 4), Text(hint!, style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4))],
          const SizedBox(height: AppSpacing.sm + 4),
          ...children,
        ],
      ),
    ),
  );
}

/// A text field with its label translated and, when there is one, the message of its problem.
class TaxField extends StatelessWidget {
  const TaxField({
    super.key,
    required this.controller,
    required this.label,
    required this.onChanged,
    this.issue,
    this.helper,
    this.keyboard,
    this.caps = TextCapitalization.sentences,
    this.maxLength,
    this.maxLines = 1,
    this.hint,
    this.suffix,
    this.prefix,
  });
  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;
  final TaxIssue? issue;
  final String? helper;
  final TextInputType? keyboard;
  final TextCapitalization caps;
  final int? maxLength;
  final int maxLines;
  final String? hint;
  final Widget? suffix;
  final String? prefix;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboard,
    textCapitalization: caps,
    maxLength: maxLength,
    maxLines: maxLines,
    onChanged: (_) => onChanged(),
    decoration: InputDecoration(
      labelText: tr(label),
      hintText: hint == null ? null : tr(hint!),
      helperText: helper == null ? null : tr(helper!),
      helperMaxLines: 3,
      errorText: issue?.text,
      errorMaxLines: 3,
      counterText: '',
      suffixIcon: suffix,
      prefixText: prefix,
    ),
  );
}

const taxGap = SizedBox(height: AppSpacing.sm + 4);

const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

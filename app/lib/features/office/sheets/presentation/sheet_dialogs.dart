import 'package:flutter/material.dart' hide Text;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import 'sheet_cubit.dart';
import '../../../../core/widgets/text.dart';

/// Result of the colour picker: [color] null means "none" (no fill, or the automatic text colour).
typedef ColorChoice = ({int? color});

const _palette = <int>[
  0xFF000000, 0xFF434343, 0xFF666666, 0xFF999999, 0xFFCCCCCC, 0xFFFFFFFF, //
  0xFFE53935, 0xFFF57C00, 0xFFFBC02D, 0xFF43A047, 0xFF1E88E5, 0xFF8E24AA,
  0xFFFFCDD2, 0xFFFFE0B2, 0xFFFFF9C4, 0xFFC8E6C9, 0xFFBBDEFB, 0xFFE1BEE7,
  0xFFB71C1C, 0xFFE65100, 0xFFF9A825, 0xFF1B5E20, 0xFF0D47A1, 0xFF4A148C,
];

Future<ColorChoice?> pickColor(BuildContext context, {required String title, required String noneLabel}) => showModalBottomSheet<ColorChoice>(
  context: context,
  showDragHandle: true,
  builder: (_) => SafeArea(
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in _palette)
                InkWell(
                  key: ValueKey('color_${c.toRadixString(16)}'),
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(context, (color: c)),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(key: const ValueKey('color_none'), onPressed: () => Navigator.pop(context, (color: null)), child: Text(noneLabel)),
        ],
      ),
    ),
  ),
);

const numberFormats = <(String, String, String)>[
  ('General', 'General', 'As typed'),
  ('Number', '0.00', '1234.50'),
  ('Number with commas', '#,##0.00', '1,234.50'),
  ('Whole number', '0', '1235'),
  ('Currency', r'$#,##0.00', r'$1,234.50'),
  ('Percent', '0.00%', '12.50%'),
  ('Date (2024-03-05)', 'yyyy-mm-dd', '2024-03-05'),
  ('Date (05/03/2024)', 'dd/mm/yyyy', '05/03/2024'),
  ('Time', 'hh:mm', '14:30'),
  ('Scientific', '0.00E+00', '1.23E+03'),
  ('Text', '@', 'Shown exactly as typed'),
];

Future<String?> pickNumberFormat(BuildContext context, String current) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final f in numberFormats)
            ListTile(
              key: ValueKey('fmt_${f.$2}'),
              title: Text(f.$1),
              subtitle: Text(f.$3),
              trailing: f.$2 == current ? const Icon(AppIcons.check, color: AppColors.primary) : null,
              onTap: () => Navigator.pop(context, f.$2),
            ),
        ],
      ),
    ),
  ),
);

Future<double?> pickFontSize(BuildContext context, double? current) => showModalBottomSheet<double>(
  context: context,
  showDragHandle: true,
  builder: (_) => SafeArea(
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in const [8.0, 9.0, 10.0, 11.0, 12.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 36.0])
            ChoiceChip(
              key: ValueKey('size_${s.toInt()}'),
              label: Text('${s.toInt()}'),
              selected: (current ?? 11) == s,
              onSelected: (_) => Navigator.pop(context, s),
            ),
        ],
      ),
    ),
  ),
);

/// Asks for a line of text. Returns null when cancelled.
Future<String?> askText(BuildContext context, {required String title, String initial = '', String? label, String confirm = 'OK', int? maxLength}) {
  final controller = TextEditingController(text: initial)..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('ask_text'),
        controller: controller,
        autofocus: true,
        maxLength: maxLength,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(confirm)),
      ],
    ),
  );
}

Future<double?> askNumber(
  BuildContext context, {
  required String title,
  required double initial,
  required String label,
  double min = 1,
  double max = 255,
}) async {
  final text = await askText(
    context,
    title: title,
    initial: initial == initial.roundToDouble() ? '${initial.toInt()}' : initial.toStringAsFixed(1),
    label: label,
  );
  final v = text == null ? null : double.tryParse(text.trim());
  if (v == null) return null;
  return v.clamp(min, max);
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, required String confirm, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

typedef SortChoice = ({bool ascending, bool hasHeader});

Future<SortChoice?> askSort(BuildContext context, {required String columnName}) {
  var ascending = true, header = false;
  return showDialog<SortChoice>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Sort by column $columnName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('A to Z')),
                ButtonSegment(value: false, label: Text('Z to A')),
              ],
              selected: {ascending},
              onSelectionChanged: (v) => setState(() => ascending = v.first),
            ),
            CheckboxListTile(
              key: const ValueKey('sort_header'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('First row is a header'),
              value: header,
              onChanged: (v) => setState(() => header = v ?? false),
            ),
            const Text(
              'Select a block of cells first to sort only that block. With one cell selected, the whole sheet is sorted.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('sort_go'),
            onPressed: () => Navigator.pop(context, (ascending: ascending, hasHeader: header)),
            child: const Text('Sort'),
          ),
        ],
      ),
    ),
  );
}

enum SaveAction { share, saveToFiles }

typedef SaveChoice = ({SheetExportFormat format, SaveAction action});

/// "Save or share" sheet: pick a format, then share it or save it to Files.
Future<SaveChoice?> askSave(BuildContext context, {bool allowPdf = true}) => showModalBottomSheet<SaveChoice>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) {
    var format = SheetExportFormat.xlsx;
    return SafeArea(
      child: StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Save or share', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              for (final f in SheetExportFormat.values)
                if (allowPdf || f != SheetExportFormat.pdf)
                  RadioListTile<SheetExportFormat>(
                    key: ValueKey('format_${f.extension}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(f.label),
                    value: f,
                    // ignore: deprecated_member_use
                    groupValue: format,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => format = v!),
                  ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('save_share'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: () => Navigator.pop(context, (format: format, action: SaveAction.share)),
                      icon: const Icon(AppIcons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('save_files'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                      onPressed: () => Navigator.pop(context, (format: format, action: SaveAction.saveToFiles)),
                      icon: const Icon(AppIcons.storage, size: 18),
                      label: const Text('Save to Files'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  },
);

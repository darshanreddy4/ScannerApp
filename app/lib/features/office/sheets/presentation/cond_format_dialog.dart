import 'package:flutter/material.dart' hide Text;

import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/text.dart';
import '../domain/cond_format.dart';
import '../domain/sheet_model.dart';

const _kinds = <(CondKind, String)>[
  (CondKind.greater, 'Greater than'),
  (CondKind.less, 'Less than'),
  (CondKind.equal, 'Equal to'),
  (CondKind.notEqual, 'Not equal to'),
  (CondKind.between, 'Between'),
  (CondKind.textContains, 'Text contains'),
  (CondKind.duplicates, 'Duplicate values'),
  (CondKind.scale, 'Colour scale'),
];

/// Asks which cells to highlight and how. The rule that comes back still has to be given the range it applies to.
Future<CondRule?> askHighlight(BuildContext context) =>
    showModalBottomSheet<CondRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _HighlightSheet(),
    );

class _HighlightSheet extends StatefulWidget {
  const _HighlightSheet();

  @override
  State<_HighlightSheet> createState() => _HighlightSheetState();
}

class _HighlightSheetState extends State<_HighlightSheet> {
  var _kind = CondKind.greater;
  var _look = 0;
  var _scale = 0;
  final _a = TextEditingController();
  final _b = TextEditingController();

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  bool get _ready {
    if (_kind == CondKind.between)
      return _a.text.trim().isNotEmpty && _b.text.trim().isNotEmpty;
    if (_kind == CondKind.duplicates || _kind == CondKind.scale) return true;
    return _a.text.trim().isNotEmpty;
  }

  CondRule _rule() => CondRule(
    range: const MergeRange(0, 0, 0, 0),
    kind: _kind,
    a: _a.text.trim(),
    b: _b.text.trim(),
    look: _kind == CondKind.scale ? const DxfStyle() : condLooks[_look].$2,
    scale: _kind == CondKind.scale ? condScales[_scale].$2 : const [],
  );

  @override
  Widget build(BuildContext context) {
    final needsValue = _kind != CondKind.duplicates && _kind != CondKind.scale;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Highlight the selected cells',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final k in _kinds)
                        ChoiceChip(
                          key: ValueKey('cond_kind_${k.$1.name}'),
                          label: Text(k.$2),
                          selected: _kind == k.$1,
                          onSelected: (_) => setState(() => _kind = k.$1),
                        ),
                    ],
                  ),
                  if (needsValue) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const ValueKey('cond_a'),
                      controller: _a,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      keyboardType: _kind == CondKind.textContains
                          ? TextInputType.text
                          : const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                      decoration: InputDecoration(
                        labelText: tr(
                          _kind == CondKind.textContains
                              ? 'Text to look for'
                              : (_kind == CondKind.between ? 'From' : 'Value'),
                        ),
                        isDense: true,
                      ),
                    ),
                  ],
                  if (_kind == CondKind.between) ...[
                    const SizedBox(height: 8),
                    TextField(
                      key: const ValueKey('cond_b'),
                      controller: _b,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: tr('To'),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    'Look',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  if (_kind == CondKind.scale)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < condScales.length; i++)
                          ChoiceChip(
                            key: ValueKey('cond_scale_$i'),
                            avatar: _Gradient(colors: condScales[i].$2),
                            label: Text(condScales[i].$1),
                            selected: _scale == i,
                            onSelected: (_) => setState(() => _scale = i),
                          ),
                      ],
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < condLooks.length; i++)
                          ChoiceChip(
                            key: ValueKey('cond_look_$i'),
                            label: Text(
                              condLooks[i].$1,
                              style: TextStyle(
                                color: Color(
                                  condLooks[i].$2.fontColor ?? 0xFF000000,
                                ),
                                fontWeight: condLooks[i].$2.bold
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            backgroundColor: condLooks[i].$2.fill == null
                                ? null
                                : Color(condLooks[i].$2.fill!),
                            selectedColor: condLooks[i].$2.fill == null
                                ? null
                                : Color(condLooks[i].$2.fill!),
                            selected: _look == i,
                            onSelected: (_) => setState(() => _look = i),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('cond_apply'),
                    onPressed: _ready
                        ? () => Navigator.pop(context, _rule())
                        : null,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Gradient extends StatelessWidget {
  const _Gradient({required this.colors});
  final List<int> colors;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 14,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: AppColors.border),
      gradient: LinearGradient(colors: [for (final c in colors) Color(c)]),
    ),
  );
}

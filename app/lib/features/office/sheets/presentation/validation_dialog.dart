import 'package:flutter/material.dart' hide Text;

import '../../../../core/i18n/tr.dart';
import '../../../../core/widgets/text.dart';
import '../domain/sheet_model.dart';
import '../domain/validation.dart';

const _kinds = <(ValidationKind, String)>[
  (ValidationKind.list, 'List of choices'),
  (ValidationKind.whole, 'Whole number'),
  (ValidationKind.decimal, 'Decimal number'),
];

/// Asks what may be typed into the selected cells. The rule that comes back still has to be given the range it applies to.
Future<ValidationRule?> askValidation(BuildContext context) => showModalBottomSheet<ValidationRule>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const _ValidationSheet(),
);

class _ValidationSheet extends StatefulWidget {
  const _ValidationSheet();

  @override
  State<_ValidationSheet> createState() => _ValidationSheetState();
}

class _ValidationSheetState extends State<_ValidationSheet> {
  var _kind = ValidationKind.list;
  final _items = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();

  @override
  void dispose() {
    _items.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  List<String> get _choices => [
    for (final i in _items.text.split(','))
      if (i.trim().isNotEmpty) i.trim(),
  ];

  bool get _ready => _kind == ValidationKind.list
      ? _choices.isNotEmpty && _choices.join(',').length <= 250
      : double.tryParse(_min.text.trim()) != null && double.tryParse(_max.text.trim()) != null;

  ValidationRule _rule() => ValidationRule(
    range: const MergeRange(0, 0, 0, 0),
    kind: _kind,
    items: _kind == ValidationKind.list ? _choices : const [],
    min: _min.text.trim(),
    max: _max.text.trim(),
  );

  @override
  Widget build(BuildContext context) => Padding(
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
                const Text('Allow only these values in the selected cells', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final k in _kinds)
                      ChoiceChip(key: ValueKey('valid_kind_${k.$1.name}'), label: Text(k.$2), selected: _kind == k.$1, onSelected: (_) => setState(() => _kind = k.$1)),
                  ],
                ),
                const SizedBox(height: 12),
                if (_kind == ValidationKind.list)
                  TextField(
                    key: const ValueKey('valid_items'),
                    controller: _items,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: tr('Choices, separated by commas'), hintText: 'Yes, No, Maybe', isDense: true),
                  )
                else ...[
                  TextField(
                    key: const ValueKey('valid_min'),
                    controller: _min,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(labelText: tr('From'), isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('valid_max'),
                    controller: _max,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: InputDecoration(labelText: tr('To'), isDense: true),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Typing anything else is refused. In a list, the cell also gets a drop-down arrow.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 4, 20, 16),
          child: Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(key: const ValueKey('valid_apply'), onPressed: _ready ? () => Navigator.pop(context, _rule()) : null, child: const Text('Apply')),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

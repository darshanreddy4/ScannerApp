import 'package:flutter/material.dart' hide Text;

import '../../../../core/i18n/tr.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/text.dart';
import '../domain/function_catalog.dart';

/// Lets the person look through the spreadsheet functions and pick one; returns its name.
Future<String?> pickFunction(BuildContext context) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _FunctionSheet(),
);

class _FunctionSheet extends StatefulWidget {
  const _FunctionSheet();

  @override
  State<_FunctionSheet> createState() => _FunctionSheetState();
}

class _FunctionSheetState extends State<_FunctionSheet> {
  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final found = searchFunctions(_search.text, category: _category);
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: TextField(
                key: const ValueKey('function_search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                autocorrect: false,
                decoration: InputDecoration(hintText: tr('Search functions, such as SUM or lookup'), prefixIcon: const Icon(AppIcons.search, size: 18), isDense: true),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                children: [
                  for (final c in <String?>[null, ...functionCategories])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        key: ValueKey('function_cat_${c ?? 'all'}'),
                        label: Text(c ?? 'All'),
                        selected: _category == c,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: found.isEmpty
                  ? const Center(
                      child: Text('No function found', style: TextStyle(color: AppColors.inkMuted)),
                    )
                  : ListView.builder(
                      itemCount: found.length,
                      itemBuilder: (_, i) {
                        final f = found[i];
                        return ListTile(
                          key: ValueKey('function_${f.name}'),
                          dense: true,
                          title: Text(f.syntax, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: Text(f.summary),
                          onTap: () => Navigator.pop(context, f.name),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

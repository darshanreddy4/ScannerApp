import 'package:flutter/material.dart' hide Text;

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/region.dart';
import '../../../core/widgets/dark_chip.dart';
import '../../../core/widgets/text.dart';
import '../data/stamp_store.dart';
import '../domain/stamps.dart';
import 'markup_color_sheet.dart';

/// Lets the person pick a ready-made stamp, one of their own, or make a new one.
Future<Stamp?> showStampLibrary(BuildContext context, {StampStore store = const StampStore(), String? region}) => showModalBottomSheet<Stamp>(
  context: context,
  isScrollControlled: true,
  backgroundColor: MarkupColors.raised,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
  builder: (_) => _StampSheet(store: store, region: region ?? Region.toolRegion.name),
);

String _colorName(int color) => switch (color) {
  stampRed => 'Red',
  stampBlue => 'Blue',
  stampGreen => 'Green',
  _ => 'Black',
};

class _StampSheet extends StatefulWidget {
  const _StampSheet({required this.store, required this.region});
  final StampStore store;
  final String region;

  @override
  State<_StampSheet> createState() => _StampSheetState();
}

class _StampSheetState extends State<_StampSheet> {
  final _text = TextEditingController();
  List<Stamp> _mine = const [];
  bool _making = false;
  bool _withDate = false;
  bool _checked = false;
  int _color = stampRed;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((all) {
      if (mounted) setState(() => _mine = all);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _problem => stampProblem(_text.text, withDate: _withDate);

  Stamp get _draft => Stamp(stampText(_text.text, withDate: _withDate), _color);

  Future<void> _useOwn() async {
    setState(() => _checked = true);
    if (_problem != null) return;
    final stamp = _draft;
    await widget.store.add(stamp);
    if (mounted) Navigator.pop(context, stamp);
  }

  Future<void> _delete(Stamp stamp) async {
    final all = await widget.store.remove(stamp);
    if (mounted) setState(() => _mine = all);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Choose a stamp',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              Flexible(
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                  children: [
                    _maker(),
                    if (_mine.isNotEmpty) ...[
                      const _Heading('My stamps'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final s in _mine) StampTile(stamp: s, onTap: () => Navigator.pop(context, s), onDelete: () => _delete(s))],
                      ),
                    ],
                    for (final group in orderedStampGroups(widget.region)) ...[
                      _Heading(group.title),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [for (final s in group.stamps) StampTile(stamp: s, onTap: () => Navigator.pop(context, s))],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _maker() {
    if (!_making) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: DarkChip(key: const ValueKey('make-stamp'), label: 'Make your own stamp', selected: false, onTap: () => setState(() => _making = true)),
      );
    }
    final problem = _checked ? _problem : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Make your own stamp',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('stamp-text'),
            controller: _text,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: tr('Words on the stamp *'),
              labelStyle: const TextStyle(color: Colors.white70),
              helperText: tr('Up to 3 lines, 24 characters each. Press enter for a new line.'),
              helperMaxLines: 2,
              helperStyle: const TextStyle(color: Colors.white60),
              errorText: problem == null ? null : tr(problem),
              errorMaxLines: 3,
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Colour',
            style: TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in stampColors)
                Semantics(
                  button: true,
                  selected: _color == c,
                  label: tr(_colorName(c)),
                  excludeSemantics: true,
                  child: InkResponse(
                    key: ValueKey('stamp-color-${_colorName(c).toLowerCase()}'),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: _color == c ? Colors.white : Colors.white24, width: _color == c ? 3 : 1),
                      ),
                      child: _color == c ? const Icon(AppIcons.check, size: 18, color: Colors.white) : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              key: const ValueKey('stamp-date'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text("Add today's date", style: TextStyle(color: Colors.white, fontSize: 14)),
              value: _withDate,
              onChanged: (v) => setState(() => _withDate = v),
            ),
          ),
          if (_text.text.trim().isNotEmpty && stampProblem(_text.text, withDate: _withDate) == null) ...[
            const SizedBox(height: 4),
            const Text(
              'Preview',
              style: TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StampTile(key: const ValueKey('stamp-preview'), stamp: _draft),
            ),
          ],
          const SizedBox(height: 10),
          const Text('It is kept in My stamps, on this phone only.', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(key: const ValueKey('stamp-use'), onPressed: _useOwn, child: const Text('Use this stamp')),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(color: Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w600),
    ),
  );
}

/// A stamp as a small framed label, as it will look on the page. The words are shown as they are, never translated.
class StampTile extends StatelessWidget {
  const StampTile({super.key, required this.stamp, this.onTap, this.onDelete});
  final Stamp stamp;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final words = stamp.resolve(formatDate(DateTime.now()).toUpperCase());
    final color = Color(stamp.color);
    final tile = Container(
      constraints: const BoxConstraints(minWidth: 64, minHeight: 48, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 2),
      ),
      child: Center(
        widthFactor: 1,
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            text: words,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800, height: 1.15),
          ),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      label: words.replaceAll('\n', ' '),
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(borderRadius: BorderRadius.circular(8), onTap: onTap, child: tile),
          if (onDelete != null)
            PositionedDirectional(
              top: -8,
              end: -8,
              child: Semantics(
                button: true,
                label: tr('Remove this stamp'),
                child: InkResponse(
                  key: ValueKey('stamp-delete-${stamp.text}'),
                  onTap: onDelete,
                  radius: 20,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                    child: const Icon(AppIcons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../qr/domain/scan_services.dart';
import '../data/card_store.dart';
import '../domain/cards.dart';
import 'card_code_view.dart';

/// What the edit screen starts with: a saved card to change, or the code just scanned for a new one.
class CardEditArgs {
  const CardEditArgs({this.card, this.number = '', this.type, this.name = ''});
  final LoyaltyCard? card;
  final String number;
  final CardCodeType? type;
  final String name;
}

IconData categoryIcon(CardCategory c) => switch (c) {
  CardCategory.shop => AppIcons.catShop,
  CardCategory.supermarket => AppIcons.catSupermarket,
  CardCategory.pharmacy => AppIcons.catPharmacy,
  CardCategory.fuel => AppIcons.catFuel,
  CardCategory.food => AppIcons.catFood,
  CardCategory.travel => AppIcons.catTravel,
  CardCategory.fitness => AppIcons.catFitness,
  CardCategory.library => AppIcons.catLibrary,
  CardCategory.gift => AppIcons.catGift,
  CardCategory.membership => AppIcons.catMembership,
  CardCategory.other => AppIcons.catOther,
};

/// Adds or changes a card: the name and number are needed, the rest helps to find and trust the card later.
class CardEditPage extends StatefulWidget {
  const CardEditPage({super.key, this.args = const CardEditArgs(), this.store = const CardStore(), this.now});
  final CardEditArgs args;
  final CardStore store;
  final DateTime Function()? now;

  @override
  State<CardEditPage> createState() => _CardEditPageState();
}

class _CardEditPageState extends State<CardEditPage> {
  late final _name = TextEditingController(text: widget.args.card?.name ?? widget.args.name);
  late final _number = TextEditingController(text: widget.args.card?.number ?? widget.args.number);
  late final _note = TextEditingController(text: widget.args.card?.note ?? '');
  final _numberFocus = FocusNode();
  final _nameFocus = FocusNode();
  late CardCodeType _type = widget.args.card?.type ?? widget.args.type ?? suggestCodeType(widget.args.number);
  late CardCategory _category = widget.args.card?.category ?? CardCategory.shop;
  late int _color = widget.args.card?.color ?? cardColors.first;
  late DateTime? _expiry = widget.args.card?.expiry;
  bool _typeChosen = false;
  bool _tried = false;
  bool _nameTouched = false;
  bool _numberTouched = false;
  bool _saving = false;
  List<LoyaltyCard> _others = const [];

  DateTime get _today => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _typeChosen = widget.args.card != null || widget.args.type != null;
    _numberFocus.addListener(() {
      if (!_numberFocus.hasFocus && mounted) setState(() => _numberTouched = true);
    });
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && mounted) setState(() => _nameTouched = true);
    });
    widget.store.load().then((all) {
      if (mounted) setState(() => _others = all);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    _note.dispose();
    _numberFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  LoyaltyCard get _draft => tidyCard(
    LoyaltyCard(
      id: widget.args.card?.id ?? '',
      name: _name.text,
      number: _number.text,
      type: _type,
      category: _category,
      color: _color,
      note: _note.text,
      expiry: _expiry,
      pinned: widget.args.card?.pinned ?? false,
      usedAt: widget.args.card?.usedAt ?? 0,
    ),
  );

  Future<void> _scan() async {
    final code = await context.push<DetectedCode>('/card-scan');
    if (code == null || !mounted) return;
    setState(() {
      _number.text = code.raw;
      _type = CardCodeType.fromScan(code.format) ?? suggestCodeType(code.raw);
      _typeChosen = true;
      _numberTouched = true;
    });
  }

  Future<void> _pickExpiry() async {
    final today = _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? DateTime(today.year + 1, today.month, today.day),
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 30),
      helpText: tr('Valid until'),
    );
    if (picked != null && mounted) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    final card = _draft;
    final problems = cardProblems(card, _others);
    if (problems.isNotEmpty) return;
    if (widget.args.card == null && _others.length >= maxCards) return;
    setState(() => _saving = true);
    final id = widget.args.card?.id ?? widget.store.newId(_others, _today);
    await widget.store.put(card.copyWith(id: id));
    if (mounted) Navigator.of(context).pop(id);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md, bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final problems = cardProblems(draft, _others);
    final nameError = (_tried || _nameTouched) ? problems['name'] : null;
    final numberError = (_tried || _numberTouched) ? problems['number'] : null;
    final noteError = problems['note'];
    final full = widget.args.card == null && _others.length >= maxCards;
    final canDraw = draft.type.isDrawn && draft.number.isNotEmpty && numberProblem(draft.type, draft.number) == null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.args.card == null ? 'Add a card' : 'Edit card')),
      body: SingleChildScrollView(
        padding: contentPadding(context),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Save the code of a shop, club or library card to show it at the till. Cards stay on this phone only.',
              style: TextStyle(fontSize: 13, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('card-name'),
              controller: _name,
              focusNode: _nameFocus,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: maxCardName,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Shop or club name *'),
                hintText: tr('For example Big Bazaar, Tesco Clubcard'),
                errorText: nameError?.text,
                errorMaxLines: 3,
                counterText: '',
              ),
            ),
            _label('Kind of card'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in CardCategory.values)
                  ChoiceChip(
                    key: ValueKey('card-kind-${c.name}'),
                    avatar: Icon(categoryIcon(c), size: 16),
                    label: Text(c.label),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('card-number'),
              controller: _number,
              focusNode: _numberFocus,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [LengthLimitingTextInputFormatter(maxCardNumber + 20)],
              onChanged: (v) => setState(() {
                if (!_typeChosen) _type = suggestCodeType(v);
              }),
              decoration: InputDecoration(
                labelText: tr('Card number *'),
                helperText: tr('Type it as printed under the barcode, or scan the card.'),
                helperMaxLines: 2,
                errorText: numberError?.text,
                errorMaxLines: 3,
                suffixIcon: IconButton(key: const ValueKey('card-scan'), tooltip: tr('Scan the card'), icon: const Icon(AppIcons.scanQr), onPressed: _scan),
              ),
            ),
            _label('How the code is shown'),
            DropdownButtonFormField<CardCodeType>(
              key: const ValueKey('card-type'),
              initialValue: _type,
              isExpanded: true,
              items: [for (final t in CardCodeType.values) DropdownMenuItem(value: t, child: Text(t.label))],
              onChanged: (t) => setState(() {
                if (t != null) {
                  _type = t;
                  _typeChosen = true;
                }
              }),
              decoration: InputDecoration(
                helperText: tr('Most shop cards use Code 128, EAN-13 or QR code. A scanned card already has the right one.'),
                helperMaxLines: 3,
              ),
            ),
            if (canDraw) ...[_label('Preview'), CardCodeView(key: const ValueKey('card-preview'), type: draft.type, number: draft.number)],
            _label('Colour'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in cardColors)
                  Semantics(
                    button: true,
                    selected: _color == c,
                    label: tr('Colour'),
                    excludeSemantics: true,
                    child: InkResponse(
                      key: ValueKey('card-color-${c.toRadixString(16)}'),
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == c ? AppColors.ink : Colors.transparent, width: 3),
                        ),
                        child: _color == c ? const Icon(AppIcons.check, size: 18, color: Colors.white) : null,
                      ),
                    ),
                  ),
              ],
            ),
            _label('Valid until (optional)'),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('card-expiry'),
                    onPressed: _pickExpiry,
                    icon: const Icon(AppIcons.timer, size: 18),
                    label: Text(_expiry == null ? 'Not set' : formatDate(_expiry!)),
                  ),
                ),
                if (_expiry != null)
                  IconButton(
                    key: const ValueKey('card-expiry-clear'),
                    tooltip: tr('Clear the date'),
                    icon: const Icon(AppIcons.close),
                    onPressed: () => setState(() => _expiry = null),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('card-note'),
              controller: _note,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: tr('Note (optional)'),
                hintText: tr('Member name, branch, plan'),
                errorText: noteError?.text,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Do not note a PIN or password here: a note is not protected.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            const SizedBox(height: AppSpacing.lg),
            if (full)
              const Text(
                'You have saved 100 cards, the most there is room for. Delete one to add another.',
                style: TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            FilledButton(key: const ValueKey('card-save'), onPressed: _saving || full ? null : _save, child: const Text('Save card')),
            if (_tried && problems.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'Fix the fields marked above, then save.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

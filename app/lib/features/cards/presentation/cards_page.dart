import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../../qr/domain/scan_services.dart';
import '../data/card_store.dart';
import '../domain/cards.dart';
import 'card_edit_page.dart';

/// The cards saved on this phone, newest used first, to open at the till.
class CardsPage extends StatefulWidget {
  const CardsPage({super.key, this.store = const CardStore(), this.now});
  final CardStore store;
  final DateTime Function()? now;

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  List<LoyaltyCard> _cards = const [];
  bool _loaded = false;
  String _query = '';

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await widget.store.load();
    if (mounted) {
      setState(() {
        _cards = all;
        _loaded = true;
      });
    }
  }

  Future<void> _scanNew() async {
    final code = await context.push<DetectedCode>('/card-scan');
    if (code == null || !mounted) return;
    await context.push<String>(
      '/card-edit',
      extra: CardEditArgs(number: code.raw, type: CardCodeType.fromScan(code.format)),
    );
    if (mounted) await _load();
  }

  Future<void> _typeNew() async {
    await context.push<String>('/card-edit', extra: const CardEditArgs());
    if (mounted) await _load();
  }

  Future<void> _add() async {
    final scan = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('add-scan'),
              leading: const Icon(AppIcons.scanQr),
              title: const Text('Scan the card'),
              subtitle: const Text('With the camera, or from a picture of the card'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              key: const ValueKey('add-type'),
              leading: const Icon(AppIcons.edit),
              title: const Text('Type the number'),
              subtitle: const Text('When the card has a number but no code you can scan'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (scan == null || !mounted) return;
    await (scan ? _scanNew() : _typeNew());
  }

  Future<void> _open(LoyaltyCard c) async {
    await context.push<void>('/card-view', extra: c.id);
    if (mounted) await _load();
  }

  Future<void> _edit(LoyaltyCard c) async {
    await context.push<String>('/card-edit', extra: CardEditArgs(card: c));
    if (mounted) await _load();
  }

  Future<void> _pin(LoyaltyCard c) async {
    await widget.store.put(c.copyWith(pinned: !c.pinned));
    await _load();
  }

  Future<void> _delete(LoyaltyCard c) async {
    final ok = await confirmDestructive(context, title: 'Delete this card?', message: 'The card is removed from this phone. Your real card is not affected.');
    if (!ok || !mounted) return;
    await widget.store.remove(c.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final shown = sortedCards(_cards, query: _query);
    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty cards')),
      floatingActionButton: _cards.isEmpty
          ? null
          : FloatingActionButton.extended(key: const ValueKey('cards-add'), onPressed: _add, icon: const Icon(AppIcons.add), label: const Text('Add card')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
          ? _Empty(onScan: _scanNew, onType: _typeNew)
          : ListView(
              padding: contentPadding(context).copyWith(bottom: 96),
              children: [
                if (_cards.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: TextField(
                      key: const ValueKey('cards-search'),
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(prefixIcon: const Icon(AppIcons.search), hintText: tr('Search your cards')),
                    ),
                  ),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No card matches your search.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                for (final c in shown)
                  _CardTile(card: c, now: _now, onOpen: () => _open(c), onEdit: () => _edit(c), onPin: () => _pin(c), onDelete: () => _delete(c)),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Cards are kept on this phone only. Tap a card to show its code; the screen turns up to full brightness.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                ),
              ],
            ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.now, required this.onOpen, required this.onEdit, required this.onPin, required this.onDelete});
  final LoyaltyCard card;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final validity = validityOf(card, now);
    final (badge, badgeColor) = switch (validity) {
      CardValidity.expired => ('Expired', AppColors.danger),
      CardValidity.soon => ('Runs out soon', AppColors.warning),
      _ => ('', AppColors.inkMuted),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        key: ValueKey('card-${card.id}'),
        onTap: onOpen,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: Color(card.color), borderRadius: BorderRadius.circular(12)),
          child: Icon(categoryIcon(card.category), color: Colors.white),
        ),
        title: Text.rich(
          TextSpan(text: card.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: maskedNumber(card.number)),
              TextSpan(text: '  \u00B7  ${tr(card.category.label)}'),
              if (badge.isNotEmpty)
                TextSpan(
                  text: '  \u00B7  ${tr(badge)}',
                  style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (card.pinned) const Icon(AppIcons.pin, size: 16, color: AppColors.primary),
            PopupMenuButton<int>(
              key: ValueKey('card-menu-${card.id}'),
              tooltip: tr('More'),
              onSelected: (v) => switch (v) {
                0 => onPin(),
                1 => onEdit(),
                _ => onDelete(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 0, child: Text(card.pinned ? 'Unpin' : 'Pin to the top')),
                const PopupMenuItem(value: 1, child: Text('Edit card')),
                const PopupMenuItem(value: 2, child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onScan, required this.onType});
  final VoidCallback onScan;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: contentPadding(context, vertical: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(AppIcons.cards, size: 56, color: AppColors.inkMuted),
          const SizedBox(height: AppSpacing.md),
          const Text('No cards yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Keep the barcodes of your shop, pharmacy, library and club cards here, and show them from your phone at the till. No account, nothing uploaded.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.inkMuted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(key: const ValueKey('empty-scan'), onPressed: onScan, icon: const Icon(AppIcons.scanQr), label: const Text('Scan a card')),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(key: const ValueKey('empty-type'), onPressed: onType, icon: const Icon(AppIcons.edit), label: const Text('Type the number')),
        ],
      ),
    ),
  );
}

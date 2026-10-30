import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/tr.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/text.dart';
import '../../documents/presentation/widgets/document_widgets.dart' show confirmDestructive;
import '../data/card_store.dart';
import '../data/screen_boost.dart';
import '../domain/cards.dart';
import 'card_code_view.dart';
import 'card_edit_page.dart';

/// Shows one card for a scanner at the till: full brightness, the screen kept on, the code large and the number below it.
class CardViewPage extends StatefulWidget {
  const CardViewPage({super.key, required this.cardId, this.store = const CardStore(), this.boost = const ScreenBoost(), this.now});
  final String cardId;
  final CardStore store;
  final ScreenBoost boost;
  final DateTime Function()? now;

  @override
  State<CardViewPage> createState() => _CardViewPageState();
}

class _CardViewPageState extends State<CardViewPage> {
  LoyaltyCard? _card;
  bool _loaded = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.boost.on();
    _load(markUsed: true);
  }

  @override
  void dispose() {
    widget.boost.off();
    super.dispose();
  }

  Future<void> _load({bool markUsed = false}) async {
    final all = await widget.store.load();
    var card = all.where((c) => c.id == widget.cardId).firstOrNull;
    if (card != null && markUsed) {
      card = card.copyWith(usedAt: _now.millisecondsSinceEpoch);
      await widget.store.put(card);
    }
    if (mounted) {
      setState(() {
        _card = card;
        _loaded = true;
      });
    }
  }

  Future<void> _togglePin() async {
    final c = _card!;
    await widget.store.put(c.copyWith(pinned: !c.pinned));
    await _load();
  }

  Future<void> _edit() async {
    await context.push<String>('/card-edit', extra: CardEditArgs(card: _card));
    if (mounted) await _load();
  }

  Future<void> _delete() async {
    final ok = await confirmDestructive(context, title: 'Delete this card?', message: 'The card is removed from this phone. Your real card is not affected.');
    if (!ok || !mounted) return;
    await widget.store.remove(widget.cardId);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _copy(String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (mounted) showMessage(context, 'Copied');
  }

  Widget _validity(LoyaltyCard c) {
    final state = validityOf(c, _now);
    if (state == CardValidity.none) return const SizedBox.shrink();
    final date = formatDate(c.expiry!);
    final (text, color) = switch (state) {
      CardValidity.expired => (trf('Expired on {date}', {'date': date}), AppColors.danger),
      CardValidity.soon => (trf('Valid until {date}. It runs out soon.', {'date': date}), AppColors.warning),
      _ => (trf('Valid until {date}', {'date': date}), AppColors.success),
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        children: [
          Icon(AppIcons.timer, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (card == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _loaded ? const Text('This card was not found.') : const CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text.rich(TextSpan(text: card.name), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('card-pin'),
            tooltip: tr(card.pinned ? 'Unpin' : 'Pin to the top'),
            icon: Icon(AppIcons.pin, color: card.pinned ? AppColors.primary : null),
            onPressed: _togglePin,
          ),
          IconButton(key: const ValueKey('card-edit'), tooltip: tr('Edit card'), icon: const Icon(AppIcons.edit), onPressed: _edit),
          IconButton(key: const ValueKey('card-delete'), tooltip: tr('Delete'), icon: const Icon(AppIcons.delete), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: contentPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: Color(card.color), borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(categoryIcon(card.category), color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(text: card.name),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (card.type.isDrawn)
                    CardCodeView(key: const ValueKey('card-code'), type: card.type, number: card.number, maxHeight: 150)
                  else
                    const SizedBox.shrink(),
                  const SizedBox(height: AppSpacing.sm),
                  Semantics(
                    button: true,
                    label: tr('Copy the number'),
                    child: InkWell(
                      key: const ValueKey('card-number-copy'),
                      onTap: () => _copy(card.number),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Expanded(
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  text: card.number,
                                  style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                                ),
                              ),
                            ),
                            const Icon(AppIcons.copy, size: 18, color: AppColors.inkMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _validity(card),
            if (card.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text.rich(TextSpan(text: card.note), style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'The screen is at full brightness while this card is open. Hold it flat to the scanner. If the till cannot read it, read the number out.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

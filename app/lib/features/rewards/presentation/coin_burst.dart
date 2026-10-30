import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/text.dart';

/// Plays a short "coins added" animation over the screen. Falls back to a message when animations are turned off.
void showCoinsEarned(BuildContext context, int amount) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null || MediaQuery.disableAnimationsOf(context)) {
    showMessage(context, 'You earned $amount coins');
    return;
  }
  HapticFeedback.mediumImpact();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CoinBurst(amount: amount, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

const _coinCount = 14;

class _CoinBurst extends StatefulWidget {
  const _CoinBurst({required this.amount, required this.onDone});
  final int amount;
  final VoidCallback onDone;

  @override
  State<_CoinBurst> createState() => _CoinBurstState();
}

class _CoinBurstState extends State<_CoinBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final origin = Offset(size.width / 2, size.height * 0.42);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0);
          return Stack(
            key: const ValueKey('coin-burst'),
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.18 * fade)),
              ),
              for (var i = 0; i < _coinCount; i++) _coin(i, origin, t),
              Positioned(
                left: 0,
                right: 0,
                top: origin.dy - 52 - 40 * Curves.easeOut.transform((t / 0.9).clamp(0.0, 1.0)),
                child: Opacity(
                  opacity: fade,
                  child: Transform.scale(scale: 0.4 + 0.6 * Curves.elasticOut.transform((t / 0.35).clamp(0.0, 1.0)), child: _badge()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _badge() => Center(
    child: Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.coins, color: AppColors.warning, size: 28),
                const SizedBox(width: 8),
                Text(
                  '+${widget.amount}',
                  key: const ValueKey('coin-burst-amount'),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ],
            ),
            const Text('Coins added', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
          ],
        ),
      ),
    ),
  );

  /// Coins shoot up in a fan, slow down, then drop a little while fading.
  Widget _coin(int i, Offset origin, double t) {
    final rnd = math.Random(i * 7919);
    final delay = i / _coinCount * 0.25;
    final local = ((t - delay) / 0.7).clamp(0.0, 1.0);
    if (local == 0) return const SizedBox.shrink();
    final angle = -math.pi / 2 + (i / (_coinCount - 1) - 0.5) * math.pi * 0.95;
    final distance = 110 + rnd.nextDouble() * 120;
    final out = Curves.easeOutCubic.transform(local);
    final drop = 60 * local * local;
    final dx = math.cos(angle) * distance * out;
    final dy = math.sin(angle) * distance * out + drop;
    final fade = local < 0.7 ? 1.0 : (1 - (local - 0.7) / 0.3);
    final coin = 20 + rnd.nextDouble() * 14;
    return Positioned(
      left: origin.dx + dx - coin / 2,
      top: origin.dy + dy - coin / 2,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: local * math.pi * (rnd.nextBool() ? 2 : -2),
          child: Icon(AppIcons.coins, size: coin, color: AppColors.warning),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/scanned_document.dart';

/// Icons a folder can show, by the key stored with it.
const Map<String, IconData> folderIcons = {
  'folder': LucideIcons.folder,
  'user': LucideIcons.user,
  'users': LucideIcons.users,
  'id': LucideIcons.idCard,
  'bank': LucideIcons.landmark,
  'work': LucideIcons.briefcaseBusiness,
  'car': LucideIcons.car,
  'invoice': LucideIcons.receipt,
  'insurance': LucideIcons.shieldCheck,
  'key': LucideIcons.keyRound,
  'home': LucideIcons.house,
  'school': LucideIcons.graduationCap,
  'health': LucideIcons.heartPulse,
  'medicine': LucideIcons.pill,
  'travel': LucideIcons.plane,
  'shopping': LucideIcons.shoppingCart,
  'wallet': LucideIcons.wallet,
  'card': LucideIcons.creditCard,
  'money': LucideIcons.banknote,
  'tax': LucideIcons.percent,
  'office': LucideIcons.building2,
  'legal': LucideIcons.scale,
  'family': LucideIcons.baby,
  'phone': LucideIcons.smartphone,
  'photo': LucideIcons.camera,
  'book': LucideIcons.bookOpen,
  'tools': LucideIcons.wrench,
  'star': LucideIcons.star,
  'lock': LucideIcons.lock,
  'file': LucideIcons.fileText,
};

/// Accent colours a folder can use, as opaque ARGB values.
const List<int> folderColors = [
  0xFF1D4ED8,
  0xFF0284C7,
  0xFF0D9488,
  0xFF16A34A,
  0xFF65A30D,
  0xFFD97706,
  0xFFEA580C,
  0xFFDC2626,
  0xFFDB2777,
  0xFF9333EA,
  0xFF4F46E5,
  0xFF475569,
];

Color folderAccent(int? color) => Color(color ?? AppColors.primary.toARGB32());

/// A rounded square showing a folder's icon, or the first letter of its name for text-only folders.
class FolderBadge extends StatelessWidget {
  const FolderBadge({super.key, required this.name, required this.icon, required this.color, this.size = 44, this.locked = false});

  FolderBadge.of(Folder folder, {Key? key, double size = 44})
    : this(key: key, name: folder.name, icon: folder.icon, color: folder.color, size: size, locked: folder.locked);

  final String name;
  final String? icon;
  final int? color;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final accent = folderAccent(color);
    final Widget glyph;
    if (icon == FolderStyle.textOnly) {
      final letter = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
      glyph = Text(
        letter,
        style: TextStyle(color: accent, fontSize: size * 0.46, fontWeight: FontWeight.w800, height: 1),
      );
    } else {
      glyph = Icon(folderIcons[icon] ?? LucideIcons.folder, color: accent, size: size * 0.5);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.3),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withValues(alpha: 0.2), accent.withValues(alpha: 0.08)],
                ),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Center(child: glyph),
            ),
          ),
          if (locked)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(LucideIcons.lock, size: size * 0.24, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

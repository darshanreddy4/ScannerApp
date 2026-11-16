import 'package:flutter/material.dart' hide Text;

import '../theme/app_colors.dart';
import 'text.dart';

/// A rounded tile with a white icon on a soft gradient, the same look the Tools page gives each tool.
class GradientIconTile extends StatelessWidget {
  const GradientIconTile({super.key, required this.icon, required this.color, this.size = 40, this.iconSize});
  final IconData icon;
  final Color color;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.28)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd, colors: [light, color]),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize ?? size * 0.54),
    );
  }
}

/// A heading with a short vertical bar in front, as on the Tools page.
class AccentLabel extends StatelessWidget {
  const AccentLabel(this.text, {super.key, this.padding = const EdgeInsetsDirectional.fromSTEB(AppSpacing.xs, AppSpacing.md, 0, AppSpacing.sm + 2)});
  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: 0.2),
          ),
        ),
      ],
    ),
  );
}

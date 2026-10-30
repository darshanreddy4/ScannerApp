import 'package:flutter/material.dart' hide Text;
import 'text.dart';

/// Toggle chip for dark surfaces (camera, markup) with fixed colours, so the label is always readable.
class DarkChip extends StatelessWidget {
  const DarkChip({super.key, required this.label, required this.selected, required this.onTap, this.bold = false, this.selectedColor = Colors.white});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool bold;

  /// Fill when selected; the label turns dark on white and white on anything else.
  final Color selectedColor;

  @override
  Widget build(BuildContext context) {
    final onLight = selectedColor.computeLuminance() > 0.5;
    final textColor = selected ? (onLight ? Colors.black : Colors.white) : Colors.white;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? selectedColor : const Color(0xFF2A3447),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(color: textColor, fontSize: 14, fontWeight: bold || selected ? FontWeight.w700 : FontWeight.w500),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

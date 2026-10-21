import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../domain/entities/filter_settings.dart';
import '../bloc/scan_session_cubit.dart';

class EnhancePage extends StatelessWidget {
  const EnhancePage({super.key});

  Future<void> _done(BuildContext context) async {
    final session = context.read<ScanSessionCubit>();
    final ok = await session.commitDraft();
    if (!context.mounted) return;
    if (ok) {
      context.go('/scan/review');
    } else if (session.state.error != null) {
      showFailure(context, session.state.error!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = context.select((ScanSessionCubit c) => c.state.draft);
    final busy = context.select((ScanSessionCubit c) => c.state.busy);
    final previewBusy = context.select((ScanSessionCubit c) => c.state.previewBusy);
    if (draft == null) return const Scaffold(backgroundColor: AppColors.scannerBackdrop);

    final cubit = context.read<ScanSessionCubit>();
    final settings = draft.settings;

    return Scaffold(
      backgroundColor: AppColors.scannerBackdrop,
      appBar: AppBar(
        backgroundColor: AppColors.scannerBackdrop,
        foregroundColor: Colors.white,
        leading: IconButton(icon: const Icon(AppIcons.back), onPressed: () => context.pop()),
        title: const Text('Enhance', style: TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: busy ? null : () => _done(context),
            child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (draft.preview != null)
                          Image.memory(draft.preview!, fit: BoxFit.contain, gaplessPlayback: true)
                        else
                          const CircularProgressIndicator(color: Colors.white),
                        if (previewBusy && draft.preview != null)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  color: const Color(0xFF111827),
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FilterStrip(
                        selected: settings.filter,
                        onSelected: (f) => cubit.updateSettings(settings.copyWith(filter: f), immediate: true),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _AdjustSlider(
                        icon: AppIcons.brightness,
                        label: 'Brightness',
                        value: settings.brightness,
                        onChanged: (v) => cubit.updateSettings(settings.copyWith(brightness: v)),
                      ),
                      _AdjustSlider(
                        icon: AppIcons.contrast,
                        label: 'Contrast',
                        value: settings.contrast,
                        onChanged: (v) => cubit.updateSettings(settings.copyWith(contrast: v)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            BusyOverlay(visible: busy, label: 'Rendering page'),
          ],
        ),
      ),
    );
  }
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.selected, required this.onSelected});

  final ScanFilter selected;
  final ValueChanged<ScanFilter> onSelected;

  static const _items = [
    (ScanFilter.original, AppIcons.filterOriginal, 'Original'),
    (ScanFilter.documentBw, AppIcons.filterDocument, 'Document'),
    (ScanFilter.magicColor, AppIcons.filterMagic, 'Magic color'),
    (ScanFilter.grayscale, AppIcons.filterGray, 'Grayscale'),
  ];

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final (filter, icon, label) in _items)
            _FilterChip(icon: icon, label: label, selected: filter == selected, onTap: () => onSelected(filter)),
        ],
      );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            width: 76,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white10,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      );
}

class _AdjustSlider extends StatelessWidget {
  const _AdjustSlider({required this.icon, required this.label, required this.value, required this.onChanged});

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          Expanded(
            child: Slider(
              value: value,
              min: -100,
              max: 100,
              label: '$label ${value.round()}',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text('${value.round()}', textAlign: TextAlign.end, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ),
        ],
      );
}

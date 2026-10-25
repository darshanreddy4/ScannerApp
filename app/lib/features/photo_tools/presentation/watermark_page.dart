import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../data/watermark_stamp.dart';
import '../domain/watermark.dart';
import '../domain/watermark_service.dart';
import 'watermark_cubit.dart';

/// Puts a business name, logo or words such as CONFIDENTIAL over photos and PDF pages.
class WatermarkPage extends StatelessWidget {
  const WatermarkPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => WatermarkCubit(service: sl<WatermarkService>(), profiles: sl<BusinessProfileStore>(), outputDir: getTemporaryDirectory)..load(),
    child: const _WatermarkView(),
  );
}

class _WatermarkView extends StatelessWidget {
  const _WatermarkView();

  Future<void> _pickGallery(BuildContext context) async {
    try {
      final files = await ImagePicker().pickMultiImage();
      if (files.isEmpty || !context.mounted) return;
      await context.read<WatermarkCubit>().add([for (final f in files) f.path]);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  Future<void> _pickFiles(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf']);
      final paths = [
        for (final f in picked)
          if (f.path != null) f.path!,
      ];
      if (paths.isEmpty || !context.mounted) return;
      await context.read<WatermarkCubit>().add(paths);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<WatermarkCubit, WatermarkState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, s) {
        showFailure(context, s.failure!);
        context.read<WatermarkCubit>().clearFailure();
      },
      builder: (context, state) {
        final cubit = context.read<WatermarkCubit>();
        final running = state.status == WatermarkStatus.running;
        final firstImage = state.inputs.where((i) => !i.isPdf).firstOrNull;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Add watermark'),
            actions: [if (state.inputs.isNotEmpty && !running) TextButton(onPressed: cubit.clear, child: const Text('Clear'))],
          ),
          body: SafeArea(
            child: ListView(
              padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running ? null : () => _pickGallery(context),
                        icon: const Icon(AppIcons.gallery, size: 18),
                        label: const Text('Photos'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: running ? null : () => _pickFiles(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Files'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.inputs.isEmpty)
                  const _Hint(text: 'Add photos or PDF files. You can mark many at once and see the result below before you start.')
                else
                  for (final input in state.inputs)
                    _InputRow(
                      input: input,
                      outcome: state.outcomes.where((o) => o.input == input).firstOrNull,
                      running: running,
                      onRemove: () => cubit.remove(input.path),
                    ),
                if (state.skipped > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      '${state.skipped} file${state.skipped == 1 ? ' was' : 's were'} skipped. Only JPG, PNG and PDF files can be marked.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                const _Label('Preview'),
                _Preview(imagePath: firstImage?.path, style: state.style, businessName: state.profile.name),
                if (state.inputs.any((i) => i.isPdf) && firstImage == null)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'A sample page is shown. Every page of your PDF gets the same mark.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                const _TextControls(),
                const SizedBox(height: AppSpacing.md),
                const _StyleControls(),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: state.inputs.isEmpty || running ? null : cubit.run,
                  icon: running
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(AppIcons.watermark, size: 18),
                  label: Text(running ? 'Marking ${state.progress} of ${state.inputs.length}' : 'Add watermark'),
                ),
                if (state.outputs.isNotEmpty) ...[const SizedBox(height: AppSpacing.md), _Results(outputs: state.outputs)],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.info, size: 20, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
      ),
    ),
  );
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.input, required this.outcome, required this.running, required this.onRemove});
  final WatermarkInput input;
  final WatermarkOutcome? outcome;
  final bool running;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final failed = outcome?.failure != null;
    final done = outcome?.output != null;
    final detail = failed
        ? outcome!.failure!.message
        : (done ? 'Watermark added${outcome!.output!.isPdf ? ' to ${outcome!.output!.pages} pages' : ''}' : formatBytes(input.bytes));
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        dense: true,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 44,
            height: 44,
            child: input.isPdf
                ? const ColoredBox(
                    color: AppColors.primarySoft,
                    child: Icon(AppIcons.pdf, color: AppColors.primary),
                  )
                : Image.file(File(input.path), fit: BoxFit.cover, cacheWidth: 100, errorBuilder: (_, _, _) => const Icon(AppIcons.gallery)),
          ),
        ),
        title: Text(input.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(detail, style: TextStyle(fontSize: 12.5, color: failed ? AppColors.danger : (done ? AppColors.success : AppColors.inkMuted))),
        trailing: running ? null : IconButton(tooltip: 'Remove', icon: const Icon(AppIcons.close, size: 18), onPressed: onRemove),
      ),
    );
  }
}

// region preview

/// Draws the picture and the watermark with the same rules the final file uses, so what is seen is what is saved.
class _Preview extends StatefulWidget {
  const _Preview({required this.imagePath, required this.style, required this.businessName});
  final String? imagePath;
  final WatermarkStyle style;
  final String businessName;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  static const _renderer = WatermarkStampRenderer();
  static const _sampleW = 595, _sampleH = 842;

  ui.Image? _base;
  ui.Image? _stamp;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void didUpdateWidget(_Preview old) {
    super.didUpdateWidget(old);
    if (old.imagePath != widget.imagePath) {
      _loadBase();
    } else if (old.style != widget.style || old.businessName != widget.businessName) {
      _scheduleStamp();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    _base?.dispose();
    _stamp?.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final generation = ++_generation;
    final path = widget.imagePath;
    ui.Image? loaded;
    if (path != null) {
      try {
        final codec = await ui.instantiateImageCodec(await File(path).readAsBytes(), targetWidth: 900);
        loaded = (await codec.getNextFrame()).image;
        codec.dispose();
      } catch (_) {
        loaded = null;
      }
    }
    if (!mounted || generation != _generation) {
      loaded?.dispose();
      return;
    }
    final old = _base;
    setState(() => _base = loaded);
    old?.dispose();
    await _makeStamp(generation);
  }

  void _scheduleStamp() {
    _debounce?.cancel();
    final generation = ++_generation;
    _debounce = Timer(const Duration(milliseconds: 120), () => _makeStamp(generation));
  }

  Future<void> _makeStamp(int generation) async {
    final w = _base?.width ?? _sampleW, h = _base?.height ?? _sampleH;
    final text = WatermarkPresets.fill(widget.style.text, name: widget.businessName, date: DateTime.now());
    ui.Image? stamp;
    try {
      stamp = await _renderer.renderImage(style: widget.style, text: text, shortSide: w < h ? w : h);
    } catch (_) {
      stamp = null;
    }
    if (!mounted || generation != _generation) {
      stamp?.dispose();
      return;
    }
    final old = _stamp;
    setState(() => _stamp = stamp);
    old?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = _base?.width ?? _sampleW, h = _base?.height ?? _sampleH;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: Colors.white,
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: AspectRatio(
          aspectRatio: w / h,
          child: CustomPaint(
            key: const ValueKey('watermark-preview'),
            painter: _PreviewPainter(base: _base, stamp: _stamp, style: widget.style, width: w, height: h),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter({required this.base, required this.stamp, required this.style, required this.width, required this.height});
  final ui.Image? base;
  final ui.Image? stamp;
  final WatermarkStyle style;
  final int width;
  final int height;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / width;
    canvas.clipRect(Offset.zero & size);
    if (base != null) {
      canvas.drawImageRect(
        base!,
        Rect.fromLTWH(0, 0, base!.width.toDouble(), base!.height.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      // A sample page with grey lines of text.
      final line = Paint()..color = const Color(0xFFE2E8F0);
      for (var i = 0; i < 24; i++) {
        final y = size.height * (0.08 + i * 0.036);
        canvas.drawRect(Rect.fromLTWH(size.width * 0.08, y, size.width * (i % 5 == 4 ? 0.5 : 0.84), size.height * 0.012), line);
      }
    }
    final s = stamp;
    if (s == null) return;
    final spots = WatermarkPlacement.spots(
      imageWidth: width,
      imageHeight: height,
      stampWidth: s.width,
      stampHeight: s.height,
      layout: style.layout,
      position: style.position,
    );
    final src = Rect.fromLTWH(0, 0, s.width.toDouble(), s.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;
    for (final spot in spots) {
      canvas.drawImageRect(s, src, Rect.fromLTWH(spot.x * scale, spot.y * scale, s.width * scale, s.height * scale), paint);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.base != base || old.stamp != stamp || old.style.layout != style.layout || old.style.position != style.position;
}

// endregion

// region controls

class _TextControls extends StatelessWidget {
  const _TextControls();

  Future<void> _editBusiness(BuildContext context) async {
    final cubit = context.read<WatermarkCubit>();
    final result = await showDialog<({BusinessProfile profile, String? logo})>(
      context: context,
      builder: (_) => _BusinessDialog(initial: cubit.state.profile),
    );
    if (result != null) await cubit.saveProfile(result.profile, newLogoSource: result.logo);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<WatermarkCubit>().state;
    final cubit = context.read<WatermarkCubit>();
    final style = state.style;
    final profile = state.profile;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Label('Words'),
            _WatermarkTextField(value: style.text, onChanged: cubit.setText),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [for (final preset in WatermarkPresets.all) ActionChip(label: Text(preset.$1), onPressed: () => cubit.setText(preset.$2))],
            ),
            const SizedBox(height: AppSpacing.md),
            const _Label('Business details'),
            if (profile.isEmpty)
              const Text(
                'Save your business name, GST or phone number and logo once, then add them to any document in one tap.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
              )
            else
              Text(profile.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                if (!profile.isEmpty)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: cubit.useBusinessDetails,
                    icon: const Icon(AppIcons.check, size: 18),
                    label: const Text('Use my details'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () => _editBusiness(context),
                  icon: const Icon(AppIcons.edit, size: 18),
                  label: Text(profile.isEmpty ? 'Add business details' : 'Edit details'),
                ),
              ],
            ),
            if (style.logoPath != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(style.logoPath!),
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(AppIcons.gallery),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: Text('Logo is added above the words', style: TextStyle(fontSize: 13))),
                  TextButton(onPressed: () => cubit.setLogo(null), child: const Text('Remove')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A text field that follows the state without moving the cursor while typing.
class _WatermarkTextField extends StatefulWidget {
  const _WatermarkTextField({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_WatermarkTextField> createState() => _WatermarkTextFieldState();
}

class _WatermarkTextFieldState extends State<_WatermarkTextField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_WatermarkTextField old) {
    super.didUpdateWidget(old);
    // A preset or "Use my details" changes the words from outside; typing already matches the state.
    if (widget.value != _controller.text)
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    minLines: 1,
    maxLines: 3,
    maxLength: 120,
    textCapitalization: TextCapitalization.sentences,
    decoration: const InputDecoration(hintText: 'For example CONFIDENTIAL', counterText: ''),
    onChanged: widget.onChanged,
  );
}

class _StyleControls extends StatelessWidget {
  const _StyleControls();

  @override
  Widget build(BuildContext context) {
    final style = context.watch<WatermarkCubit>().state.style;
    final cubit = context.read<WatermarkCubit>();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Label('Layout'),
            SegmentedButton<WatermarkLayout>(
              showSelectedIcon: false,
              segments: [for (final l in WatermarkLayout.values) ButtonSegment(value: l, label: Text(l.label))],
              selected: {style.layout},
              onSelectionChanged: (s) => cubit.setLayout(s.first),
            ),
            if (style.layout == WatermarkLayout.single) ...[
              const SizedBox(height: AppSpacing.md),
              const _Label('Position'),
              _PositionGrid(selected: style.position, onSelected: cubit.setPosition),
            ],
            const SizedBox(height: AppSpacing.sm),
            _SliderRow(
              label: 'Size',
              value: style.size,
              min: WatermarkStyle.minSize,
              max: WatermarkStyle.maxSize,
              onChanged: cubit.setSize,
              text: '${(style.size * 100).round()}%',
            ),
            _SliderRow(
              label: 'Strength',
              value: style.opacity,
              min: WatermarkStyle.minOpacity,
              max: 1,
              onChanged: cubit.setOpacity,
              text: '${(style.opacity * 100).round()}%',
            ),
            _SliderRow(
              label: 'Angle',
              value: style.rotation,
              min: -90,
              max: 90,
              divisions: 36,
              onChanged: cubit.setRotation,
              text: '${style.rotation.round()}°',
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final a in const [(0.0, 'Straight'), (-30.0, 'Diagonal'), (-45.0, 'Steep diagonal')])
                  ChoiceChip(label: Text(a.$2), selected: style.rotation == a.$1, onSelected: (_) => cubit.setRotation(a.$1)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const _Label('Colour'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in WatermarkColor.values)
                  ChoiceChip(
                    avatar: CircleAvatar(
                      backgroundColor: Color(c.argb),
                      radius: 8,
                      child: c == WatermarkColor.white
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.border),
                              ),
                            )
                          : null,
                    ),
                    label: Text(c.label),
                    selected: style.color == c,
                    onSelected: (_) => cubit.setColor(c),
                  ),
              ],
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Bold letters'), value: style.bold, onChanged: cubit.setBold),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.text,
    this.divisions,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 64,
        child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
      ),
      Expanded(
        child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
      ),
      SizedBox(
        width: 44,
        child: Text(
          text,
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
        ),
      ),
    ],
  );
}

class _PositionGrid extends StatelessWidget {
  const _PositionGrid({required this.selected, required this.onSelected});
  final WatermarkPosition selected;
  final ValueChanged<WatermarkPosition> onSelected;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 132,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        children: [
          for (final p in WatermarkPosition.values)
            Semantics(
              button: true,
              selected: p == selected,
              label: 'Position ${p.name}',
              child: InkWell(
                onTap: () => onSelected(p),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: p == selected ? AppColors.primary : AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p == selected ? AppColors.primaryDark : AppColors.border),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _BusinessDialog extends StatefulWidget {
  const _BusinessDialog({required this.initial});
  final BusinessProfile initial;

  @override
  State<_BusinessDialog> createState() => _BusinessDialogState();
}

class _BusinessDialogState extends State<_BusinessDialog> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _details = TextEditingController(text: widget.initial.details);
  String? _logo;
  late String? _current = widget.initial.logoPath;

  @override
  void dispose() {
    _name.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null && mounted) setState(() => _logo = picked.path);
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _logo ?? _current;
    return AlertDialog(
      title: const Text('Business details'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Business name', counterText: ''),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _details,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Second line', hintText: 'GST number, phone or website', counterText: ''),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (shown != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(shown), width: 44, height: 44, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(AppIcons.gallery)),
                  )
                else
                  const Icon(AppIcons.gallery, color: AppColors.inkMuted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(onPressed: _pickLogo, child: Text(shown == null ? 'Add logo' : 'Change logo')),
                ),
                if (shown != null)
                  IconButton(
                    tooltip: 'Remove logo',
                    icon: const Icon(AppIcons.close, size: 18),
                    onPressed: () => setState(() {
                      _logo = null;
                      _current = null;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(context, (profile: BusinessProfile(name: _name.text, details: _details.text, logoPath: _current), logo: _logo)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// endregion

// region results

class _Results extends StatelessWidget {
  const _Results({required this.outputs});
  final List<WatermarkOutput> outputs;

  Future<void> _share(BuildContext context) async {
    final mime = outputs.every((o) => o.isPdf) ? 'application/pdf' : (outputs.every((o) => !o.isPdf) ? 'image/*' : '*/*');
    final failure = (await sl<ShareService>().shareFiles(paths: [for (final o in outputs) o.path], mimeType: mime)).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _gallery(BuildContext context) async {
    final images = [
      for (final o in outputs)
        if (!o.isPdf) o.path,
    ];
    final result = await sl<SaveService>().saveImagesToGallery(images);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    failure != null ? showFailure(context, failure) : showMessage(context, 'Saved ${images.length} to your gallery');
  }

  Future<void> _files(BuildContext context, WatermarkOutput o) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: o.path, fileName: o.name.replaceAll(' ', '_'), mimeType: o.mimeType);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImages = outputs.any((o) => !o.isPdf);
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(outputs.length == 1 ? 'Your file is ready' : '${outputs.length} files are ready', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => _share(context),
                  icon: const Icon(AppIcons.share, size: 18),
                  label: const Text('Share'),
                ),
                if (hasImages)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => _gallery(context),
                    icon: const Icon(AppIcons.download, size: 18),
                    label: const Text('Save to gallery'),
                  ),
                if (outputs.length == 1)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: () => _files(context, outputs.first),
                    icon: const Icon(AppIcons.storage, size: 18),
                    label: const Text('Save to Files'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// endregion

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/crop_math.dart';
import '../domain/passport_maker.dart';
import '../domain/photo_compressor.dart';
import '../domain/photo_specs.dart';
import 'passport_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Makes passport, visa and ID photos in the size each country asks for, then saves, shares or prints them.
class PassportPhotoPage extends StatefulWidget {
  const PassportPhotoPage({super.key});

  @override
  State<PassportPhotoPage> createState() => _PassportPhotoPageState();
}

class _PassportPhotoPageState extends State<PassportPhotoPage> {
  static const _countryKey = 'photo_country';
  late final Future<String?> _saved = SharedPreferences.getInstance().then((p) => p.getString(_countryKey)).catchError((_) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _saved,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return BlocProvider(
        create: (_) => PassportCubit(maker: sl<PassportMaker>(), compressor: sl<PhotoCompressor>(), workDir: getTemporaryDirectory, countryCode: snapshot.data),
        child: const _PassportView(),
      );
    },
  );
}

class _PassportView extends StatelessWidget {
  const _PassportView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PassportCubit, PassportState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, s) {
        showFailure(context, s.failure!);
        context.read<PassportCubit>().clearFailure();
      },
      builder: (context, state) {
        final cubit = context.read<PassportCubit>();
        final title = switch (state.step) {
          PassportStep.choose => 'Passport and ID photo',
          PassportStep.edit => 'Adjust the photo',
          PassportStep.result => 'Your photo',
        };
        return PopScope(
          canPop: state.step == PassportStep.choose,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cubit.back();
          },
          child: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(
              child: Stack(
                children: [
                  switch (state.step) {
                    PassportStep.choose => const _ChooseStep(),
                    PassportStep.edit => const _EditStep(),
                    PassportStep.result => const _ResultStep(),
                  },
                  BusyOverlay(visible: state.busy, label: 'Working...'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// region choose

class _ChooseStep extends StatelessWidget {
  const _ChooseStep();

  Future<void> _pickCountry(BuildContext context) async {
    final code = await showModalBottomSheet<String>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _CountrySheet());
    if (code == null || !context.mounted) return;
    context.read<PassportCubit>().selectCountry(code);
    try {
      (await SharedPreferences.getInstance()).setString(_PassportPhotoPageState._countryKey, code);
    } catch (_) {
      // Remembering the country is a convenience only.
    }
  }

  Future<void> _customSize(BuildContext context) async {
    final spec = await showDialog<PhotoSpec>(
      context: context,
      builder: (_) => _CustomSizeDialog(initial: context.read<PassportCubit>().state.custom),
    );
    if (spec != null && context.mounted) context.read<PassportCubit>().useCustom(spec);
  }

  Future<void> _pick(BuildContext context, Future<String?> Function() source) async {
    try {
      final path = await source();
      if (path == null || !context.mounted) return;
      await context.read<PassportCubit>().pickPhoto(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The camera or photo library is unavailable. Check the permissions in Settings.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassportCubit>().state;
    final cubit = context.read<PassportCubit>();
    final country = state.country;
    return ListView(
      padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
      children: [
        const _Label('Country'),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: _CodeBadge(code: country.code),
            title: Text(country.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Tap to change'),
            trailing: const Icon(AppIcons.next, size: 18),
            onTap: () => _pickCountry(context),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Label('Photo type'),
        for (final spec in country.specs)
          _SpecTile(spec: spec, selected: state.spec.id == spec.id && state.spec.id != 'custom', onTap: () => cubit.selectSpec(spec)),
        _SpecTile(
          spec: state.custom ?? PhotoSpec.custom(widthMm: 0, heightMm: 0),
          customEmpty: state.custom == null,
          selected: state.spec.id == 'custom',
          onTap: () => state.custom == null || state.spec.id == 'custom' ? _customSize(context) : cubit.useCustom(state.custom!),
          onEdit: state.custom == null ? null : () => _customSize(context),
        ),
        const SizedBox(height: AppSpacing.sm),
        const _Note(text: 'Sizes can change. Before you submit, check the size, background and head position your passport office, embassy or form asks for.'),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: state.busy
              ? null
              : () => _pick(context, () async => (await ImagePicker().pickImage(source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear))?.path),
          icon: const Icon(AppIcons.camera, size: 18),
          label: const Text('Take a photo'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: state.busy ? null : () => _pick(context, () async => (await ImagePicker().pickImage(source: ImageSource.gallery))?.path),
                icon: const Icon(AppIcons.gallery, size: 18),
                label: const Text('Gallery'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () => _pick(context, () async {
                        final picked = await FilePicker.pickFiles(type: FileType.image);
                        return picked.isEmpty ? null : picked.first.path;
                      }),
                icon: const Icon(AppIcons.importFile, size: 18),
                label: const Text('Files'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const _Note(text: 'Tip: stand in front of a plain, evenly lit wall, look straight at the camera with a neutral face, and keep the phone at eye level.'),
      ],
    );
  }
}

class _SpecTile extends StatelessWidget {
  const _SpecTile({required this.spec, required this.selected, required this.onTap, this.customEmpty = false, this.onEdit});
  final PhotoSpec spec;
  final bool selected;
  final bool customEmpty;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final detail = customEmpty
        ? 'Enter your own width and height'
        : [
            spec.sizeLabelFull,
            if (spec.headMinMm != null) 'head ${_n(spec.headMinMm!)} to ${_n(spec.headMaxMm!)} mm',
            if (spec.note != null && spec.id != 'custom') spec.note!,
          ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: selected ? AppColors.primarySoft : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      ),
      child: ListTile(
        leading: Icon(selected ? AppIcons.check : AppIcons.idPhoto, color: selected ? AppColors.primary : AppColors.inkMuted),
        title: Text(customEmpty ? 'Custom size' : spec.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(detail, style: const TextStyle(fontSize: 12.5)),
        trailing: onEdit == null ? null : IconButton(tooltip: tr('Change size'), icon: const Icon(AppIcons.edit, size: 18), onPressed: onEdit),
        onTap: onTap,
      ),
    );
  }

  static String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _CodeBadge extends StatelessWidget {
  const _CodeBadge({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
    child: Text(
      code,
      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
    ),
  );
}

class _CountrySheet extends StatefulWidget {
  const _CountrySheet();

  @override
  State<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends State<_CountrySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final countries = PhotoCatalog.search(_query);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(hintText: tr('Search country'), prefixIcon: Icon(AppIcons.search, size: 20), isDense: true),
                ),
              ),
              Expanded(
                child: countries.isEmpty
                    ? const Center(
                        child: Text('No country found. Use Custom size instead.', style: TextStyle(color: AppColors.inkMuted)),
                      )
                    : ListView.builder(
                        itemCount: countries.length,
                        itemBuilder: (_, i) {
                          final c = countries[i];
                          return ListTile(
                            leading: _CodeBadge(code: c.code),
                            title: Text(c.name),
                            subtitle: Text(c.specs.map((s) => s.sizeLabel).toSet().join(', '), style: const TextStyle(fontSize: 12)),
                            onTap: () => Navigator.pop(context, c.code),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomSizeDialog extends StatefulWidget {
  const _CustomSizeDialog({this.initial});
  final PhotoSpec? initial;

  @override
  State<_CustomSizeDialog> createState() => _CustomSizeDialogState();
}

enum _Unit { mm, inch, px }

class _CustomSizeDialogState extends State<_CustomSizeDialog> {
  late final _w = TextEditingController(text: widget.initial == null ? '' : _show(widget.initial!.widthMm));
  late final _h = TextEditingController(text: widget.initial == null ? '' : _show(widget.initial!.heightMm));
  _Unit _unit = _Unit.mm;
  String? _error;

  static String _show(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  double? _read(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final w = _read(_w), h = _read(_h);
    if (w == null || h == null || w <= 0 || h <= 0) {
      setState(() => _error = 'Enter both width and height.');
      return;
    }
    switch (_unit) {
      case _Unit.mm:
        if (w < 10 || h < 10 || w > 150 || h > 150) return setState(() => _error = 'Use sizes between 10 and 150 mm.');
        Navigator.pop(context, PhotoSpec.custom(widthMm: w, heightMm: h));
      case _Unit.inch:
        if (w < 0.4 || h < 0.4 || w > 6 || h > 6) return setState(() => _error = 'Use sizes between 0.4 and 6 inches.');
        Navigator.pop(context, PhotoSpec.custom(widthMm: w * 25.4, heightMm: h * 25.4));
      case _Unit.px:
        if (w < 50 || h < 50 || w > 3000 || h > 3000) return setState(() => _error = 'Use sizes between 50 and 3000 pixels.');
        final wp = w.round(), hp = h.round();
        Navigator.pop(context, PhotoSpec.custom(widthMm: wp / 300 * 25.4, heightMm: hp / 300 * 25.4, widthPx: wp, heightPx: hp));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Custom size'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<_Unit>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Unit.mm, label: Text('mm')),
              ButtonSegment(value: _Unit.inch, label: Text('inch')),
              ButtonSegment(value: _Unit.px, label: Text('pixels')),
            ],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() {
              _unit = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _numberField(_w, 'Width')),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _numberField(_h, 'Height')),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ),
          if (_unit == _Unit.px)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text('For online forms: the photo is made with exactly these pixels.', style: TextStyle(fontSize: 12, color: AppColors.inkMuted)),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: _save, child: const Text('Use')),
    ],
  );

  Widget _numberField(TextEditingController c, String label) => TextField(
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() => _error = null),
    onSubmitted: (_) => _save(),
  );
}

// endregion

// region edit

class _EditStep extends StatefulWidget {
  const _EditStep();

  @override
  State<_EditStep> createState() => _EditStepState();
}

class _EditStepState extends State<_EditStep> {
  bool _guide = true;

  /// While a finger is on the photo the list must not scroll, or dragging the photo would scroll the screen.
  bool _holding = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassportCubit>().state;
    final cubit = context.read<PassportCubit>();
    final photo = state.working, view = state.view;
    if (photo == null || view == null) return const SizedBox.shrink();
    final spec = state.spec;
    final guide = HeadGuide.forPhoto(headMm: spec.headTargetMm, photoWidthMm: spec.widthMm, photoHeightMm: spec.heightMm);
    final exact = spec.exactWidthPx != null;

    return LayoutBuilder(
      builder: (context, box) {
        // The frame is as large as the screen allows but leaves room for the controls below it.
        final maxW = (box.maxWidth - 2 * AppSpacing.md).clamp(120.0, 480.0);
        final maxH = (box.maxHeight * 0.55).clamp(160.0, 560.0);
        final frameW = (maxH * spec.aspect).clamp(0.0, maxW);
        final frameH = frameW / spec.aspect;

        return ListView(
          physics: _holding ? const NeverScrollableScrollPhysics() : null,
          padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
          children: [
            Text(
              '${spec.name} · ${spec.sizeLabel}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: Listener(
                onPointerDown: (_) => setState(() => _holding = true),
                onPointerUp: (_) => setState(() => _holding = false),
                onPointerCancel: (_) => setState(() => _holding = false),
                child: _CropFrame(photo: photo, view: view, spec: spec, width: frameW, height: frameH, guide: _guide ? guide : null),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Drag to move and pinch to zoom. Keep the head inside the oval and the eyes on the line.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(AppIcons.fullFrame, size: 16, color: AppColors.inkMuted),
                Expanded(
                  child: Slider(value: view.zoom, min: 1, max: CropView.maxZoom, onChanged: cubit.setZoom),
                ),
                Text('${view.zoom.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              children: [
                TextButton.icon(onPressed: cubit.rotate, icon: const Icon(AppIcons.rotate, size: 18), label: const Text('Rotate')),
                TextButton.icon(onPressed: cubit.resetView, icon: const Icon(AppIcons.reset, size: 18), label: const Text('Reset')),
                TextButton.icon(
                  onPressed: () => setState(() => _guide = !_guide),
                  icon: const Icon(AppIcons.autoCapture, size: 18),
                  label: Text(_guide ? 'Hide guide' : 'Show guide'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Replace the background'),
                      subtitle: const Text('Works best on a plain, evenly lit wall.'),
                      value: state.replaceBackground,
                      onChanged: cubit.setReplaceBackground,
                    ),
                    if (state.replaceBackground) ...[
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final b in PhotoBackground.values)
                            ChoiceChip(
                              avatar: CircleAvatar(backgroundColor: Color(b.argb), radius: 8),
                              label: Text(b.label),
                              selected: state.background == b,
                              onSelected: (_) => cubit.setBackground(b),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Strength', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
                          Expanded(
                            child: Slider(
                              value: state.cleanStrength.toDouble(),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${state.cleanStrength}',
                              onChanged: (v) => cubit.setStrength(v.round()),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'If the person is partly erased, lower the strength. If wall is left, raise it.',
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (!exact) ...[
              const _Label('Quality'),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 300, label: Text('Standard 300 dpi')),
                  ButtonSegment(value: 600, label: Text('High 600 dpi')),
                ],
                selected: {state.dpi},
                onSelectionChanged: (s) => cubit.setDpi(s.first),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              'Result: ${spec.pixelWidth(state.dpi)} x ${spec.pixelHeight(state.dpi)} pixels',
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(onPressed: state.busy ? null : cubit.create, icon: const Icon(AppIcons.check, size: 18), label: const Text('Create photo')),
          ],
        );
      },
    );
  }
}

/// The photo behind a fixed frame in the shape of the final picture. The photo is moved and zoomed under it.
class _CropFrame extends StatefulWidget {
  const _CropFrame({required this.photo, required this.view, required this.spec, required this.width, required this.height, required this.guide});
  final WorkingPhoto photo;
  final CropView view;
  final PhotoSpec spec;
  final double width;
  final double height;
  final HeadGuide? guide;

  @override
  State<_CropFrame> createState() => _CropFrameState();
}

class _CropFrameState extends State<_CropFrame> {
  double _startZoom = 1;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PassportCubit>();
    final state = cubit.state;
    final rect = widget.view.rect(widget.photo.width, widget.photo.height, state.frameW, state.frameH);
    // Frame pixels per photo pixel.
    final scale = widget.width / rect.width;
    return GestureDetector(
      onScaleStart: (_) => _startZoom = cubit.state.view?.zoom ?? 1,
      onScaleUpdate: (d) {
        cubit.pan(d.focalPointDelta.dx / widget.width, d.focalPointDelta.dy / widget.height);
        if (d.pointerCount > 1) cubit.setZoom(_startZoom * d.scale);
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: Colors.black12,
        ),
        child: ClipRect(
          key: const ValueKey('crop-frame'),
          child: Stack(
            children: [
              Positioned(
                left: -rect.left * scale,
                top: -rect.top * scale,
                width: widget.photo.width * scale,
                height: widget.photo.height * scale,
                child: Image.file(
                  File(widget.photo.path),
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                ),
              ),
              if (widget.guide != null) Positioned.fill(child: CustomPaint(painter: _GuidePainter(widget.guide!))),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.guide);
  final HeadGuide guide;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, (guide.top + guide.height / 2) * size.height),
      width: guide.width * size.width,
      height: guide.height * size.height,
    );
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = Colors.black54;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = Colors.white;
    for (final paint in [shadow, line]) {
      canvas.drawOval(oval, paint);
    }
    // Eye line and centre line.
    final eyeY = guide.eyeLine * size.height;
    for (final paint in [shadow, line]) {
      canvas.drawLine(Offset(size.width * 0.22, eyeY), Offset(size.width * 0.78, eyeY), paint);
      _dashed(canvas, Offset(size.width / 2, 0), Offset(size.width / 2, size.height), paint);
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 8.0, gap = 7.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, total), paint..strokeWidth = paint.strokeWidth);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.guide != guide;
}

// endregion

// region result

class _ResultStep extends StatefulWidget {
  const _ResultStep();

  @override
  State<_ResultStep> createState() => _ResultStepState();
}

class _ResultStepState extends State<_ResultStep> {
  SheetPaper _paper = SheetPaper.photo4x6;
  int? _copies;

  static const _limits = <(String, int)>[('20 kB', 20 * 1024), ('50 kB', 50 * 1024), ('100 kB', 100 * 1024), ('200 kB', 200 * 1024), ('500 kB', 500 * 1024)];

  Future<void> _share(BuildContext context, List<String> paths, String mime) async {
    final failure = (await sl<ShareService>().shareFiles(paths: paths, mimeType: mime)).failureOrNull;
    if (failure != null && context.mounted) showFailure(context, failure);
  }

  Future<void> _gallery(BuildContext context, String path) async {
    final result = await sl<SaveService>().saveImagesToGallery([path]);
    if (!context.mounted) return;
    final failure = result.failureOrNull;
    failure != null ? showFailure(context, failure) : showMessage(context, 'Saved to your gallery');
  }

  Future<void> _files(BuildContext context, String path, String name, String mime) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: path, fileName: name, mimeType: mime);
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
    final state = context.watch<PassportCubit>().state;
    final cubit = context.read<PassportCubit>();
    final photo = state.rendered;
    if (photo == null) return const SizedBox.shrink();
    final spec = state.spec;
    final sheet = state.sheet;
    final fileName = '${state.country.name.replaceAll(' ', '_')}_${spec.id}_photo.jpg';

    return ListView(
      padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
      children: [
        Center(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: Colors.white,
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
            ),
            child: AspectRatio(
              aspectRatio: spec.aspect,
              child: Image.file(File(photo.path), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(AppIcons.gallery)),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${photo.width} x ${photo.height} px · ${spec.sizeLabel} · ${formatBytes(photo.bytes)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (state.compressNote != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              state.compressNote!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.warning),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _share(context, [photo.path], 'image/jpeg'),
              icon: const Icon(AppIcons.share, size: 18),
              label: const Text('Share'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _gallery(context, photo.path),
              icon: const Icon(AppIcons.download, size: 18),
              label: const Text('Gallery'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => _files(context, photo.path, fileName, 'image/jpeg'),
              icon: const Icon(AppIcons.storage, size: 18),
              label: const Text('Files'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Label('Upload to a website or form'),
        const Text(
          'Some portals accept only small files. This keeps the same pixel size and lowers the file size.',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [for (final l in _limits) ActionChip(label: Text('Under ${l.$1}'), onPressed: state.busy ? null : () => cubit.compressTo(l.$2))],
        ),
        const SizedBox(height: AppSpacing.lg),
        const _Label('Print sheet'),
        const Text(
          'Repeats the photo on paper so you can print or take it to a photo shop. The PDF has the exact paper size.',
          style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [for (final p in SheetPaper.values) ChoiceChip(label: Text(p.label), selected: _paper == p, onSelected: (_) => setState(() => _paper = p))],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Copies', style: TextStyle(fontSize: 13, color: AppColors.inkMuted)),
            ChoiceChip(label: const Text('Fill the sheet'), selected: _copies == null, onSelected: (_) => setState(() => _copies = null)),
            for (final n in const [2, 4, 6, 8]) ChoiceChip(label: Text('$n'), selected: _copies == n, onSelected: (_) => setState(() => _copies = n)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: state.busy ? null : () => cubit.makeSheet(paper: _paper, copies: _copies),
          icon: const Icon(AppIcons.print, size: 18),
          label: const Text('Create print sheet'),
        ),
        if (sheet != null) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(border: Border.all(color: AppColors.border)),
              child: Image.file(File(sheet.jpgPath), fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(AppIcons.print)),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${sheet.copies} photos on ${_paper.label}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _share(context, [sheet.pdfPath], 'application/pdf'),
                icon: const Icon(AppIcons.pdf, size: 18),
                label: const Text('Share PDF'),
              ),
              OutlinedButton.icon(
                onPressed: () => _share(context, [sheet.jpgPath], 'image/jpeg'),
                icon: const Icon(AppIcons.gallery, size: 18),
                label: const Text('Share JPG'),
              ),
              OutlinedButton.icon(
                onPressed: () => _files(context, sheet.pdfPath, 'photo_sheet.pdf', 'application/pdf'),
                icon: const Icon(AppIcons.storage, size: 18),
                label: const Text('Save PDF'),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(onPressed: cubit.backToEdit, icon: const Icon(AppIcons.crop, size: 18), label: const Text('Adjust')),
            ),
            Expanded(
              child: TextButton.icon(onPressed: cubit.startOver, icon: const Icon(AppIcons.add, size: 18), label: const Text('New photo')),
            ),
          ],
        ),
      ],
    );
  }
}

// endregion

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

class _Note extends StatelessWidget {
  const _Note({required this.text});
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../../app/di.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../documents/domain/entities/scanned_document.dart';
import '../data/print_pdf_builder.dart' show sheetsFor;
import '../domain/print_options.dart';
import '../domain/print_service.dart';

/// Print settings with a live preview. The final step opens the system print sheet, where the printer,
/// two-sided printing and paper tray are chosen (works with Xerox, HP, Canon, Epson, Brother and more).
class PrintPage extends StatefulWidget {
  const PrintPage({super.key, required this.document});
  final ScannedDocument document;

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  PrintOptions _options = const PrintOptions();
  bool _customRange = false;
  final _rangeController = TextEditingController();

  PdfControllerPinch? _preview;
  Object _previewKey = Object();
  bool _building = true;
  String? _error;
  bool _printing = false;
  Timer? _debounce;
  int _token = 0;

  int get _total => widget.document.pageCount;
  bool get _rangeValid => PageRange.parse(_options.pageRange, _total) != null;

  @override
  void initState() {
    super.initState();
    _rebuild(immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _preview?.dispose();
    _rangeController.dispose();
    super.dispose();
  }

  void _set(PrintOptions next, {bool immediate = true}) {
    setState(() => _options = next);
    _rebuild(immediate: immediate);
  }

  void _rebuild({bool immediate = false}) {
    _debounce?.cancel();
    if (!_rangeValid) {
      setState(() {
        _building = false;
        _error = null;
      });
      return;
    }
    setState(() => _building = true);
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 450), _buildPreview);
  }

  Future<void> _buildPreview() async {
    final token = ++_token;
    final result = await sl<PrintService>().buildPdf(document: widget.document, options: _options, preview: true);
    if (!mounted || token != _token) return;
    final bytes = result.valueOrNull;
    if (bytes == null) {
      setState(() {
        _building = false;
        _error = result.failureOrNull?.message;
      });
      return;
    }
    final old = _preview;
    setState(() {
      _preview = PdfControllerPinch(document: PdfDocument.openData(bytes));
      _previewKey = Object();
      _building = false;
      _error = null;
    });
    Future<void>.delayed(const Duration(milliseconds: 300), () => old?.dispose());
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    final service = sl<PrintService>();
    final built = await service.buildPdf(document: widget.document, options: _options);
    final Uint8List? pdf = built.valueOrNull;
    if (!mounted) return;
    if (pdf == null) {
      setState(() => _printing = false);
      showFailure(context, built.failureOrNull!);
      return;
    }
    final sent = await service.print(pdf: pdf, jobName: widget.document.title, options: _options);
    if (!mounted) return;
    setState(() => _printing = false);
    if (sent.failureOrNull != null) showFailure(context, sent.failureOrNull!);
  }

  @override
  Widget build(BuildContext context) {
    final sheets = sheetsFor(_options, _total);
    return Scaffold(
      appBar: AppBar(title: const Text('Print')),
      body: LayoutBuilder(
        builder: (context, box) {
          final preview = _PreviewPane(controller: _preview, previewKey: _previewKey, building: _building, error: _error, rangeInvalid: !_rangeValid);
          final settings = ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Section(
                'Quick setup',
                child: Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final p in PrintPreset.values)
                      ActionChip(
                        label: Text(p.label),
                        onPressed: () {
                          setState(() => _customRange = false);
                          _rangeController.clear();
                          _set(PrintOptions.preset(p));
                        },
                      ),
                  ],
                ),
              ),
              _Section(
                'Paper size',
                child: DropdownButtonFormField<PaperSize>(
                  initialValue: _options.paper,
                  isDense: true,
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                  items: [for (final p in PaperSize.values) DropdownMenuItem(value: p, child: Text(p.label))],
                  onChanged: (p) => _set(_options.copyWith(paper: p)),
                ),
              ),
              _Section(
                'Orientation',
                child: _Segments<PrintOrientation>(
                  value: _options.orientation,
                  options: PrintOrientation.values,
                  label: (o) => o.label,
                  onChanged: (o) => _set(_options.copyWith(orientation: o)),
                ),
              ),
              _Section(
                'Colour',
                child: _Segments<bool>(
                  value: _options.color,
                  options: const [true, false],
                  label: (c) => c ? 'Colour' : 'Black & white',
                  onChanged: (c) => _set(_options.copyWith(color: c)),
                ),
              ),
              _Section(
                'Pages',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Segments<bool>(
                      value: !_customRange,
                      options: const [true, false],
                      label: (all) => all ? 'All ($_total)' : 'Custom',
                      onChanged: (all) {
                        setState(() => _customRange = !all);
                        _rangeController.text = all ? '' : '1';
                        _set(_options.copyWith(pageRange: all ? '' : '1'));
                      },
                    ),
                    if (_customRange) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _rangeController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'For example 1-3, 5',
                          errorText: _rangeValid ? null : 'Use pages 1 to $_total, like 1-3, 5',
                        ),
                        onChanged: (v) => _set(_options.copyWith(pageRange: v), immediate: false),
                      ),
                    ],
                  ],
                ),
              ),
              _Section(
                'Copies',
                child: Row(
                  children: [
                    IconButton.outlined(
                      onPressed: _options.copies > 1 ? () => _set(_options.copyWith(copies: _options.copies - 1)) : null,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${_options.copies}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: _options.copies < 99 ? () => _set(_options.copyWith(copies: _options.copies + 1)) : null,
                      icon: const Icon(AppIcons.add, size: 18),
                    ),
                  ],
                ),
              ),
              _Section(
                'Pages per sheet',
                child: _Segments<int>(
                  value: _options.pagesPerSheet,
                  options: const [1, 2, 4],
                  label: (n) => '$n',
                  onChanged: (n) => _set(_options.copyWith(pagesPerSheet: n)),
                ),
              ),
              _Section(
                'Scaling',
                child: _Segments<bool>(
                  value: _options.fill,
                  options: const [false, true],
                  label: (fill) => fill ? 'Fill page' : 'Fit to page',
                  onChanged: (f) => _set(_options.copyWith(fill: f)),
                ),
              ),
              _Section(
                'Margins',
                child: _Segments<PrintMargin>(
                  value: _options.margin,
                  options: PrintMargin.values,
                  label: (m) => m.label,
                  onChanged: (m) => _set(_options.copyWith(margin: m)),
                ),
              ),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.info, size: 20, color: AppColors.primary),
                      SizedBox(width: AppSpacing.sm + 4),
                      Expanded(
                        child: Text(
                          'Next you choose the printer, two-sided printing and paper tray. For a Xerox, HP, Canon, Epson or Brother printer, turn on its print service in Android Settings > Connected devices > Printing (Mopria or the maker\'s plug-in). On iPhone it uses AirPrint.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          // Wide screens show the preview beside the settings instead of above them.
          if (box.maxWidth >= Breakpoints.expanded) {
            return Row(
              children: [
                Expanded(child: preview),
                const VerticalDivider(width: 1),
                SizedBox(width: 460, child: settings),
              ],
            );
          }
          return Column(
            children: [
              SizedBox(height: 250, child: preview),
              const Divider(),
              Expanded(child: settings),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(sheets == 0 ? 'Check settings' : '$sheets sheet${sheets == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${_options.paper.label} · ${_options.color ? 'Colour' : 'B&W'} · ${_options.copies} cop${_options.copies == 1 ? 'y' : 'ies'}',
                      style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 170,
                child: FilledButton.icon(
                  onPressed: sheets == 0 || _printing || _building ? null : _print,
                  icon: _printing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(AppIcons.print, size: 20),
                  label: const Text('Print'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.controller, required this.previewKey, required this.building, required this.error, required this.rangeInvalid});

  final PdfControllerPinch? controller;
  final Object previewKey;
  final bool building;
  final String? error;
  final bool rangeInvalid;

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (rangeInvalid) {
      content = const Center(
        child: Text('Fix the page range to see the preview', style: TextStyle(color: AppColors.inkMuted)),
      );
    } else if (error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.danger),
          ),
        ),
      );
    } else if (controller == null) {
      content = const Center(child: CircularProgressIndicator());
    } else {
      content = PdfViewPinch(
        key: ValueKey(previewKey),
        controller: controller!,
        backgroundDecoration: const BoxDecoration(color: Color(0xFFE9EDF3)),
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
          pageLoaderBuilder: (_) => const Center(child: CircularProgressIndicator()),
          errorBuilder: (_, e) => const Center(child: Text('Preview unavailable')),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: const Color(0xFFE9EDF3), child: content),
        ),
        if (building && controller != null)
          const Positioned(top: 8, right: 8, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.inkMuted, letterSpacing: 0.3),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    ),
  );
}

class _Segments<T> extends StatelessWidget {
  const _Segments({required this.value, required this.options, required this.label, required this.onChanged});
  final T value;
  final List<T> options;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<T>(
      showSelectedIcon: false,
      segments: [
        for (final o in options)
          ButtonSegment(
            value: o,
            label: Text(label(o), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    ),
  );
}

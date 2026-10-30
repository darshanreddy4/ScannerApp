import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../text_edit/pdf/pdf_page_renderer.dart';
import '../domain/pdf_forms.dart';
import 'pdf_form_cubit.dart';
import 'pdf_result_card.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Fill in the boxes of a PDF form, type text, a date, ticks and crosses on any PDF, and optionally make it all permanent.
/// With [flattenOnly] it only makes the notes and form boxes of a PDF part of its pages.
class PdfFormPage extends StatelessWidget {
  const PdfFormPage({super.key, this.flattenOnly = false, this.openRenderer = PdfxPageRenderer.open});
  final bool flattenOnly;
  final Future<PdfPageRenderer> Function(String path) openRenderer;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfFormCubit(service: sl<PdfFormService>(), outputDir: getTemporaryDirectory, openRenderer: openRenderer, flattenOnly: flattenOnly),
    child: _FormView(flattenOnly: flattenOnly),
  );
}

class _FormView extends StatelessWidget {
  const _FormView({required this.flattenOnly});
  final bool flattenOnly;

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      await context.read<PdfFormCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PdfFormCubit, PdfFormState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure && b.path != null,
      listener: (context, s) => showFailure(context, s.failure!),
      builder: (context, state) {
        final cubit = context.read<PdfFormCubit>();
        final info = state.info;
        return Scaffold(
          appBar: AppBar(
            title: Text(flattenOnly ? 'Flatten PDF' : 'Fill a PDF form'),
            actions: [
              if (info != null && !flattenOnly && state.marks.isNotEmpty && !state.busy)
                IconButton(key: const ValueKey('form-undo'), tooltip: tr('Undo the last mark'), icon: const Icon(AppIcons.undo), onPressed: cubit.undoMark),
              if (state.path != null && !state.busy) TextButton(onPressed: cubit.clear, child: const Text('Close')),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                if (info == null)
                  _Start(flattenOnly: flattenOnly, failure: state.failure, onPick: state.busy ? null : () => _pick(context))
                else
                  Column(
                    children: [
                      if (!flattenOnly) const _Tools(),
                      _Note(info: info, flattenOnly: flattenOnly),
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('form-pages'),
                          padding: contentPadding(context, base: AppSpacing.sm, maxWidth: 720),
                          itemCount: info.pages.length,
                          itemBuilder: (context, i) => _PageView(index: i, page: info.pages[i]),
                        ),
                      ),
                      _SavePanel(flattenOnly: flattenOnly),
                    ],
                  ),
                BusyOverlay(visible: state.busy, label: state.status == FormStatus.saving ? 'Saving' : 'Opening'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.flattenOnly, required this.failure, required this.onPick});
  final bool flattenOnly;
  final Failure? failure;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => ListView(
    padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
    children: [
      FilledButton.icon(
        key: const ValueKey('form-pick'),
        onPressed: onPick,
        icon: const Icon(AppIcons.importFile, size: 18),
        label: const Text('Choose a PDF'),
      ),
      if (failure != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: Text(
            failure!.message,
            key: const ValueKey('form-failure'),
            style: const TextStyle(color: AppColors.danger, height: 1.4),
          ),
        ),
      const SizedBox(height: AppSpacing.md),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(AppIcons.shield, size: 20, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm + 4),
              Expanded(
                child: Text(
                  flattenOnly
                      ? 'Flattening makes form boxes, comments, stamps and drawings part of the page, so they can no longer be changed or removed. Text of the page stays selectable. Everything happens on your phone.'
                      : 'Fill the boxes of a form, or type text, a date, ticks and crosses on any PDF. Text of the page stays selectable. Everything happens on your phone and the file is never uploaded.',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Tools extends StatelessWidget {
  const _Tools();

  static const _labels = {
    FormTool.fields: ('Boxes', AppIcons.pointer),
    FormTool.text: ('Text', AppIcons.markText),
    FormTool.date: ('Date', AppIcons.calendar),
    FormTool.tick: ('Tick', AppIcons.check),
    FormTool.cross: ('Cross', AppIcons.close),
  };

  static const _hints = {
    FormTool.fields: 'Tap a box of the form to fill it.',
    FormTool.text: 'Tap the page where the text should start.',
    FormTool.date: 'Tap the page where the date should go.',
    FormTool.tick: 'Tap the page to put a tick.',
    FormTool.cross: 'Tap the page to put a cross.',
  };

  @override
  Widget build(BuildContext context) {
    final tool = context.select((PdfFormCubit c) => c.state.tool);
    final cubit = context.read<PdfFormCubit>();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final e in _labels.entries)
                ChoiceChip(
                  key: ValueKey('tool-${e.key.name}'),
                  avatar: Icon(e.value.$2, size: 16),
                  label: Text(e.value.$1),
                  selected: tool == e.key,
                  onSelected: (_) => cubit.setTool(e.key),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _hints[tool]!,
              key: const ValueKey('tool-hint'),
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.info, required this.flattenOnly});
  final PdfFormInfo info;
  final bool flattenOnly;

  @override
  Widget build(BuildContext context) {
    final String? text;
    if (flattenOnly) {
      text = info.notes == 0
          ? 'This PDF has no form boxes or notes, so there is nothing to flatten.'
          : '${info.notes} ${info.notes == 1 ? 'form box or note' : 'form boxes and notes'} will become part of the pages and can no longer be changed.';
    } else if (!info.hasFields) {
      text = 'This PDF has no form boxes. Use Text, Date, Tick and Cross to fill it in.';
    } else {
      text = null;
    }
    if (text == null) return const SizedBox(height: AppSpacing.sm);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Text(text, key: const ValueKey('form-note'), style: const TextStyle(fontSize: 13, height: 1.4)),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.index, required this.page});
  final int index;
  final PdfFormPageInfo page;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PdfFormCubit>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: page.aspect,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              final scale = w / page.widthPt;
              return BlocBuilder<PdfFormCubit, PdfFormState>(
                builder: (context, state) => Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder(
                      future: cubit.page(index),
                      builder: (context, snap) => snap.hasData
                          ? Image.memory(snap.data!, fit: BoxFit.fill, gaplessPlayback: true)
                          : Center(
                              child: snap.hasError ? const Icon(AppIcons.info, color: AppColors.inkMuted) : const CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
                    if (!cubit.flattenOnly)
                      Positioned.fill(
                        child: GestureDetector(
                          key: ValueKey('page-$index'),
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (d) => _placeMark(context, state.tool, d.localPosition.dx / w, d.localPosition.dy / h),
                        ),
                      ),
                    for (final f in page.fields)
                      Positioned(
                        left: f.box.left * w,
                        top: f.box.top * h,
                        width: f.box.width * w,
                        height: f.box.height * h,
                        child: _FieldBox(field: f, value: state.valueOf(f), scale: scale, editable: !cubit.flattenOnly),
                      ),
                    for (final m in state.marks.where((m) => m.page == index))
                      Positioned(
                        left: m.u * w,
                        top: m.v * h,
                        child: _MarkView(mark: m, scale: scale),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _placeMark(BuildContext context, FormTool tool, double u, double v) async {
    final cubit = context.read<PdfFormCubit>();
    switch (tool) {
      case FormTool.fields:
        return;
      case FormTool.tick:
        cubit.addMark(index, u, v, MarkKind.tick);
      case FormTool.cross:
        cubit.addMark(index, u, v, MarkKind.cross);
      case FormTool.text || FormTool.date:
        final text = await askFormText(context, title: tool == FormTool.date ? 'Date' : 'Text', initial: tool == FormTool.date ? formDate(cubit.today) : '');
        if (text != null && text.trim().isNotEmpty) cubit.addMark(index, u, v, MarkKind.text, text: text.trim());
    }
  }
}

class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.field, required this.value, required this.scale, required this.editable});
  final FormFieldInfo field;
  final String value;
  final double scale;
  final bool editable;

  Future<void> _tap(BuildContext context) async {
    final cubit = context.read<PdfFormCubit>();
    switch (field.kind) {
      case FormFieldKind.checkbox || FormFieldKind.radio:
        cubit.tapField(field);
      case FormFieldKind.text:
        final text = await askFormText(
          context,
          title: field.name.isEmpty ? 'Text' : field.name,
          initial: value,
          multiline: field.multiline,
          maxLength: field.maxLength,
        );
        if (text != null) cubit.setValue(field, text);
      case FormFieldKind.choice:
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final o in field.options)
                  ListTile(
                    key: ValueKey('option-${o.value}'),
                    title: Text(o.label),
                    trailing: o.value == value ? const Icon(AppIcons.check) : null,
                    onTap: () => Navigator.pop(ctx, o.value),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) cubit.setValue(field, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget content;
    switch (field.kind) {
      case FormFieldKind.checkbox:
        content = value == 'on' ? const FittedBox(child: Icon(AppIcons.check, color: AppColors.ink)) : const SizedBox.shrink();
      case FormFieldKind.radio:
        content = value.isNotEmpty && value == field.option
            ? const FittedBox(
                child: Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.circle, color: AppColors.ink),
                ),
              )
            : const SizedBox.shrink();
      case FormFieldKind.text || FormFieldKind.choice:
        final label = field.kind == FormFieldKind.choice ? field.options.where((o) => o.value == value).map((o) => o.label).firstOrNull ?? value : value;
        content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Align(
            alignment: field.multiline ? AlignmentDirectional.topStart : AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: field.multiline ? null : 1,
              overflow: TextOverflow.clip,
              style: TextStyle(fontSize: 11 * scale, height: 1.15, color: Colors.black),
            ),
          ),
        );
    }
    return GestureDetector(
      key: ValueKey('field-${field.id}-${field.widget}'),
      behavior: HitTestBehavior.opaque,
      onTap: editable ? () => _tap(context) : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: ClipRect(child: content),
      ),
    );
  }
}

class _MarkView extends StatelessWidget {
  const _MarkView({required this.mark, required this.scale});
  final PdfMark mark;
  final double scale;

  Future<void> _remove(BuildContext context) async {
    final cubit = context.read<PdfFormCubit>();
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this mark?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(key: const ValueKey('mark-remove'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove == true) cubit.removeMark(mark);
  }

  @override
  Widget build(BuildContext context) {
    final size = mark.sizePt * scale;
    final Widget child = switch (mark.kind) {
      MarkKind.text => Text(
        mark.text,
        style: TextStyle(fontSize: size, height: 1, color: Colors.black),
      ),
      MarkKind.tick => Icon(AppIcons.check, size: size * 1.1, color: Colors.black),
      MarkKind.cross => Icon(AppIcons.close, size: size * 1.1, color: Colors.black),
    };
    // Text starts at the mark; ticks and crosses are centred on it.
    return FractionalTranslation(
      translation: mark.kind == MarkKind.text ? const Offset(0, -0.5) : const Offset(-0.5, -0.5),
      child: GestureDetector(
        key: ValueKey('mark-${mark.page}-${mark.u.toStringAsFixed(3)}-${mark.v.toStringAsFixed(3)}'),
        onTap: () => _remove(context),
        child: child,
      ),
    );
  }
}

class _SavePanel extends StatelessWidget {
  const _SavePanel({required this.flattenOnly});
  final bool flattenOnly;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PdfFormCubit>().state;
    final cubit = context.read<PdfFormCubit>();
    final flatNothing = flattenOnly && (state.info?.notes ?? 0) == 0;
    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.result != null) ...[
                PdfResultCard(
                  title: flattenOnly ? 'Your PDF is flattened' : 'Your PDF is ready',
                  message: state.flatten
                      ? 'Boxes and marks are now part of the pages. Share this copy; the original file is unchanged.'
                      : 'The boxes keep their values and can still be changed in a PDF reader. The original file is unchanged.',
                  path: state.result!.path,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (!flattenOnly)
                SwitchListTile(
                  key: const ValueKey('form-flatten-switch'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Make it permanent (flatten)'),
                  subtitle: const Text('Boxes and marks become part of the page and cannot be changed later.'),
                  value: state.flatten,
                  onChanged: state.busy ? null : cubit.setFlatten,
                ),
              FilledButton.icon(
                key: const ValueKey('form-save'),
                onPressed: state.busy || flatNothing ? null : cubit.save,
                icon: Icon(flattenOnly ? AppIcons.flatten : AppIcons.check, size: 18),
                label: Text(flattenOnly ? 'Flatten and save' : 'Save PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small dialog for typing one text; returns null when cancelled.
Future<String?> askFormText(BuildContext context, {required String title, String initial = '', bool multiline = false, int maxLength = 0}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextDialog(title: title, initial: initial, multiline: multiline, maxLength: maxLength),
    );

class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.multiline, required this.maxLength});
  final String title;
  final String initial;
  final bool multiline;
  final int maxLength;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    content: TextField(
      key: const ValueKey('form-text-input'),
      controller: _controller,
      autofocus: true,
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? 6 : 1,
      maxLength: widget.maxLength > 0 ? widget.maxLength : null,
      textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
      onSubmitted: widget.multiline ? null : (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const ValueKey('form-text-ok'), onPressed: () => Navigator.pop(context, _controller.text), child: const Text('OK')),
    ],
  );
}

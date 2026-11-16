import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import '../../../documents/presentation/library_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/di.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../export/domain/repositories/export_repository.dart';
import '../../../documents/presentation/library_actions.dart';
import '../../sheets/presentation/sheet_dialogs.dart';
import '../../../text_edit/docx/doc_template_store.dart';
import '../data/pptx_template.dart';
import '../domain/slide_model.dart';
import '../domain/slide_presets.dart';
import 'slide_canvas.dart';
import 'slides_cubit.dart';
import '../../../../core/widgets/text.dart';
import '../../../../core/i18n/tr.dart';

class SlidesPage extends StatelessWidget {
  const SlidesPage({super.key, this.path, this.preset, this.libraryId});

  /// Set when the file is one kept in the library; saving then puts the new version in its place.
  final String? libraryId;

  /// The .pptx file to open; null starts a new presentation.
  final String? path;

  /// A starter to build the new presentation from; used when there is no [path].
  final DeckPreset? preset;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = SlidesCubit(workDir: getTemporaryDirectory);
      if (path != null) {
        cubit.open(path!);
      } else if (preset != null) {
        cubit.startPreset(preset!);
      } else {
        cubit.startBlank();
      }
      return cubit;
    },
    child: _SlidesView(libraryId: libraryId),
  );
}

Future<String?> askMultiline(BuildContext context, {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('slide_text_field'),
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const ValueKey('slide_text_ok'), onPressed: () => Navigator.pop(context, controller.text), child: const Text('Done')),
      ],
    ),
  );
}

const _shapes = <(String, String, IconData)>[
  ('rect', 'Rectangle', Icons.crop_square),
  ('roundRect', 'Rounded', Icons.rounded_corner),
  ('ellipse', 'Circle', Icons.circle_outlined),
  ('triangle', 'Triangle', Icons.change_history),
  ('rightArrow', 'Arrow', Icons.arrow_forward),
  ('star5', 'Star', Icons.star_outline),
  ('line', 'Line', Icons.horizontal_rule),
];

class _SlidesView extends StatefulWidget {
  const _SlidesView({this.libraryId});
  final String? libraryId;

  @override
  State<_SlidesView> createState() => _SlidesViewState();
}

class _SlidesViewState extends State<_SlidesView> {
  late String? _libraryId = widget.libraryId;

  SlidesCubit get cubit => context.read<SlidesCubit>();

  Future<void> _editText() async {
    final sel = cubit.selected;
    if (sel == null || !sel.canHaveText) return;
    final text = await askMultiline(context, title: 'Edit text', initial: sel.plainText);
    if (text != null && mounted) cubit.setText(text);
  }

  Future<void> _addWithLayout() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('New slide with layout', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final l in deckLayouts)
              ListTile(
                key: ValueKey('layout_${l.type}'),
                dense: true,
                leading: const Icon(AppIcons.slides, color: AppColors.primary),
                title: Text(l.name),
                onTap: () => Navigator.pop(context, l.type),
              ),
          ],
        ),
      ),
    );
    if (pick != null && mounted) cubit.addSlide(layout: pick);
  }

  Future<void> _addText() async {
    final text = await askMultiline(context, title: 'Add text');
    if (text != null && mounted) cubit.addTextBox(text);
  }

  Future<void> _addPicture() async {
    try {
      final picked = await pickFilePaths(context, type: FileType.image);
      final path = picked.isEmpty ? null : picked.first;
      if (path == null || !mounted) return;
      final bytes = await File(path).readAsBytes();
      if (mounted) cubit.addPicture(bytes);
    } catch (_) {
      if (mounted) showMessage(context, 'That picture could not be added.');
    }
  }

  Future<void> _addShape() async {
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final s in _shapes)
                InkWell(
                  key: ValueKey('shape_${s.$1}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, s.$1),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        Icon(s.$3, size: 30, color: AppColors.primary),
                        const SizedBox(height: 4),
                        Text(s.$2, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (pick == null || !mounted) return;
    final color = await pickColor(context, title: 'Shape colour', noneLabel: 'Blue');
    if (color != null && mounted) cubit.addShape(pick, color.color ?? 0xFF4472C4);
  }

  Future<void> _export() async {
    final choice = await showModalBottomSheet<({SlideExportFormat format, bool share, bool template, bool library})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        var format = SlideExportFormat.pptx;
        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Save or share', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 8),
                  for (final f in SlideExportFormat.values)
                    RadioListTile<SlideExportFormat>(
                      key: ValueKey('slide_format_${f.name}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(f.label),
                      value: f,
                      // ignore: deprecated_member_use
                      groupValue: format,
                      // ignore: deprecated_member_use
                      onChanged: (v) => setState(() => format = v!),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    key: const ValueKey('slide_library'),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: format == SlideExportFormat.images ? null : () => Navigator.pop(context, (format: format, share: false, template: false, library: true)),
                    icon: const Icon(AppIcons.library, size: 18),
                    label: const Text('Save in Doculoom'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('slide_share'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                          onPressed: () => Navigator.pop(context, (format: format, share: true, template: false, library: false)),
                          icon: const Icon(AppIcons.share, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('slide_save'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                          onPressed: format == SlideExportFormat.images ? null : () => Navigator.pop(context, (format: format, share: false, template: false, library: false)),
                          icon: const Icon(AppIcons.storage, size: 18),
                          label: const Text('Save to Files'),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey('slide_template'),
                      onPressed: () => Navigator.pop(context, (format: SlideExportFormat.pptx, share: false, template: true, library: false)),
                      icon: const Icon(AppIcons.tplBlank, size: 18),
                      label: const Text('Save as my template'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    final paths = await cubit.export(choice.format);
    if (paths == null || paths.isEmpty || !mounted) return;
    if (choice.template) {
      try {
        await const DocTemplateStore.decks().save(paths.first, cubit.name);
        if (mounted) showMessage(context, 'Saved. Find it under My templates when you start a new presentation.');
      } catch (_) {
        if (mounted) showFailure(context, const ExportFailure('The template could not be saved.'));
      }
      return;
    }
    // A new version replaces the library file only when it is the same kind of file.
    final sameKind = choice.format == SlideExportFormat.pptx;
    final id = choice.format == SlideExportFormat.images
        ? null
        : await saveToLibrary(
            context,
            path: paths.first,
            title: cubit.name,
            existingId: sameKind ? _libraryId : null,
            announce: choice.library,
          );
    if (sameKind) _libraryId = id ?? _libraryId;
    if (!mounted) return;
    if (choice.library) {
      if (id != null && sameKind) cubit.markSaved();
      return;
    }
    if (choice.share) {
      final failure = (await sl<ShareService>().shareFiles(paths: paths, mimeType: paths.length == 1 ? choice.format.mimeType : '*/*')).failureOrNull;
      if (!mounted) return;
      if (failure != null) {
        showFailure(context, failure);
        return;
      }
      if (choice.format == SlideExportFormat.pptx) cubit.markSaved();
    } else {
      final result = await sl<SaveService>().saveToFiles(sourcePath: paths.first, fileName: cubit.exportName(choice.format), mimeType: choice.format.mimeType);
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        showFailure(context, failure);
      } else if (result.valueOrNull == true) {
        showMessage(context, 'Saved');
        if (choice.format == SlideExportFormat.pptx) cubit.markSaved();
      }
    }
  }

  /// Cuts the edges off the selected picture and picks its outline shape.
  Future<void> _crop() async {
    final sel = cubit.selected;
    final image = sel?.media == null ? null : cubit.images[sel!.media];
    if (sel == null || image == null) return;
    final result = await showModalBottomSheet<({List<double> crop, String geometry})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CropSheet(image: image, crop: sel.crop ?? const [0, 0, 0, 0], geometry: sel.geometry),
    );
    if (result != null && mounted) cubit.cropSelected(result.crop, geometry: result.geometry);
  }

  /// Edits the speaker notes of the current slide.
  Future<void> _notes() async {
    final text = await askMultiline(context, title: 'Speaker notes', initial: cubit.notesOf(cubit.slide));
    if (text != null && mounted) cubit.setNotes(text);
  }

  /// Chooses how the current slide (or every slide) appears in the slide show.
  Future<void> _transition() async {
    final current = cubit.transitionOf(cubit.slide);
    var all = false;
    final pick = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('How this slide appears in the slide show', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final k in const [('none', 'None'), ('fade', 'Fade'), ('push', 'Push'), ('wipe', 'Wipe'), ('cover', 'Cover')])
                      ChoiceChip(
                        key: ValueKey('transition_${k.$1}'),
                        label: Text(k.$2),
                        selected: current == k.$1,
                        onSelected: (_) => Navigator.pop(context, all ? 'all:${k.$1}' : k.$1),
                      ),
                  ],
                ),
                SwitchListTile(
                  key: const ValueKey('transition_all'),
                  contentPadding: EdgeInsets.zero,
                  value: all,
                  onChanged: (v) => setState(() => all = v),
                  title: const Text('Use for every slide'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (pick == null || !mounted) return;
    cubit.setTransition(pick.replaceFirst('all:', ''), all: pick.startsWith('all:'));
  }

  Future<void> _leave() async {
    if (!cubit.state.modified) {
      context.pop();
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave without saving?'),
        content: const Text('Your changes to this presentation have not been saved or shared. If you leave now they are lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'keep'), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(context, 'leave'),
            child: const Text('Leave', style: TextStyle(color: AppColors.danger)),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'leave') {
      context.pop();
    } else if (choice == 'save') {
      await _export();
    }
  }

  void _show() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(value: cubit, child: const SlideShowPage()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SlidesCubit, SlidesState>(
      listenWhen: (a, b) => (a.failure != b.failure && b.failure != null) || (a.notice != b.notice && b.notice != null),
      listener: (context, s) {
        final f = s.failure;
        if (f != null) showFailure(context, f);
        if (s.notice != null) showMessage(context, s.notice!);
        cubit.clearMessages();
      },
      child: BlocBuilder<SlidesCubit, SlidesState>(
        builder: (context, state) {
          final ready = !state.loading && cubit.hasDeck;
          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _leave();
            },
            child: Scaffold(
              backgroundColor: AppColors.background,
              appBar: AppBar(
                leading: IconButton(key: const ValueKey('slides_back'), icon: const Icon(AppIcons.back), onPressed: _leave),
                title: Text(
                  ready ? '${cubit.name}${state.modified ? ' *' : ''}' : 'Presentation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17),
                ),
                actions: [
                  if (ready) ...[
                    IconButton(
                      key: const ValueKey('slides_undo'),
                      tooltip: tr('Undo'),
                      onPressed: state.canUndo ? cubit.undo : null,
                      icon: const Icon(AppIcons.markUndo, size: 20),
                    ),
                    IconButton(
                      key: const ValueKey('slides_redo'),
                      tooltip: tr('Redo'),
                      onPressed: state.canRedo ? cubit.redo : null,
                      icon: const Icon(AppIcons.markRedo, size: 20),
                    ),
                    IconButton(key: const ValueKey('slides_play'), tooltip: tr('Slide show'), onPressed: _show, icon: const Icon(Icons.play_arrow_rounded)),
                    IconButton(
                      key: const ValueKey('slides_export'),
                      tooltip: tr('Save or share'),
                      onPressed: _export,
                      icon: const Icon(AppIcons.export, size: 20),
                    ),
                  ],
                ],
              ),
              body: SafeArea(
                child: Stack(
                  children: [
                    if (state.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (!cubit.hasDeck)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(AppIcons.warning, size: 40, color: AppColors.danger),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                state.failure?.message ?? 'This presentation could not be opened.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(height: 1.4),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              FilledButton(onPressed: () => context.pop(), child: const Text('Go back')),
                            ],
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: SlideCanvas(
                                  key: ValueKey('canvas_${state.slideIndex}'),
                                  view: cubit.currentView,
                                  images: cubit.images,
                                  imagesVersion: state.imagesVersion,
                                  widthEmu: cubit.deck.width,
                                  heightEmu: cubit.deck.height,
                                  selected: cubit.selected,
                                  interactive: true,
                                  hitTest: cubit.hit,
                                  onSelect: cubit.select,
                                  onFrame: cubit.setFrame,
                                  onEditText: _editText,
                                ),
                              ),
                            ),
                          ),
                          _toolbar(state),
                          _Strip(state: state),
                        ],
                      ),
                    BusyOverlay(visible: state.busy != null, label: state.busy),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _toolbar(SlidesState state) {
    final sel = cubit.selected;
    Widget tool(String key, IconData icon, String label, VoidCallback? onTap, {bool on = false}) =>
        _Tool(key: ValueKey('stool_$key'), icon: icon, label: label, onTap: onTap, selected: on);
    final first = sel?.paragraphs.firstOrNull?.runs.firstOrNull;
    final children = <Widget>[];
    if (sel != null) {
      children.add(tool('done', AppIcons.check, 'Done', () => cubit.select(null)));
      if (sel.canHaveText) {
        children.addAll([
          tool('edit', AppIcons.edit, 'Edit\ntext', _editText),
          tool('smaller', AppIcons.zoomOut, 'Smaller\ntext', cubit.smallerText),
          tool('bigger', AppIcons.zoomIn, 'Bigger\ntext', cubit.biggerText),
          tool('bold', AppIcons.bold, 'Bold', cubit.toggleBold, on: first?.bold ?? false),
          tool('italic', AppIcons.italic, 'Italic', cubit.toggleItalic, on: first?.italic ?? false),
          tool('underline', AppIcons.underline, 'Underline', cubit.toggleUnderline, on: first?.underline ?? false),
          tool('textcolor', AppIcons.textColor, 'Text\ncolour', () async {
            final c = await pickColor(context, title: 'Text colour', noneLabel: 'Black');
            if (c != null) cubit.setTextColor(c.color ?? 0xFF000000);
          }),
          tool(
            'align',
            switch (sel.paragraphs.firstOrNull?.align) {
              'ctr' => AppIcons.alignCenter,
              'r' => AppIcons.alignRight,
              _ => AppIcons.alignLeft,
            },
            'Align',
            cubit.cycleAlign,
          ),
          tool('fill', AppIcons.fillColor, 'Fill', () async {
            final c = await pickColor(context, title: 'Shape colour', noneLabel: 'No fill');
            if (c != null) cubit.setFill(c.color);
          }),
          tool('outline', AppIcons.shape, 'Outline', () async {
            final c = await pickColor(context, title: 'Outline colour', noneLabel: 'No outline');
            if (c != null) cubit.setOutline(c.color);
          }),
        ]);
      }
      if (sel.kind == ShapeKind.picture && sel.media != null) children.add(tool('crop', Icons.crop, 'Crop', _crop));
      children.addAll([
        tool('duplicate', AppIcons.duplicate, 'Copy', cubit.duplicateSelected),
        tool('front', AppIcons.expandLess, 'Bring\nforward', () => cubit.reorderSelected(toFront: true)),
        tool('back', AppIcons.expandMore, 'Send\nback', () => cubit.reorderSelected(toFront: false)),
        tool('delete', AppIcons.delete, 'Delete', cubit.deleteSelected),
      ]);
    } else {
      children.addAll([
        tool('addtext', AppIcons.text, 'Add\ntext', _addText),
        tool('addpicture', AppIcons.gallery, 'Add\npicture', _addPicture),
        tool('addshape', AppIcons.shape, 'Add\nshape', _addShape),
        tool('background', AppIcons.fillColor, 'Slide\ncolour', () async {
          final c = await pickColor(context, title: 'Slide colour', noneLabel: 'Theme colour');
          if (c != null) cubit.setBackground(c.color);
        }),
        tool('transition', Icons.animation, 'Slide\nshow effect', _transition),
        tool('notes', Icons.sticky_note_2_outlined, 'Speaker\nnotes', _notes),
        tool('newslide', AppIcons.add, 'New\nslide', cubit.addSlide),
        tool('newlayout', AppIcons.slides, 'Slide\nlayouts', _addWithLayout),
        tool('dupslide', AppIcons.duplicate, 'Copy\nslide', cubit.duplicateSlide),
        tool('left', AppIcons.back, 'Move\nleft', state.slideIndex > 0 ? () => cubit.moveSlide(-1) : null),
        tool('right', AppIcons.next, 'Move\nright', state.slideIndex < cubit.deck.slides.length - 1 ? () => cubit.moveSlide(1) : null),
        tool('delslide', AppIcons.delete, 'Delete\nslide', () async {
          final ok = await confirmDialog(
            context,
            title: 'Delete this slide?',
            message: 'Slide ${state.slideIndex + 1} will be removed. You can undo this.',
            confirm: 'Delete',
            danger: true,
          );
          if (ok) cubit.deleteSlide();
        }),
      ]);
    }
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      height: 62,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), children: children),
    );
  }
}

/// Sliders for the four edges of a picture, a preview of what stays, and the outline shape.
class _CropSheet extends StatefulWidget {
  const _CropSheet({required this.image, required this.crop, required this.geometry});

  final ui.Image image;
  final List<double> crop;
  final String geometry;

  @override
  State<_CropSheet> createState() => _CropSheetState();
}

class _CropSheetState extends State<_CropSheet> {
  late List<double> crop = [for (final c in widget.crop) c.clamp(0.0, 0.9)];
  late String geometry = const {'rect', 'roundRect', 'ellipse'}.contains(widget.geometry) ? widget.geometry : 'rect';

  static const _edges = ['Left', 'Top', 'Right', 'Bottom'];

  void _set(int i, double v) {
    // Opposite edges never meet.
    final other = (i + 2) % 4;
    setState(() {
      crop = List.of(crop)..[i] = v;
      if (crop[i] + crop[other] > 0.9) crop[other] = 0.9 - crop[i];
    });
  }

  @override
  Widget build(BuildContext context) {
    final iw = widget.image.width.toDouble(), ih = widget.image.height.toDouble();
    final keepW = iw * (1 - crop[0] - crop[2]), keepH = ih * (1 - crop[1] - crop[3]);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Crop picture', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                height: 110,
                child: AspectRatio(
                  key: const ValueKey('crop_preview'),
                  aspectRatio: keepW / keepH,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(geometry == 'roundRect' ? 14 : 0),
                    child: CustomPaint(painter: _CropPreview(widget.image, crop, geometry == 'ellipse')),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < 4; i++)
              Row(
                children: [
                  SizedBox(width: 58, child: Text(_edges[i], style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: Slider(key: ValueKey('crop_${_edges[i].toLowerCase()}'), value: crop[i], max: 0.9, onChanged: (v) => _set(i, v)),
                  ),
                  SizedBox(width: 40, child: Text('${(crop[i] * 100).round()}%', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
                ],
              ),
            const Text('Shape', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final g in const [('rect', 'Rectangle'), ('roundRect', 'Rounded'), ('ellipse', 'Oval')])
                  ChoiceChip(key: ValueKey('crop_shape_${g.$1}'), label: Text(g.$2), selected: geometry == g.$1, onSelected: (_) => setState(() => geometry = g.$1)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('crop_reset'),
                    onPressed: () => setState(() {
                      crop = [0, 0, 0, 0];
                      geometry = 'rect';
                    }),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(key: const ValueKey('crop_apply'), onPressed: () => Navigator.pop(context, (crop: crop, geometry: geometry)), child: const Text('Apply')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPreview extends CustomPainter {
  _CropPreview(this.image, this.crop, this.oval);
  final ui.Image image;
  final List<double> crop;
  final bool oval;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (oval) canvas.clipPath(Path()..addOval(rect));
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    canvas.drawImageRect(image, Rect.fromLTRB(iw * crop[0], ih * crop[1], iw * (1 - crop[2]), ih * (1 - crop[3])), rect, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_CropPreview old) => old.crop != crop || old.oval != oval || old.image != image;
}

class _Tool extends StatelessWidget {
  const _Tool({super.key, required this.icon, required this.label, required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.border : (selected ? AppColors.primary : AppColors.ink);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 58,
        decoration: BoxDecoration(color: selected ? AppColors.primarySoft : null, borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, height: 1.05, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pictures of every slide, to jump between them.
class _Strip extends StatefulWidget {
  const _Strip({required this.state});
  final SlidesState state;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_Strip old) {
    super.didUpdateWidget(old);
    if (old.state.slideIndex != widget.state.slideIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final cubit = context.read<SlidesCubit>();
        final itemWidth = 72 * cubit.deck.width / cubit.deck.height + 16;
        final pos = _controller.position;
        final target = (widget.state.slideIndex * itemWidth - pos.viewportDimension / 2 + itemWidth / 2 + 8).clamp(0.0, pos.maxScrollExtent);
        _controller.jumpTo(target);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<SlidesCubit>();
    final slides = cubit.deck.slides;
    return Container(
      height: 92,
      color: AppColors.background,
      child: ListView.builder(
        key: const ValueKey('slide_strip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: slides.length,
        itemBuilder: (context, i) {
          final on = i == state.slideIndex;
          return GestureDetector(
            key: ValueKey('thumb_$i'),
            onTap: () => cubit.selectSlide(i),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border.all(color: on ? AppColors.primary : AppColors.border, width: on ? 2.5 : 1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 72,
                      child: SlideCanvas(
                        view: cubit.viewOf(slides[i]),
                        images: cubit.images,
                        imagesVersion: state.imagesVersion,
                        widthEmu: cubit.deck.width,
                        heightEmu: cubit.deck.height,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 3,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen slide show: tap or swipe to move on.
class SlideShowPage extends StatefulWidget {
  const SlideShowPage({super.key});

  @override
  State<SlideShowPage> createState() => _SlideShowPageState();
}

class _SlideShowPageState extends State<SlideShowPage> {
  late int _index = context.read<SlidesCubit>().state.slideIndex;
  var _showNotes = false;

  /// Which way the last move went, so the slide that goes away leaves on the right side.
  var _forward = true;

  void _go(int delta) {
    final count = context.read<SlidesCubit>().deck.slides.length;
    final next = _index + delta;
    if (next >= count) {
      Navigator.of(context).pop();
      return;
    }
    if (next < 0) return;
    setState(() {
      _forward = delta > 0;
      _index = next;
    });
  }

  Widget _transitionFor(String kind, Widget child, Animation<double> animation, bool incoming) {
    final sign = _forward ? 1.0 : -1.0;
    switch (kind) {
      case 'fade':
        return FadeTransition(opacity: animation, child: child);
      case 'push':
        // The new slide comes in from one side while the old one leaves by the other.
        final begin = Offset(incoming ? sign : -sign, 0);
        return SlideTransition(position: Tween(begin: begin, end: Offset.zero).animate(animation), child: child);
      case 'cover':
        if (!incoming) return child;
        return SlideTransition(position: Tween(begin: Offset(sign, 0), end: Offset.zero).animate(animation), child: child);
      case 'wipe':
        if (!incoming) return child;
        return ClipRect(
          clipper: _WipeClipper(animation.value, fromRight: _forward),
          child: child,
        );
      default:
        return child;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SlidesCubit>();
    final slides = cubit.deck.slides;
    final slide = slides[_index.clamp(0, slides.length - 1)];
    // The slide that comes in decides how the change looks.
    final kind = cubit.transitionOf(slide);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            key: const ValueKey('slide_show'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _go(1),
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              // A swipe to the left moves on, as turning a page does.
              final towardsEnd = Directionality.of(context) == TextDirection.rtl ? v > 0 : v < 0;
              _go(towardsEnd ? 1 : -1);
            },
            child: SizedBox.expand(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: kind == 'none' ? 0 : 450),
                transitionBuilder: (child, animation) => AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) => _transitionFor(kind, child, animation, child.key == ValueKey(_index)),
                ),
                child: Center(
                  key: ValueKey(_index),
                  child: SlideCanvas(
                    view: cubit.viewOf(slide),
                    images: cubit.images,
                    imagesVersion: cubit.state.imagesVersion,
                    widthEmu: cubit.deck.width,
                    heightEmu: cubit.deck.height,
                  ),
                ),
              ),
            ),
          ),
          if (_showNotes)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                key: const ValueKey('show_notes_panel'),
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.35),
                color: Colors.black87,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Builder(
                      builder: (context) {
                        final notes = cubit.notesOf(slide);
                        return Text(
                          notes.isEmpty ? 'No notes for this slide' : notes,
                          style: TextStyle(color: notes.isEmpty ? Colors.white54 : Colors.white, fontSize: 16, height: 1.35),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: const ValueKey('show_notes'),
                    color: _showNotes ? Colors.amber : Colors.white,
                    tooltip: tr('Speaker notes'),
                    icon: const Icon(Icons.sticky_note_2_outlined),
                    onPressed: () => setState(() => _showNotes = !_showNotes),
                  ),
                  IconButton(
                    key: const ValueKey('show_close'),
                    color: Colors.white,
                    icon: const Icon(AppIcons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reveals a slide from one edge, as a wipe does.
class _WipeClipper extends CustomClipper<Rect> {
  _WipeClipper(this.progress, {required this.fromRight});
  final double progress;
  final bool fromRight;

  @override
  Rect getClip(Size size) {
    final w = size.width * progress.clamp(0.0, 1.0);
    return fromRight ? Rect.fromLTWH(size.width - w, 0, w, size.height) : Rect.fromLTWH(0, 0, w, size.height);
  }

  @override
  bool shouldReclip(_WipeClipper old) => old.progress != progress || old.fromRight != fromRight;
}

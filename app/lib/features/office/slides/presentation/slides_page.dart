import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/di.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/widgets/feedback.dart';
import '../../../export/domain/repositories/export_repository.dart';
import '../../sheets/presentation/sheet_dialogs.dart';
import 'slide_canvas.dart';
import 'slides_cubit.dart';
import '../../../../core/widgets/text.dart';
import '../../../../core/i18n/tr.dart';

class SlidesPage extends StatelessWidget {
  const SlidesPage({super.key, this.path});

  /// The .pptx file to open; null starts a new presentation.
  final String? path;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = SlidesCubit(workDir: getTemporaryDirectory);
      if (path == null) {
        cubit.startBlank();
      } else {
        cubit.open(path!);
      }
      return cubit;
    },
    child: const _SlidesView(),
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
  const _SlidesView();

  @override
  State<_SlidesView> createState() => _SlidesViewState();
}

class _SlidesViewState extends State<_SlidesView> {
  SlidesCubit get cubit => context.read<SlidesCubit>();

  Future<void> _editText() async {
    final sel = cubit.selected;
    if (sel == null || !sel.canHaveText) return;
    final text = await askMultiline(context, title: 'Edit text', initial: sel.plainText);
    if (text != null && mounted) cubit.setText(text);
  }

  Future<void> _addText() async {
    final text = await askMultiline(context, title: 'Add text');
    if (text != null && mounted) cubit.addTextBox(text);
  }

  Future<void> _addPicture() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      final path = picked.isEmpty ? null : picked.first.path;
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
    final choice = await showModalBottomSheet<({SlideExportFormat format, bool share})>(
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
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: const ValueKey('slide_share'),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                          onPressed: () => Navigator.pop(context, (format: format, share: true)),
                          icon: const Icon(AppIcons.share, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('slide_save'),
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                          onPressed: format == SlideExportFormat.images ? null : () => Navigator.pop(context, (format: format, share: false)),
                          icon: const Icon(AppIcons.storage, size: 18),
                          label: const Text('Save to Files'),
                        ),
                      ),
                    ],
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
        tool('newslide', AppIcons.add, 'New\nslide', cubit.addSlide),
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
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: context.read<SlidesCubit>().state.slideIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SlidesCubit>();
    final slides = cubit.deck.slides;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            key: const ValueKey('slide_show'),
            controller: _controller,
            itemCount: slides.length,
            itemBuilder: (context, i) => GestureDetector(
              onTap: () {
                if (i + 1 < slides.length) {
                  _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                } else {
                  Navigator.of(context).pop();
                }
              },
              child: Center(
                child: SlideCanvas(
                  view: cubit.viewOf(slides[i]),
                  images: cubit.images,
                  imagesVersion: cubit.state.imagesVersion,
                  widthEmu: cubit.deck.width,
                  heightEmu: cubit.deck.height,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topEnd,
              child: IconButton(
                key: const ValueKey('show_close'),
                color: Colors.white,
                icon: const Icon(AppIcons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

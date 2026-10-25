import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../domain/markup.dart';
import 'markup_canvas.dart';
import 'markup_color_sheet.dart';
import 'markup_cubit.dart';
import 'markup_emoji_sheet.dart';
import 'markup_text_dialog.dart';

/// What the markup screen needs to show the page.
class MarkupArgs {
  const MarkupArgs({required this.width, required this.height, this.imagePath, this.previewBytes});

  /// Pixel size of the page picture; marks are saved relative to it.
  final int width;
  final int height;

  /// The page as it looks with the chosen colour filter, when a preview exists.
  final Uint8List? previewBytes;
  final String? imagePath;
}

/// Draw, highlight and place shapes or emoji on a page. Pops the marks when done, or nothing when cancelled.
class MarkupPage extends StatelessWidget {
  const MarkupPage({super.key, required this.args});
  final MarkupArgs args;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => MarkupCubit(page: Size(args.width.toDouble(), args.height.toDouble())),
    child: _MarkupView(args: args),
  );
}

class _MarkupView extends StatefulWidget {
  const _MarkupView({required this.args});
  final MarkupArgs args;

  @override
  State<_MarkupView> createState() => _MarkupViewState();
}

class _MarkupViewState extends State<_MarkupView> {
  ui.Image? _base;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      Uint8List? bytes = widget.args.previewBytes;
      if (bytes == null && widget.args.imagePath != null) {
        // Drawing needs far fewer pixels than the saved page has.
        final codec = await ui.instantiateImageCodec(await File(widget.args.imagePath!).readAsBytes(), targetWidth: widget.args.width > 1600 ? 1600 : null);
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (mounted) setState(() => _base = frame.image);
        return;
      }
      if (bytes == null) return;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (mounted) setState(() => _base = frame.image);
    } catch (_) {
      // The page stays white; marks can still be drawn and are saved on the real picture.
    }
  }

  @override
  void dispose() {
    _base?.dispose();
    super.dispose();
  }

  Future<void> _cancel(MarkupCubit cubit) async {
    if (!cubit.state.hasMarks) {
      context.pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard your markup?'),
        content: const Text('The marks you added to this page will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) context.pop();
  }

  /// Tapping with the Text tool edits the text mark under the finger, or starts a new one there.
  Future<void> _typeAt(MarkupCubit cubit, Offset at) async {
    final page = cubit.page;
    for (final item in cubit.state.items.reversed) {
      if (item is MarkupText && MarkupGeometry.hit(item, at, page)) {
        await _editText(cubit, item);
        return;
      }
    }
    final text = await showMarkupTextDialog(context);
    if (text != null) cubit.addText(at, text);
  }

  Future<void> _editText(MarkupCubit cubit, MarkupText item) async {
    final text = await showMarkupTextDialog(context, initial: item.text);
    if (text != null) cubit.editText(item.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MarkupCubit>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel(cubit);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: MarkupCanvas(
                    base: _base,
                    pageSize: Size(widget.args.width.toDouble(), widget.args.height.toDouble()),
                    onTextTap: (at) => _typeAt(cubit, at),
                  ),
                ),
              ),
              const _OptionsRow(),
              const _ToolStrip(),
              BlocBuilder<MarkupCubit, MarkupState>(
                builder: (context, state) => _BottomBar(
                  canUndo: state.canUndo,
                  canRedo: state.canRedo,
                  hasMarks: state.hasMarks,
                  onCancel: () => _cancel(cubit),
                  onUndo: cubit.undo,
                  onRedo: cubit.redo,
                  onDone: () => context.pop(state.hasMarks ? state.items : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionsRow extends StatelessWidget {
  const _OptionsRow();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MarkupCubit>();
    return BlocBuilder<MarkupCubit, MarkupState>(
      builder: (context, state) {
        final tool = state.tool;
        final selected = state.selected;
        Widget hint(String text) => Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        );

        Widget slider({required double value, required double min, required double max, required ValueChanged<double> onChanged}) => Row(
          children: [
            const Icon(AppIcons.markPen, size: 14, color: Colors.white54),
            Expanded(
              child: Slider(
                key: const ValueKey('thickness-slider'),
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
                onChangeEnd: (_) => cubit.endStyleChange(),
              ),
            ),
            const Icon(AppIcons.markPen, size: 24, color: Colors.white54),
          ],
        );

        final Widget child;
        if (tool.hasInk) {
          child = Row(
            children: [
              Expanded(
                child: slider(value: state.widthOf(tool), min: MarkupState.minWidth, max: MarkupState.maxWidth, onChanged: cubit.setWidth),
              ),
              if (tool == MarkupTool.rectangle || tool == MarkupTool.ellipse)
                FilterChip(
                  key: const ValueKey('fill-chip'),
                  label: const Text('Fill'),
                  selected: state.filled,
                  onSelected: cubit.setFilled,
                  labelStyle: TextStyle(color: state.filled ? Colors.black : Colors.white),
                  backgroundColor: Colors.white12,
                  selectedColor: Colors.white,
                  checkmarkColor: Colors.black,
                  side: BorderSide.none,
                ),
            ],
          );
        } else if (tool == MarkupTool.sticker) {
          child = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  'Tap the page to place',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              _EmojiButton(emoji: state.emoji, onTap: () => _pickEmoji(context, cubit)),
            ],
          );
        } else if (tool == MarkupTool.text) {
          child = Row(
            children: [
              const Icon(AppIcons.markText, size: 14, color: Colors.white54),
              Expanded(
                child: Slider(
                  key: const ValueKey('text-size'),
                  value: state.textSize.clamp(MarkupText.minSize, 0.2),
                  min: MarkupText.minSize,
                  max: 0.2,
                  onChanged: cubit.setTextSize,
                  onChangeEnd: (_) => cubit.endStyleChange(),
                ),
              ),
              const Icon(AppIcons.markText, size: 24, color: Colors.white54),
              const SizedBox(width: 8),
              _BoldChip(selected: state.textBold, onSelected: cubit.setTextBold),
            ],
          );
        } else if (tool == MarkupTool.select) {
          if (selected == null) {
            child = hint('Tap a mark to select it, then drag to move. Pinch to resize.');
          } else {
            child = Row(
              children: [
                IconButton(
                  key: const ValueKey('delete-selected'),
                  tooltip: 'Delete',
                  onPressed: cubit.deleteSelected,
                  icon: const Icon(AppIcons.delete, color: Colors.white),
                ),
                if (selected is MarkupText) ...[
                  IconButton(
                    key: const ValueKey('edit-text'),
                    tooltip: 'Edit text',
                    onPressed: () async {
                      final text = await showMarkupTextDialog(context, initial: selected.text);
                      if (text != null) cubit.editText(selected.id, text);
                    },
                    icon: const Icon(AppIcons.edit, color: Colors.white),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('text-size'),
                      value: selected.size.clamp(MarkupText.minSize, 0.2),
                      min: MarkupText.minSize,
                      max: 0.2,
                      onChanged: cubit.setTextSize,
                      onChangeEnd: (_) => cubit.endStyleChange(),
                    ),
                  ),
                  _BoldChip(selected: selected.bold, onSelected: cubit.setTextBold),
                ] else if (selected is MarkupSticker) ...[
                  _EmojiButton(emoji: selected.text, onTap: () => _pickEmoji(context, cubit)),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('sticker-size'),
                      value: selected.size.clamp(MarkupSticker.minSize, 0.5),
                      min: MarkupSticker.minSize,
                      max: 0.5,
                      onChanged: cubit.resizeSelectedSticker,
                      onChangeEnd: (_) => cubit.endStyleChange(),
                    ),
                  ),
                ] else
                  Expanded(
                    child: slider(
                      value: selected is MarkupStroke ? selected.width : (selected as MarkupShape).width,
                      min: MarkupState.minWidth,
                      max: MarkupState.maxWidth,
                      onChanged: cubit.setWidth,
                    ),
                  ),
              ],
            );
          }
        } else if (tool == MarkupTool.eraser) {
          child = hint('Drag over a mark to remove it');
        } else {
          child = hint('Pinch to zoom the page and drag to move it');
        }
        return SizedBox(
          height: 52,
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child),
        );
      },
    );
  }

  Future<void> _pickEmoji(BuildContext context, MarkupCubit cubit) async {
    final e = await showMarkupEmojiSheet(context);
    if (e != null) cubit.setEmoji(e);
  }
}

class _BoldChip extends StatelessWidget {
  const _BoldChip({required this.selected, required this.onSelected});
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
    key: const ValueKey('bold-chip'),
    label: const Text('Bold', style: TextStyle(fontWeight: FontWeight.w700)),
    selected: selected,
    onSelected: onSelected,
    labelStyle: TextStyle(color: selected ? Colors.black : Colors.white),
    backgroundColor: Colors.white12,
    selectedColor: Colors.white,
    checkmarkColor: Colors.black,
    side: BorderSide.none,
    visualDensity: VisualDensity.compact,
  );
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.onTap});
  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Choose emoji',
    child: InkWell(
      key: const ValueKey('emoji-button'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(12)),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    ),
  );
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip();

  static const _icons = <MarkupTool, IconData>{
    MarkupTool.pen: AppIcons.markPen,
    MarkupTool.pencil: AppIcons.markPencil,
    MarkupTool.highlighter: AppIcons.markHighlighter,
    MarkupTool.eraser: AppIcons.markEraser,
    MarkupTool.line: AppIcons.markLine,
    MarkupTool.arrow: AppIcons.markArrow,
    MarkupTool.rectangle: AppIcons.markSquare,
    MarkupTool.ellipse: AppIcons.markCircle,
    MarkupTool.sticker: AppIcons.markEmoji,
    MarkupTool.text: AppIcons.markText,
    MarkupTool.select: AppIcons.markMove,
    MarkupTool.hand: AppIcons.markZoom,
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MarkupCubit>();
    return BlocBuilder<MarkupCubit, MarkupState>(
      builder: (context, state) {
        return Container(
          height: 76,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: MarkupColors.surface, borderRadius: BorderRadius.circular(22)),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Tooltip(
                  message: 'Colour',
                  child: InkResponse(
                    key: const ValueKey('color-button'),
                    onTap: () => showMarkupColorSheet(context, cubit),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF000000 | state.color).withValues(alpha: state.tool.hasInk ? state.opacityOf(state.tool) : 1),
                          border: Border.all(color: MarkupColors.surface, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final t in MarkupTool.values)
                      _ToolButton(
                        key: ValueKey('tool-${t.name}'),
                        icon: _icons[t]!,
                        label: t.label,
                        selected: state.tool == t,
                        onTap: () => cubit.selectTool(t),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.icon, required this.label, required this.selected, required this.onTap});
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 64,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(color: selected ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: selected ? Colors.black : Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(fontSize: 11, color: selected ? Colors.black : Colors.white70, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canUndo,
    required this.canRedo,
    required this.hasMarks,
    required this.onCancel,
    required this.onUndo,
    required this.onRedo,
    required this.onDone,
  });
  final bool canUndo;
  final bool canRedo;
  final bool hasMarks;
  final VoidCallback onCancel;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.white12,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: const Text('Cancel', maxLines: 1),
        ),
        const Spacer(),
        IconButton(
          key: const ValueKey('undo'),
          tooltip: 'Undo',
          onPressed: canUndo ? onUndo : null,
          icon: const Icon(AppIcons.markUndo),
          color: Colors.white,
          disabledColor: Colors.white30,
        ),
        IconButton(
          key: const ValueKey('redo'),
          tooltip: 'Redo',
          onPressed: canRedo ? onRedo : null,
          icon: const Icon(AppIcons.markRedo),
          color: Colors.white,
          disabledColor: Colors.white30,
        ),
        const Spacer(),
        FilledButton(
          onPressed: onDone,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            backgroundColor: const Color(0xFFFFC107),
            foregroundColor: Colors.black,
          ),
          child: const Text('Done', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

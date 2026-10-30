import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../data/pdf_picture_pages.dart';
import '../domain/pdf_forms.dart';
import '../domain/pdf_pages.dart';
import 'pdf_images_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Turns the pages of a PDF into picture files, or saves the pictures that are inside a PDF.
class PdfImagesPage extends StatelessWidget {
  const PdfImagesPage({super.key, this.pages});
  final PdfPicturePages Function()? pages;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => PdfImagesCubit(tools: sl<PdfPageToolsService>(), outputDir: getTemporaryDirectory, pages: pages),
    child: const _ImagesView(),
  );
}

class _ImagesView extends StatefulWidget {
  const _ImagesView();

  @override
  State<_ImagesView> createState() => _ImagesViewState();
}

class _ImagesViewState extends State<_ImagesView> {
  final _range = TextEditingController();

  @override
  void dispose() {
    _range.dispose();
    super.dispose();
  }

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      _range.clear();
      await context.read<PdfImagesCubit>().pick(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _share(PdfImagesState state) async {
    final failure = (await sl<ShareService>().shareFiles(paths: state.files, mimeType: state.mime)).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _gallery(PdfImagesState state) async {
    final result = await sl<SaveService>().saveImagesToGallery(state.files);
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull != null) {
      final n = result.valueOrNull!;
      showMessage(context, n == 1 ? 'Saved 1 picture to your gallery' : 'Saved $n pictures to your gallery');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PdfImagesCubit, PdfImagesState>(
      builder: (context, state) {
        final cubit = context.read<PdfImagesCubit>();
        final pages = state.mode == ImagesMode.pages;
        return Scaffold(
          appBar: AppBar(
            title: const Text('PDF to pictures'),
            actions: [
              if (state.path != null && !state.busy)
                TextButton(
                  onPressed: () {
                    _range.clear();
                    cubit.clear();
                  },
                  child: const Text('Close'),
                ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
                  children: [
                    if (!state.open)
                      FilledButton.icon(
                        key: const ValueKey('images-pick'),
                        onPressed: state.busy ? null : () => _pick(context),
                        icon: const Icon(AppIcons.importFile, size: 18),
                        label: const Text('Choose a PDF'),
                      )
                    else ...[
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(AppIcons.pdf, color: AppColors.primary),
                          title: Text(p.basename(state.path!), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(state.pageCount == 1 ? '1 page' : '${state.pageCount} pages'),
                          trailing: TextButton(onPressed: state.busy ? null : () => _pick(context), child: const Text('Change')),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      SegmentedButton<ImagesMode>(
                        key: const ValueKey('images-mode'),
                        segments: const [
                          ButtonSegment(value: ImagesMode.pages, label: Text('Pages'), icon: Icon(AppIcons.pdfImage, size: 18)),
                          ButtonSegment(value: ImagesMode.inside, label: Text('Pictures inside'), icon: Icon(AppIcons.gallery, size: 18)),
                        ],
                        selected: {state.mode},
                        onSelectionChanged: (s) => cubit.setMode(s.first),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (pages) ...[
                        TextField(
                          key: const ValueKey('images-range'),
                          controller: _range,
                          enabled: !state.busy,
                          decoration: InputDecoration(labelText: tr('Pages (leave empty for all)'), hintText: tr('1-3, 5')),
                          onChanged: cubit.setRange,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            ChoiceChip(
                              key: const ValueKey('images-jpeg'),
                              label: const Text('JPEG (smaller)'),
                              selected: !state.png,
                              onSelected: (_) => cubit.setPng(false),
                            ),
                            ChoiceChip(
                              key: const ValueKey('images-png'),
                              label: const Text('PNG (sharper)'),
                              selected: state.png,
                              onSelected: (_) => cubit.setPng(true),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            ChoiceChip(
                              key: const ValueKey('images-standard'),
                              label: const Text('Standard'),
                              selected: !state.high,
                              onSelected: (_) => cubit.setHigh(false),
                            ),
                            ChoiceChip(
                              key: const ValueKey('images-high'),
                              label: const Text('High detail'),
                              selected: state.high,
                              onSelected: (_) => cubit.setHigh(true),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          key: const ValueKey('images-make'),
                          onPressed: state.busy ? null : cubit.makePages,
                          icon: const Icon(AppIcons.pdfImage, size: 18),
                          label: const Text('Make pictures'),
                        ),
                      ] else ...[
                        const Text(
                          'Saves the photos and graphics placed inside the PDF exactly as they are stored, without the text around them. Very small pictures are left out.',
                          style: TextStyle(fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          key: const ValueKey('images-find'),
                          onPressed: state.busy ? null : cubit.findPictures,
                          icon: const Icon(AppIcons.gallery, size: 18),
                          label: const Text('Find pictures'),
                        ),
                      ],
                    ],
                    if (state.failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          state.failure!.message,
                          key: const ValueKey('images-failure'),
                          style: const TextStyle(color: AppColors.danger, height: 1.4),
                        ),
                      ),
                    if (state.status == ImagesStatus.done || (state.searched && state.files.isEmpty)) ...[
                      const SizedBox(height: AppSpacing.md),
                      _Result(state: state, onShare: () => _share(state), onGallery: () => _gallery(state)),
                    ],
                  ],
                ),
                BusyOverlay(
                  visible: state.busy,
                  label: state.status == ImagesStatus.working && state.mode == ImagesMode.pages ? 'Page ${state.progress + 1} of ${_total(state)}' : 'Working',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static int _total(PdfImagesState s) {
    final text = s.range.trim();
    final parsed = PageRanges.parse(text.isEmpty ? '1-${s.pageCount}' : text, s.pageCount);
    return parsed.ok ? parsed.pages.length : s.pageCount;
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.state, required this.onShare, required this.onGallery});
  final PdfImagesState state;
  final VoidCallback onShare;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final files = state.files;
    final title = files.isEmpty
        ? 'No pictures found'
        : (state.mode == ImagesMode.pages
              ? (files.length == 1 ? '1 page is ready' : '${files.length} pages are ready')
              : (files.length == 1 ? '1 picture found' : '${files.length} pictures found'));
    final note = files.isEmpty
        ? 'This PDF has no photos or graphics that can be saved. A scanned PDF is made of page pictures: use Pages instead.'
        : (state.skipped > 0
              ? '${state.skipped} more ${state.skipped == 1 ? 'picture is' : 'pictures are'} in a form that cannot be saved as a picture file. Use Pages to get the whole page as a picture.'
              : 'Share them or keep them in your gallery.');
    return Card(
      key: const ValueKey('images-result'),
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(note, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            if (files.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(files[i]),
                      height: 84,
                      cacheHeight: 168,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(width: 60, child: Icon(AppIcons.gallery)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('images-share'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onShare,
                    icon: const Icon(AppIcons.share, size: 18),
                    label: const Text('Share'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('images-gallery'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onGallery,
                    icon: const Icon(AppIcons.download, size: 18),
                    label: const Text('Save to gallery'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

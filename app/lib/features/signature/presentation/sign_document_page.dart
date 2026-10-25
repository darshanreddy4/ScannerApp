import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../domain/signature.dart';
import 'signature_cubits.dart';

/// Puts a saved signature on a PDF or photo. The signature is dragged into place on a preview of the page.
class SignDocumentPage extends StatelessWidget {
  const SignDocumentPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SignDocumentCubit(signer: sl<DocumentSigner>(), store: sl<SignatureStore>(), outputDir: getTemporaryDirectory)..loadSignatures(),
    child: const _SignView(),
  );
}

class _SignView extends StatefulWidget {
  const _SignView();

  @override
  State<_SignView> createState() => _SignViewState();
}

class _SignViewState extends State<_SignView> {
  bool _holding = false;

  Future<void> _pickFile(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png']);
      final path = picked.isEmpty ? null : picked.first.path;
      if (path == null || !context.mounted) return;
      await context.read<SignDocumentCubit>().open(path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _pickPhoto(BuildContext context) async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !context.mounted) return;
      await context.read<SignDocumentCubit>().open(file.path);
    } catch (_) {
      if (context.mounted) showFailure(context, const PermissionFailure('Photo library access is unavailable.'));
    }
  }

  Future<void> _share(SignedFile f) async {
    final failure = (await sl<ShareService>().shareFiles(paths: [f.path], mimeType: f.mimeType)).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _save(SignedFile f) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: f.path, fileName: f.name.replaceAll(' ', '_'), mimeType: f.mimeType);
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  Future<void> _gallery(SignedFile f) async {
    final result = await sl<SaveService>().saveImagesToGallery([f.path]);
    if (!mounted) return;
    final failure = result.failureOrNull;
    failure != null ? showFailure(context, failure) : showMessage(context, 'Saved to your gallery');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SignDocumentCubit, SignDocumentState>(
      listenWhen: (a, b) => b.failure != null && a.failure != b.failure,
      listener: (context, s) {
        showFailure(context, s.failure!);
        context.read<SignDocumentCubit>().clearFailure();
      },
      builder: (context, state) {
        final cubit = context.read<SignDocumentCubit>();
        final doc = state.document;
        final sig = state.selected;
        return Scaffold(
          appBar: AppBar(title: const Text('Sign a document')),
          body: SafeArea(
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final pad = contentPadding(context, base: AppSpacing.md, maxWidth: 640);
                    return ListView(
                      physics: _holding ? const NeverScrollableScrollPhysics() : null,
                      padding: pad,
                      children: [
                        if (state.signatures.isEmpty && state.status == SignStatus.idle)
                          const Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: EdgeInsets.all(AppSpacing.md),
                              child: Text(
                                'You have no saved signature yet. Go back and draw one or use a photo of your signature first.',
                                style: TextStyle(height: 1.4),
                              ),
                            ),
                          ),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: state.busy ? null : () => _pickFile(context),
                              icon: const Icon(AppIcons.importFile, size: 18),
                              label: Text(doc == null ? 'Choose a PDF or photo' : 'Change file'),
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: state.busy ? null : () => _pickPhoto(context),
                              icon: const Icon(AppIcons.gallery, size: 18),
                              label: const Text('From gallery'),
                            ),
                          ],
                        ),
                        if (doc != null && sig != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          _PagePreview(
                            state: state,
                            maxWidth: (box.maxWidth - pad.horizontal).clamp(120.0, 560.0),
                            onHold: (v) => setState(() => _holding = v),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          if (state.pageCount > 1)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Previous page',
                                  onPressed: state.page > 0 ? () => cubit.setPage(state.page - 1) : null,
                                  icon: const Icon(AppIcons.back),
                                ),
                                Text('Page ${state.page + 1} of ${state.pageCount}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                IconButton(
                                  tooltip: 'Next page',
                                  onPressed: state.page < state.pageCount - 1 ? () => cubit.setPage(state.page + 1) : null,
                                  icon: const Icon(AppIcons.next),
                                ),
                              ],
                            ),
                          const Text(
                            'Drag the signature where it should go.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              const Icon(AppIcons.fullFrame, size: 16, color: AppColors.inkMuted),
                              Expanded(
                                child: Slider(
                                  value: state.placement.width.clamp(SignPlacement.minWidth, SignPlacement.maxWidth),
                                  min: SignPlacement.minWidth,
                                  max: SignPlacement.maxWidth,
                                  onChanged: cubit.resize,
                                ),
                              ),
                              const Text('Size', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                            ],
                          ),
                          if (state.signatures.length > 1) ...[
                            const SizedBox(height: AppSpacing.sm),
                            const Text('Signature', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: AppSpacing.xs),
                            SizedBox(
                              height: 64,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  for (final s in state.signatures)
                                    Padding(
                                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                                      child: InkWell(
                                        key: ValueKey('sig-${s.id}'),
                                        onTap: () => cubit.select(s),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          width: 110,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: s.id == sig.id ? AppColors.primary : AppColors.border, width: s.id == sig.id ? 2.5 : 1),
                                            color: Colors.white,
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          child: Image.file(File(s.path), fit: BoxFit.contain),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (state.pageCount > 1) ...[
                            const SizedBox(height: AppSpacing.md),
                            const Text('Put it on', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.xs,
                              children: [
                                for (final t in SignPages.values)
                                  ChoiceChip(label: Text(t.label), selected: state.target == t, onSelected: (_) => cubit.setTarget(t)),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          FilledButton.icon(
                            onPressed: state.busy ? null : cubit.sign,
                            icon: const Icon(AppIcons.check, size: 18),
                            label: Text(state.status == SignStatus.signing ? 'Signing page ${state.done} of ${state.total}' : 'Add signature'),
                          ),
                          if (state.result != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            _Result(
                              file: state.result!,
                              onShare: () => _share(state.result!),
                              onSave: () => _save(state.result!),
                              onGallery: () => _gallery(state.result!),
                            ),
                          ],
                        ],
                        const SizedBox(height: AppSpacing.md),
                        const _Note(),
                      ],
                    );
                  },
                ),
                BusyOverlay(visible: state.status == SignStatus.opening, label: 'Opening...'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.state, required this.maxWidth, required this.onHold});
  final SignDocumentState state;
  final double maxWidth;
  final void Function(bool) onHold;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SignDocumentCubit>();
    final doc = state.document!, sig = state.selected!;
    final aspect = doc.aspectOf(state.page);
    const maxHeight = 520.0;
    final w = (maxHeight * aspect).clamp(0.0, maxWidth);
    final h = w / aspect;
    final p = state.placement.clamped(aspect: sig.aspect, pageAspect: aspect);
    final sw = p.width * w, sh = sw / sig.aspect;
    return Center(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.file(
                  File(doc.pages[state.page]),
                  fit: BoxFit.fill,
                  cacheWidth: 1200,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black12),
                ),
              ),
              Positioned(
                key: const ValueKey('signature-overlay'),
                left: p.centerX * w - sw / 2,
                top: p.centerY * h - sh / 2,
                width: sw,
                height: sh,
                child: Listener(
                  onPointerDown: (_) => onHold(true),
                  onPointerUp: (_) => onHold(false),
                  onPointerCancel: (_) => onHold(false),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: (d) => cubit.move(d.delta.dx / w, d.delta.dy / h),
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: AppColors.primary.withValues(alpha: 0.7), width: 1.2)),
                      child: Image.file(File(sig.path), fit: BoxFit.fill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.file, required this.onShare, required this.onSave, required this.onGallery});
  final SignedFile file;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final isPdf = file.mimeType == 'application/pdf';
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.primarySoft,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Signed', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              isPdf ? '${file.name}: signature added to ${file.signedPages} of ${file.pages} ${file.pages == 1 ? 'page' : 'pages'}.' : '${file.name} is ready.',
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onShare,
                  icon: const Icon(AppIcons.share, size: 18),
                  label: const Text('Share'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: onSave,
                  icon: const Icon(AppIcons.storage, size: 18),
                  label: const Text('Save to Files'),
                ),
                if (!isPdf)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onGallery,
                    icon: const Icon(AppIcons.download, size: 18),
                    label: const Text('Gallery'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) => const Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: 20, color: AppColors.primary),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'The signature is added as a picture. PDF pages become pictures too, so text in the new PDF can no longer be selected. Password-protected PDFs cannot be opened.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';

import '../../../app/di.dart';
import '../../../app/router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';
import '../../export/domain/entities/export_options.dart';
import '../../export/domain/usecases/export_usecases.dart';
import '../data/library_files.dart';
import '../domain/entities/scanned_document.dart';
import '../domain/usecases/document_usecases.dart';
import 'widgets/document_actions.dart' show confirmOwner;
import 'widgets/document_widgets.dart' show DocThumb;

/// How a library item is handed to a tool.
enum LibraryUse { file, pdf, images }

const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'heic'};

Set<String> _normalized(Iterable<String> extensions) => {for (final e in extensions) e.toLowerCase().replaceFirst('.', '')};

/// What a tool that accepts [extensions] receives from [doc], or null when it cannot use it.
/// A scanned document becomes a PDF when the tool takes PDFs, otherwise its pages become pictures.
LibraryUse? libraryUseOf(ScannedDocument doc, Iterable<String> extensions) {
  final wanted = _normalized(extensions);
  if (doc.isFile) return wanted.contains(doc.fileExtension) ? LibraryUse.file : null;
  if (doc.pages.isEmpty) return null;
  if (wanted.contains('pdf')) return LibraryUse.pdf;
  if (wanted.any(_imageExtensions.contains)) return LibraryUse.images;
  return null;
}

BuildContext? _contextOrRoot(BuildContext? context) => context != null && context.mounted ? context : appRouter.routerDelegate.navigatorKey.currentContext;

/// True when the library holds something a tool taking [extensions] could use.
Future<bool> _libraryHasMatches(Iterable<String> extensions) async {
  try {
    final docs = (await sl<ListDocuments>()()).valueOrNull ?? const <ScannedDocument>[];
    return docs.any((d) => libraryUseOf(d, extensions) != null);
  } catch (_) {
    return false;
  }
}

enum _Source { device, library }

Future<_Source?> _askSource(BuildContext context, {required String deviceLabel, required IconData deviceIcon}) => showModalBottomSheet<_Source>(
  context: context,
  showDragHandle: true,
  builder: (ctx) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('source-device'),
          leading: Icon(deviceIcon),
          title: Text(deviceLabel),
          onTap: () => Navigator.pop(ctx, _Source.device),
        ),
        ListTile(
          key: const ValueKey('source-library'),
          leading: const Icon(AppIcons.library),
          title: const Text('From Doculoom'),
          subtitle: const Text('Documents and files you made or saved in this app'),
          onTap: () => Navigator.pop(ctx, _Source.library),
        ),
      ],
    ),
  ),
);

/// Like picking from the Files app, with a second place to choose from: the documents and files already in Doculoom.
/// Returns the chosen paths, empty when nothing was chosen. [type] and [allowedExtensions] work as in the file picker.
Future<List<String>> pickFilePaths(
  BuildContext? context, {
  FileType type = FileType.custom,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
}) async {
  final extensions = type == FileType.image ? ['jpg', 'jpeg', 'png', 'webp'] : (allowedExtensions ?? const <String>[]);
  Future<List<String>> device() async {
    final picked = await FilePicker.pickFiles(type: type, allowedExtensions: allowedExtensions);
    final paths = [
      for (final f in picked)
        if (f.path != null) f.path!,
    ];
    return allowMultiple || paths.length < 2 ? paths : [paths.first];
  }

  final ctx = _contextOrRoot(context);
  if (ctx == null || extensions.isEmpty || !await _libraryHasMatches(extensions) || !ctx.mounted) return device();
  final source = await _askSource(ctx, deviceLabel: 'From this device', deviceIcon: AppIcons.storage);
  if (source == null) return const [];
  if (source == _Source.device) return device();
  if (!ctx.mounted) return const [];
  return pickFromLibrary(ctx, extensions: extensions, multiple: allowMultiple);
}

/// Photos from the gallery, or pictures already in Doculoom.
Future<List<String>> pickPhotoPaths(BuildContext? context, {bool multiple = true, bool requestFullMetadata = true}) async {
  Future<List<String>> device() async {
    final picker = ImagePicker();
    if (multiple) return [for (final f in await picker.pickMultiImage(requestFullMetadata: requestFullMetadata)) f.path];
    final one = await picker.pickImage(source: ImageSource.gallery, requestFullMetadata: requestFullMetadata);
    return one == null ? const [] : [one.path];
  }

  const extensions = ['jpg', 'jpeg', 'png'];
  final ctx = _contextOrRoot(context);
  if (ctx == null || !await _libraryHasMatches(extensions) || !ctx.mounted) return device();
  final source = await _askSource(ctx, deviceLabel: 'From your photos', deviceIcon: AppIcons.gallery);
  if (source == null) return const [];
  if (source == _Source.device) return device();
  if (!ctx.mounted) return const [];
  return pickFromLibrary(ctx, extensions: extensions, multiple: multiple);
}

/// Opens the list of Doculoom documents and files that a tool taking [extensions] can use and returns copies of the chosen ones.
Future<List<String>> pickFromLibrary(BuildContext context, {required Iterable<String> extensions, bool multiple = false}) async {
  final chosen = await showModalBottomSheet<List<ScannedDocument>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: LibraryPickerSheet(extensions: extensions.toList(), multiple: multiple),
    ),
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return const [];
  final paths = await runBusy(context, 'Preparing files', () => _prepare(chosen, extensions.toList()));
  return paths;
}

/// Makes private copies of the chosen items in the form the tool takes, so a tool can never change what is in the library.
Future<List<String>> _prepare(List<ScannedDocument> docs, List<String> extensions) async {
  final library = sl<LibraryFiles>();
  final out = <String>[];
  for (final doc in docs) {
    switch (libraryUseOf(doc, extensions)) {
      case LibraryUse.file:
        out.add(await library.stage(doc));
      case LibraryUse.pdf:
        final built = await sl<ExportDocument>()(document: doc, format: ExportFormat.pdf, quality: ExportQuality.high);
        final path = built.valueOrNull;
        if (path != null) out.add(await library.stageCopy(path, '${LibraryFiles.safeFileName(doc.title)}.pdf'));
      case LibraryUse.images:
        out.addAll(await library.stagePages(doc));
      case null:
        break;
    }
  }
  return out;
}

/// The list the person chooses from: folders, then the documents and files a tool can use.
class LibraryPickerSheet extends StatefulWidget {
  const LibraryPickerSheet({super.key, required this.extensions, required this.multiple});
  final List<String> extensions;
  final bool multiple;

  @override
  State<LibraryPickerSheet> createState() => _LibraryPickerSheetState();
}

class _LibraryPickerSheetState extends State<LibraryPickerSheet> {
  List<ScannedDocument> _docs = const [];
  List<Folder> _folders = const [];
  var _loading = true;
  String? _folderId;
  var _query = '';
  final _picked = <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = (await sl<ListDocuments>()()).valueOrNull ?? const <ScannedDocument>[];
    final folders = (await sl<ListFolders>()()).valueOrNull ?? const <Folder>[];
    if (!mounted) return;
    setState(() {
      _docs = [for (final d in docs) if (libraryUseOf(d, widget.extensions) != null) d]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _folders = folders;
      _loading = false;
    });
  }

  Folder? get _folder => _folders.where((f) => f.id == _folderId).firstOrNull;

  int _countIn(Folder f) => _docs.where((d) => d.folderId == f.id).length;

  Future<void> _openFolder(Folder f) async {
    if (f.locked && !await confirmOwner(context, 'Unlock "${f.name}"', allowIfUnavailable: true)) return;
    if (mounted) setState(() => _folderId = f.id);
  }

  Future<void> _tap(ScannedDocument d) async {
    if (d.locked && !await confirmOwner(context, 'Unlock "${d.title}"', allowIfUnavailable: true)) return;
    if (!mounted) return;
    if (!widget.multiple) {
      Navigator.pop(context, [d]);
      return;
    }
    setState(() => _picked.contains(d.id) ? _picked.remove(d.id) : _picked.add(d.id));
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final lockedFolders = {
      for (final f in _folders)
        if (f.locked) f.id,
    };
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final d in _docs)
        if (searching ? (!lockedFolders.contains(d.folderId) && d.title.toLowerCase().contains(q)) : d.folderId == _folderId) d,
    ];
    final folders = _folderId == null && !searching ? [for (final f in _folders) if (_countIn(f) > 0) f] : const <Folder>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
          child: Row(
            children: [
              if (_folderId != null)
                IconButton(
                  key: const ValueKey('library-back'),
                  tooltip: tr('Back'),
                  icon: const Icon(AppIcons.back),
                  onPressed: () => setState(() => _folderId = null),
                ),
              Expanded(
                child: Text(_folder?.name ?? 'From Doculoom', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: TextField(
            key: const ValueKey('library-search'),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(hintText: tr('Search documents'), prefixIcon: const Icon(AppIcons.search, size: 20), isDense: true),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (shown.isEmpty && folders.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Text(searching ? 'No documents match' : 'Nothing here that this tool can use', style: const TextStyle(color: AppColors.inkMuted)),
                  ),
                )
              : ListView(
                  children: [
                    for (final f in folders)
                      ListTile(
                        key: ValueKey('library-folder-${f.id}'),
                        leading: const Icon(AppIcons.emptyDocs, color: AppColors.primary),
                        title: Text(f.name),
                        subtitle: Text('${_countIn(f)} item${_countIn(f) == 1 ? '' : 's'}'),
                        trailing: f.locked ? const Icon(AppIcons.lock, size: 16, color: AppColors.inkMuted) : const Icon(AppIcons.back, size: 16, textDirection: TextDirection.rtl),
                        onTap: () => _openFolder(f),
                      ),
                    for (final d in shown) _tile(d),
                  ],
                ),
        ),
        if (widget.multiple)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FilledButton(
                key: const ValueKey('library-use'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, [for (final id in _picked) _docs.firstWhere((d) => d.id == id)]),
                child: Text(_picked.isEmpty ? 'Choose files' : trf('Use {n} selected', {'n': _picked.length})),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile(ScannedDocument d) {
    final use = libraryUseOf(d, widget.extensions);
    final order = _picked.indexOf(d.id);
    final detail = d.isFile ? tr(d.fileKind.label) : tr(use == LibraryUse.pdf ? 'Scan, used as a PDF' : 'Scan, used as pictures');
    return ListTile(
      key: ValueKey('library-item-${d.id}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 44, height: 56, child: DocThumb(document: d, cacheWidth: 120)),
      ),
      title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(detail),
      trailing: widget.multiple ? Icon(order >= 0 ? Icons.check_circle : Icons.circle_outlined, color: order >= 0 ? AppColors.primary : AppColors.inkMuted) : null,
      onTap: () => _tap(d),
    );
  }
}

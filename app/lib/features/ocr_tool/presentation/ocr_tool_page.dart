import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../../ocr/domain/ocr_engine.dart';
import '../../ocr/domain/ocr_models.dart';
import '../../pdf_tools/data/pdf_picture_pages.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../speech/domain/speech_chunks.dart';
import '../../speech/presentation/read_aloud_page.dart';
import '../../translate/domain/translation_languages.dart';
import '../../translate/domain/translation_service.dart';
import 'ocr_tool_cubit.dart';
import '../../../core/widgets/text.dart';
import '../../../core/i18n/tr.dart';

/// Where the pictures and files come from; replaced in tests.
typedef FilePickerFn = Future<List<String>> Function();

Future<List<String>> _pickImages() async {
  final files = await ImagePicker().pickMultiImage();
  return [for (final f in files) f.path];
}

Future<List<String>> _pickFiles() async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: [...ocrToolImageExtensions, 'pdf']);
  return [
    for (final f in picked)
      if (f.path != null) f.path!,
  ];
}

/// The OCR tool: pictures and PDFs in, editable text out, with translation into another language and a voice to listen to it.
class OcrToolPage extends StatelessWidget {
  const OcrToolPage({super.key, this.engine, this.translator, this.pdfPages, this.pickImages = _pickImages, this.pickFiles = _pickFiles});

  /// For tests; the phone's text reader and translator are used otherwise.
  final OcrEngine? engine;
  final TranslationService? translator;
  final PdfPicturePages Function()? pdfPages;
  final FilePickerFn pickImages;
  final FilePickerFn pickFiles;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => OcrToolCubit(
      engine: engine ?? sl<OcrEngine>(),
      translator: translator ?? sl<TranslationService>(),
      outputDir: getTemporaryDirectory,
      script: context.read<SettingsCubit>().state.ocrScript,
      target: _defaultTarget(),
      pdfPages: pdfPages,
    ),
    child: _ToolView(pickImages: pickImages, pickFiles: pickFiles),
  );

  /// The language of the phone; when that is English, Hindi (text in the pictures is then more likely in another language).
  static String _defaultTarget() {
    final code = translationCodeFor(PlatformDispatcher.instance.locale.languageCode);
    if (code == null) return 'en';
    return code == 'en' ? 'hi' : code;
  }
}

class _ToolView extends StatefulWidget {
  const _ToolView({required this.pickImages, required this.pickFiles});
  final FilePickerFn pickImages;
  final FilePickerFn pickFiles;

  @override
  State<_ToolView> createState() => _ToolViewState();
}

class _ToolViewState extends State<_ToolView> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add(FilePickerFn pick) async {
    try {
      final paths = await pick();
      if (paths.isEmpty || !mounted) return;
      await context.read<OcrToolCubit>().addFiles(paths);
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('The pictures or files could not be opened.'));
    }
  }

  Future<void> _shareText(String text, String name, String title) async {
    final dir = await Directory(p.join((await getTemporaryDirectory()).path, 'ocr_tool')).create(recursive: true);
    final file = await File(p.join(dir.path, '$name.txt')).writeAsString(text, flush: true);
    final failure = (await sl<ShareService>().shareFile(path: file.path, mimeType: 'text/plain', subject: title)).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showMessage(context, message);
  }

  void _listen(String text, String title, {String? language}) => context.push(
    '/read-aloud',
    extra: ReadAloudArgs(title: title, text: text, language: language),
  );

  /// Opens the language list; returns the code, '' for "detect automatically", or null when closed.
  Future<String?> _pickLanguage({required bool allowAuto, required String? current}) {
    final cubit = context.read<OcrToolCubit>();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LanguageSheet(allowAuto: allowAuto, current: current, downloaded: cubit.downloadedLanguages()),
    );
  }

  Future<void> _manageData() async {
    final cubit = context.read<OcrToolCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DataSheet(cubit: cubit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OcrToolCubit, OcrToolState>(
      listenWhen: (a, b) => a.text != b.text && b.text != _text.text,
      listener: (context, s) => _text.value = TextEditingValue(
        text: s.text,
        selection: TextSelection.collapsed(offset: s.text.length),
      ),
      builder: (context, state) {
        final cubit = context.read<OcrToolCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('OCR and translate'),
            actions: [
              if (state.hasText && !state.reading) TextButton(key: const ValueKey('ocrtool-clear'), onPressed: cubit.clear, child: const Text('Clear')),
              PopupMenuButton<String>(
                key: const ValueKey('ocrtool-menu'),
                tooltip: tr('More'),
                icon: const Icon(AppIcons.more),
                onSelected: (_) => _manageData(),
                itemBuilder: (_) => const [PopupMenuItem(value: 'data', child: Text('Language data on this phone'))],
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: contentPadding(context, base: AppSpacing.md, maxWidth: 720),
              children: [
                _AddCard(state: state, onImages: () => _add(widget.pickImages), onFiles: () => _add(widget.pickFiles)),
                if (state.reading) ...[const SizedBox(height: AppSpacing.md), _Reading(state: state)],
                for (final note in state.notes)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      note,
                      key: const ValueKey('ocrtool-note'),
                      style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted, height: 1.4),
                    ),
                  ),
                if (state.failure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      state.failure!.message,
                      key: const ValueKey('ocrtool-failure'),
                      style: const TextStyle(color: AppColors.danger, height: 1.4),
                    ),
                  ),
                if (state.hasText || (state.status == OcrToolStatus.ready && state.text.isNotEmpty)) ...[
                  const SizedBox(height: AppSpacing.md),
                  _TextCard(
                    controller: _text,
                    onChanged: cubit.setText,
                    onCopy: () => _copy(state.text, 'Text copied'),
                    onShare: () => _shareText(state.text, 'text', 'Text'),
                    onListen: () => _listen(state.text, 'Text', language: state.sourceDetected || state.source != null ? speechVoiceFor(state.source!) : null),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _TranslateCard(
                    state: state,
                    onFrom: () async {
                      final code = await _pickLanguage(allowAuto: true, current: state.source);
                      if (code != null) cubit.setSource(code.isEmpty ? null : code);
                    },
                    onTo: () async {
                      final code = await _pickLanguage(allowAuto: false, current: state.target);
                      if (code != null && code.isNotEmpty) cubit.setTarget(code);
                    },
                    onCopy: () => _copy(state.translated!, 'Translation copied'),
                    onShare: () => _shareText(state.translated!, 'translation', 'Translation'),
                    onListen: () => _listen(state.translated!, 'Translation', language: speechVoiceFor(state.target)),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const _Note(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AddCard extends StatelessWidget {
  const _AddCard({required this.state, required this.onImages, required this.onFiles});
  final OcrToolState state;
  final VoidCallback onImages;
  final VoidCallback onFiles;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OcrToolCubit>();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.hasText ? 'Add more' : 'Read text from pictures and PDFs', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  key: const ValueKey('ocrtool-images'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: state.reading ? null : onImages,
                  icon: const Icon(AppIcons.gallery, size: 18),
                  label: const Text('Choose pictures'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('ocrtool-files'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: state.reading ? null : onFiles,
                  icon: const Icon(AppIcons.importFile, size: 18),
                  label: const Text('Choose files'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('Language of the text in the pictures', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final s in OcrScript.values)
                  ChoiceChip(
                    key: ValueKey('ocrtool-script-${s.name}'),
                    label: Text(s.label),
                    selected: state.script == s,
                    onSelected: state.reading ? null : (_) => cubit.setScript(s),
                  ),
              ],
            ),
            Text(state.script.languages, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
          ],
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({required this.state});
  final OcrToolState state;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.total > 1 ? 'Reading ${state.label} (file ${(state.done + 1).clamp(1, state.total)} of ${state.total})' : 'Reading ${state.label}',
            key: const ValueKey('ocrtool-progress'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          const LinearProgressIndicator(),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(key: const ValueKey('ocrtool-cancel'), onPressed: context.read<OcrToolCubit>().cancel, child: const Text('Stop')),
          ),
        ],
      ),
    ),
  );
}

class _TextCard extends StatelessWidget {
  const _TextCard({required this.controller, required this.onChanged, required this.onCopy, required this.onShare, required this.onListen});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Text', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('ocrtool-text'),
            controller: controller,
            minLines: 6,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(hintText: tr('The text from your pictures appears here. You can correct it.')),
            onChanged: onChanged,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const ValueKey('ocrtool-listen'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: onListen,
                icon: const Icon(AppIcons.speak, size: 18),
                label: const Text('Listen'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('ocrtool-copy'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: onCopy,
                icon: const Icon(AppIcons.copy, size: 18),
                label: const Text('Copy'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('ocrtool-share'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: onShare,
                icon: const Icon(AppIcons.share, size: 18),
                label: const Text('Share'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _TranslateCard extends StatelessWidget {
  const _TranslateCard({required this.state, required this.onFrom, required this.onTo, required this.onCopy, required this.onShare, required this.onListen});
  final OcrToolState state;
  final VoidCallback onFrom;
  final VoidCallback onTo;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<OcrToolCubit>();
    final from = state.source == null ? 'Detect automatically' : '${languageName(state.source!)}${state.sourceDetected ? ' (detected)' : ''}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(AppIcons.translate, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Translate', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _LanguageButton(key: const ValueKey('ocrtool-from'), label: 'From', value: from, onTap: state.translating ? null : onFrom),
                ),
                IconButton(
                  key: const ValueKey('ocrtool-swap'),
                  tooltip: tr('Swap languages'),
                  onPressed: state.translating || state.source == null ? null : () => _swap(cubit),
                  icon: const Icon(AppIcons.swap, size: 18),
                ),
                Expanded(
                  child: _LanguageButton(
                    key: const ValueKey('ocrtool-to'),
                    label: 'To',
                    value: languageName(state.target),
                    onTap: state.translating ? null : onTo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (state.translate == TranslateStatus.needsDownload)
              _DownloadAsk(pending: state.pending, onYes: cubit.confirmDownloadAndTranslate, onNo: cubit.dismissDownload)
            else if (state.translating)
              _TranslateProgress(state: state, onCancel: cubit.cancelTranslation)
            else
              FilledButton.icon(
                key: const ValueKey('ocrtool-translate'),
                onPressed: state.hasText ? cubit.translate : null,
                icon: const Icon(AppIcons.translate, size: 18),
                label: const Text('Translate'),
              ),
            if (state.translate == TranslateStatus.failed && state.translateMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  state.translateMessage!,
                  key: const ValueKey('ocrtool-translate-failure'),
                  style: const TextStyle(color: AppColors.danger, height: 1.4),
                ),
              ),
            if (state.translated != null) ...[
              const Divider(height: AppSpacing.lg),
              Text('Translation (${languageName(state.target)})', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.sm),
              SelectableText(state.translated!, key: const ValueKey('ocrtool-translation'), style: const TextStyle(height: 1.4)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('ocrtool-listen-translation'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onListen,
                    icon: const Icon(AppIcons.speak, size: 18),
                    label: const Text('Listen'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('ocrtool-copy-translation'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onCopy,
                    icon: const Icon(AppIcons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('ocrtool-share-translation'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: onShare,
                    icon: const Icon(AppIcons.share, size: 18),
                    label: const Text('Share'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('ocrtool-use-translation'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: cubit.useTranslationAsText,
                    icon: const Icon(AppIcons.replace, size: 18),
                    label: const Text('Use as text'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The text stays; the languages change places so the same text can go the other way after "Use as text".
  void _swap(OcrToolCubit cubit) {
    final from = state.source;
    if (from == null) return;
    final to = state.target;
    cubit
      ..setTarget(from)
      ..setSource(to);
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 10)),
    onPressed: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkMuted)),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
      ],
    ),
  );
}

class _DownloadAsk extends StatelessWidget {
  const _DownloadAsk({required this.pending, required this.onYes, required this.onNo});
  final List<String> pending;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('ocrtool-download-ask'),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: const Color(0xFFFFF7E0), borderRadius: BorderRadius.circular(AppSpacing.radius)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Download ${pending.map(languageName).join(' and ')} language data?', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text(
          'Translating happens on your phone, but each language needs its data once: about 30 MB each. This download is the only thing that uses the internet, and it can be removed again from the menu.',
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const ValueKey('ocrtool-download'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: onYes,
              child: const Text('Download and translate'),
            ),
            TextButton(key: const ValueKey('ocrtool-download-no'), onPressed: onNo, child: const Text('Not now')),
          ],
        ),
      ],
    ),
  );
}

class _TranslateProgress extends StatelessWidget {
  const _TranslateProgress({required this.state, required this.onCancel});
  final OcrToolState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = switch (state.translate) {
      TranslateStatus.downloading => 'Downloading ${state.pending.map(languageName).join(' and ')} language data',
      TranslateStatus.translating when state.translateTotal > 1 => 'Translating ${state.translateDone} of ${state.translateTotal}',
      _ => 'Translating',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, key: const ValueKey('ocrtool-translate-progress')),
        const SizedBox(height: AppSpacing.xs),
        const LinearProgressIndicator(),
        if (state.translate == TranslateStatus.translating)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(key: const ValueKey('ocrtool-translate-cancel'), onPressed: onCancel, child: const Text('Stop')),
          ),
      ],
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
          Icon(AppIcons.shield, size: 20, color: AppColors.success),
          SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Text(
              'Pictures and PDFs are read on your phone and are never uploaded. Translation also runs on the phone; only the one-time download of a language\'s data needs the internet. Listening uses your phone\'s own voice.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A searchable list of languages. Returns the code, '' for "Detect automatically", or null when closed.
class _LanguageSheet extends StatefulWidget {
  const _LanguageSheet({required this.allowAuto, required this.current, required this.downloaded});
  final bool allowAuto;
  final String? current;
  final Future<List<String>> downloaded;

  @override
  State<_LanguageSheet> createState() => _LanguageSheetState();
}

class _LanguageSheetState extends State<_LanguageSheet> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final languages = [
      for (final l in translationLanguages)
        if (q.isEmpty || l.name.toLowerCase().contains(q) || l.code == q) l,
    ];
    return FutureBuilder<List<String>>(
      future: widget.downloaded,
      builder: (context, snap) {
        final have = snap.data ?? const <String>[];
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
                child: TextField(
                  key: const ValueKey('lang-search'),
                  decoration: InputDecoration(prefixIcon: Icon(AppIcons.search, size: 20), hintText: tr('Search languages')),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    if (widget.allowAuto && q.isEmpty)
                      ListTile(
                        key: const ValueKey('lang-auto'),
                        title: const Text('Detect automatically'),
                        trailing: widget.current == null ? const Icon(AppIcons.check) : null,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                    for (final l in languages)
                      ListTile(
                        key: ValueKey('lang-${l.code}'),
                        title: Text(l.name),
                        subtitle: have.contains(l.code) ? const Text('On this phone', style: TextStyle(fontSize: 12)) : null,
                        trailing: widget.current == l.code ? const Icon(AppIcons.check) : null,
                        onTap: () => Navigator.pop(context, l.code),
                      ),
                    if (languages.isEmpty) const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text('No language matches.')),
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

/// The languages whose data is on the phone, each with a button to remove it.
class _DataSheet extends StatefulWidget {
  const _DataSheet({required this.cubit});
  final OcrToolCubit cubit;

  @override
  State<_DataSheet> createState() => _DataSheetState();
}

class _DataSheetState extends State<_DataSheet> {
  late Future<List<String>> _have = widget.cubit.downloadedLanguages();
  String? _downloading;
  String? _message;

  Future<void> _download() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _LanguageSheet(allowAuto: false, current: null, downloaded: widget.cubit.downloadedLanguages()),
    );
    if (code == null || code.isEmpty || !mounted) return;
    setState(() {
      _downloading = code;
      _message = null;
    });
    final ok = await widget.cubit.downloadLanguage(code);
    if (!mounted) return;
    final next = widget.cubit.downloadedLanguages();
    setState(() {
      _downloading = null;
      _message = ok ? null : 'The ${languageName(code)} language data could not be downloaded. Check the internet connection and try again.';
      _have = next;
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _have,
    builder: (context, snap) {
      final have = snap.data;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
        children: [
          const Text('Language data on this phone', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Needed to translate without the internet. Remove what you no longer use; it can be downloaded again.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const ValueKey('langdata-download'),
              onPressed: _downloading == null ? _download : null,
              icon: _downloading == null
                  ? const Icon(AppIcons.download, size: 18)
                  : const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              label: Text(_downloading == null ? 'Download a language' : 'Downloading ${languageName(_downloading!)}...'),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _message!,
                key: const ValueKey('langdata-error'),
                style: const TextStyle(fontSize: 12.5, color: AppColors.danger),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (have == null)
            const Center(
              child: Padding(padding: EdgeInsets.all(AppSpacing.md), child: CircularProgressIndicator()),
            )
          else if (have.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Text('Nothing is downloaded yet.', key: ValueKey('langdata-empty')),
            )
          else
            for (final code in have)
              ListTile(
                key: ValueKey('langdata-$code'),
                contentPadding: EdgeInsets.zero,
                title: Text(languageName(code)),
                trailing: IconButton(
                  key: ValueKey('langdata-delete-$code'),
                  tooltip: 'Remove ${languageName(code)}',
                  icon: const Icon(AppIcons.delete),
                  onPressed: () async {
                    await widget.cubit.deleteLanguage(code);
                    if (!mounted) return;
                    final next = widget.cubit.downloadedLanguages();
                    setState(() {
                      _have = next;
                    });
                  },
                ),
              ),
        ],
      );
    },
  );
}

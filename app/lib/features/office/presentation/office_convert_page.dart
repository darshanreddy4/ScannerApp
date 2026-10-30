import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/di.dart';
import '../../../core/error/failures.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/responsive.dart';
import '../../export/domain/repositories/export_repository.dart';
import '../convert/office_converter.dart';
import '../sheets/presentation/sheet_page.dart';
import '../../../core/widgets/text.dart';

/// One conversion: choose the file or files, convert, then share or save the results.
class OfficeConvertPage extends StatefulWidget {
  const OfficeConvertPage({super.key, required this.conversion, this.initialInputs = const []});

  final OfficeConversion conversion;

  /// Files already chosen, for example when the page is opened from a viewer.
  final List<String> initialInputs;

  @override
  State<OfficeConvertPage> createState() => _OfficeConvertPageState();
}

class _OfficeConvertPageState extends State<OfficeConvertPage> {
  late final _inputs = <String>[...widget.initialInputs];
  var _running = false;
  String _progress = '';
  Failure? _failure;
  List<ConvertedFile>? _results;

  OfficeConversion get kind => widget.conversion;

  Future<void> _pick() async {
    try {
      final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: kind.extensions);
      final paths = [
        for (final f in picked)
          if (f.path != null) f.path!,
      ];
      if (paths.isEmpty || !mounted) return;
      setState(() {
        if (kind.multiple) {
          _inputs.addAll(paths);
        } else {
          _inputs
            ..clear()
            ..add(paths.first);
        }
        _results = null;
        _failure = null;
      });
    } catch (_) {
      if (mounted) showFailure(context, const PermissionFailure('The file picker is unavailable.'));
    }
  }

  Future<void> _run() async {
    if (_running || _inputs.isEmpty) return;
    setState(() {
      _running = true;
      _progress = 'Working';
      _failure = null;
      _results = null;
    });
    try {
      final results = await sl<OfficeConverter>().convert(kind, List.of(_inputs), onProgress: (s) => mounted ? setState(() => _progress = s) : null);
      if (mounted) setState(() => _results = results);
    } on Failure catch (f) {
      if (mounted) setState(() => _failure = f);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _share(List<ConvertedFile> files) async {
    final failure = (await sl<ShareService>().shareFiles(
      paths: [for (final f in files) f.path],
      mimeType: files.length == 1 ? files.first.mimeType : '*/*',
    )).failureOrNull;
    if (failure != null && mounted) showFailure(context, failure);
  }

  Future<void> _save(ConvertedFile f) async {
    final result = await sl<SaveService>().saveToFiles(sourcePath: f.path, fileName: f.name, mimeType: f.mimeType);
    if (!mounted) return;
    final failure = result.failureOrNull;
    if (failure != null) {
      showFailure(context, failure);
    } else if (result.valueOrNull == true) {
      showMessage(context, 'Saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: Text(kind.title),
        actions: [
          if (_inputs.isNotEmpty && !_running)
            TextButton(
              onPressed: () => setState(() {
                _inputs.clear();
                _results = null;
                _failure = null;
              }),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: contentPadding(context, base: AppSpacing.md, maxWidth: 640),
          children: [
            Text(kind.description, style: const TextStyle(height: 1.4)),
            const SizedBox(height: AppSpacing.md),
            if (_inputs.isEmpty)
              FilledButton.icon(
                key: const ValueKey('convert_pick'),
                onPressed: _pick,
                icon: const Icon(AppIcons.importFile, size: 18),
                label: Text(kind.pickLabel),
              )
            else ...[
              for (final path in _inputs)
                Card(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: ListTile(
                    leading: Icon(kind.isSlides ? AppIcons.slides : AppIcons.sheet, color: AppColors.primary),
                    title: Text(p.basename(path), maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: kind.multiple && !_running
                        ? IconButton(icon: const Icon(AppIcons.close, size: 18), onPressed: () => setState(() => _inputs.remove(path)))
                        : null,
                  ),
                ),
              if (kind.multiple)
                OutlinedButton.icon(onPressed: _running ? null : _pick, icon: const Icon(AppIcons.add, size: 18), label: const Text('Add more'))
              else
                TextButton(onPressed: _running ? null : _pick, child: const Text('Choose a different file')),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const ValueKey('convert_go'),
              onPressed: _inputs.isEmpty || _running ? null : _run,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(AppIcons.convert, size: 18),
              label: Text(_running ? _progress : 'Convert'),
            ),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Text(
                  _failure!.message,
                  key: const ValueKey('convert_error'),
                  style: const TextStyle(color: AppColors.danger, height: 1.4),
                ),
              ),
            if (results != null) ...[
              const SizedBox(height: AppSpacing.md),
              Card(
                key: const ValueKey('convert_result'),
                margin: EdgeInsets.zero,
                color: AppColors.primarySoft,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(results.length == 1 ? 'Done' : 'Done: ${results.length} files', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: AppSpacing.sm),
                      for (final f in results)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${f.name}  (${formatBytes(_size(f.path))})',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              if (results.length > 1) TextButton(onPressed: () => _save(f), child: const Text('Save')),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          FilledButton.icon(
                            key: const ValueKey('convert_share'),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                            onPressed: () => _share(results),
                            icon: const Icon(AppIcons.share, size: 18),
                            label: Text(results.length == 1 ? 'Share' : 'Share all'),
                          ),
                          if (results.length == 1)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: () => _save(results.first),
                              icon: const Icon(AppIcons.storage, size: 18),
                              label: const Text('Save to Files'),
                            ),
                          if (results.length == 1 && results.first.openAs == 'sheet')
                            OutlinedButton.icon(
                              key: const ValueKey('convert_open'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: () => context.push('/sheet', extra: SheetArgs(path: results.first.path)),
                              icon: const Icon(AppIcons.edit, size: 18),
                              label: const Text('Open and edit'),
                            ),
                          if (results.length == 1 && results.first.openAs == 'slides')
                            OutlinedButton.icon(
                              key: const ValueKey('convert_open'),
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                              onPressed: () => context.push('/slides', extra: results.first.path),
                              icon: const Icon(AppIcons.edit, size: 18),
                              label: const Text('Open and edit'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            const _Note(),
          ],
        ),
      ),
    );
  }

  int _size(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
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
              'Everything happens on your phone; files are never uploaded. Pictures of pages are drawn by this app, so very complex layouts can look slightly different from Excel or PowerPoint.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    ),
  );
}

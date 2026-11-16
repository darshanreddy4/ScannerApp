import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Files the person saved to start new documents from: Word files by default, or presentations with [DocTemplateStore.decks].
class DocTemplateStore {
  const DocTemplateStore({this.dir = _defaultDir, this.extension = 'docx'});

  /// Presentations saved as templates.
  const DocTemplateStore.decks({this.dir = _decksDir}) : extension = 'pptx';

  /// Spreadsheets saved as templates.
  const DocTemplateStore.sheets({this.dir = _sheetsDir}) : extension = 'xlsx';

  final Future<Directory> Function() dir;
  final String extension;

  static Future<Directory> _defaultDir() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'my_templates'));
  static Future<Directory> _decksDir() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'my_decks'));
  static Future<Directory> _sheetsDir() async => Directory(p.join((await getApplicationSupportDirectory()).path, 'my_sheets'));

  static String cleanName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), '_').trim();
    return cleaned.isEmpty ? 'Template' : (cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned);
  }

  Future<Directory> _folder() async => (await dir()).create(recursive: true);

  /// The saved templates, newest first.
  Future<List<File>> list() async {
    final folder = await dir();
    if (!await folder.exists()) return const [];
    final files = [
      for (final e in await folder.list().toList())
        if (e is File && e.path.toLowerCase().endsWith('.$extension')) e,
    ];
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Copies [source] in under [name]; an existing template with that name is replaced.
  Future<File> save(String source, String name) async {
    final target = p.join((await _folder()).path, '${cleanName(name)}.$extension');
    return File(source).copy(target);
  }

  Future<void> delete(File template) async {
    if (await template.exists()) await template.delete();
  }
}

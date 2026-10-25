import '../../../core/error/result.dart';

enum ImportKind {
  pdf('PDF', ['pdf']),
  docx('Word document', ['docx']);

  const ImportKind(this.label, this.extensions);
  final String label;
  final List<String> extensions;
}

/// A file converted into page images ready for the scan editor.
class ImportedDocument {
  const ImportedDocument({required this.title, required this.imagePaths});

  final String title;
  final List<String> imagePaths;
}

typedef ImportProgress = void Function(int done, int total);

abstract interface class DocumentImporter {
  Future<Result<ImportedDocument>> import({required ImportKind kind, required String path, ImportProgress? onProgress});
}

class ImportDocumentFile {
  const ImportDocumentFile(this._importer);
  final DocumentImporter _importer;

  Future<Result<ImportedDocument>> call({required ImportKind kind, required String path, ImportProgress? onProgress}) =>
      _importer.import(kind: kind, path: path, onProgress: onProgress);
}

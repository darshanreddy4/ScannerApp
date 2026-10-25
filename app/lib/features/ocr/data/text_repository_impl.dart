import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../documents/data/datasources/document_local_data_source.dart';
import '../domain/ocr_models.dart';
import '../domain/text_repository.dart';

class TextRepositoryImpl implements TextRepository {
  TextRepositoryImpl(this._local);

  final DocumentLocalDataSource _local;

  Failure _db(Object e) => DatabaseFailure('Could not access the saved text.', cause: e);

  static OcrScript _script(String name) => OcrScript.values.firstWhere((s) => s.name == name, orElse: () => OcrScript.latin);

  @override
  Future<Result<List<PageText>>> loadText(String documentId) => guard(() async {
    final rows = await _local.pageTexts(documentId);
    return [
      for (final r in rows)
        PageText(
          position: r['position'] as int,
          script: _script(r['script'] as String),
          markdown: r['markdown'] as String,
          plain: r['plain'] as String,
          edited: (r['edited'] as int? ?? 0) == 1,
        ),
    ];
  }, onError: _db);

  @override
  Future<Result<void>> saveText(String documentId, List<PageText> pages) => guard(() async {
    await _local.replacePageTexts(documentId, [
      for (final p in pages) {'position': p.position, 'script': p.script.name, 'markdown': p.markdown, 'plain': p.plain, 'edited': p.edited ? 1 : 0},
    ]);
  }, onError: _db);

  @override
  Future<Result<void>> updatePageMarkdown(String documentId, int position, String markdown) =>
      guard(() => _local.updatePageTextMarkdown(documentId, position, markdown), onError: _db);

  @override
  Future<Result<void>> clearText(String documentId) => guard(() => _local.clearPageTexts(documentId), onError: _db);

  @override
  Future<Result<Set<String>>> searchText(String query) => guard(() async {
    final q = query.trim();
    if (q.length < 2) return <String>{};
    return _local.documentIdsWithText(q);
  }, onError: _db);
}

import '../../../core/error/result.dart';
import 'ocr_models.dart';

abstract interface class TextRepository {
  /// Saved text for a document, by page. Pages without text are missing.
  Future<Result<List<PageText>>> loadText(String documentId);

  Future<Result<void>> saveText(String documentId, List<PageText> pages);

  /// Replaces one page's text after the person edited it.
  Future<Result<void>> updatePageMarkdown(String documentId, int position, String markdown);

  Future<Result<void>> clearText(String documentId);

  /// Ids of documents whose recognised text contains [query].
  Future<Result<Set<String>>> searchText(String query);
}

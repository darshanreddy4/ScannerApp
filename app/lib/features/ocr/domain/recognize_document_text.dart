import '../../../core/error/failures.dart';
import '../../../core/error/result.dart';
import '../../documents/domain/entities/scanned_document.dart';
import 'ocr_engine.dart';
import 'ocr_models.dart';
import 'text_repository.dart';
import 'text_structurer.dart';

/// Reads every page of a document, turns the result into Markdown and saves it.
class RecognizeDocumentText {
  const RecognizeDocumentText(this._engine, this._repo);

  final OcrEngine _engine;
  final TextRepository _repo;

  Future<Result<List<PageText>>> call({
    required ScannedDocument document,
    required OcrScript script,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = document.pages.length;
    final pages = <PageText>[];
    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) return const Err(OcrFailure('Text recognition was cancelled.'));
      onProgress?.call(i, total);
      final read = await _engine.recognize(document.pages[i].imagePath, script);
      final result = read.valueOrNull;
      if (result == null) return Err(read.failureOrNull!);
      pages.add(PageText(position: i, script: script, markdown: TextStructurer.toMarkdown(result), plain: result.plainText));
    }
    if (isCancelled?.call() ?? false) return const Err(OcrFailure('Text recognition was cancelled.'));
    final saved = await _repo.saveText(document.id, pages);
    final failure = saved.failureOrNull;
    if (failure != null) return Err(failure);
    onProgress?.call(total, total);
    return Ok(pages);
  }
}

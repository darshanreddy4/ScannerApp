import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../export/domain/entities/export_options.dart';
import '../../../export/domain/usecases/export_usecases.dart';
import '../../domain/entities/scanned_document.dart';
import '../../domain/usecases/document_usecases.dart';

class DocumentDetailState {
  const DocumentDetailState({this.document, this.exporting = false, this.failure, this.loading = true});

  final ScannedDocument? document;
  final bool exporting;
  final bool loading;
  final Failure? failure;

  DocumentDetailState copyWith({ScannedDocument? document, bool? exporting, bool? loading, Failure? failure, bool clearFailure = false}) => DocumentDetailState(
    document: document ?? this.document,
    exporting: exporting ?? this.exporting,
    loading: loading ?? this.loading,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

class DocumentDetailCubit extends Cubit<DocumentDetailState> {
  DocumentDetailCubit({
    required this.documentId,
    required GetDocument getDocument,
    required RenameDocument renameDocument,
    required DeleteDocument deleteDocument,
    required ExportDocument exportDocument,
    required ShareFile shareFile,
  }) : _get = getDocument,
       _rename = renameDocument,
       _delete = deleteDocument,
       _export = exportDocument,
       _share = shareFile,
       super(const DocumentDetailState());

  final String documentId;
  final GetDocument _get;
  final RenameDocument _rename;
  final DeleteDocument _delete;
  final ExportDocument _export;
  final ShareFile _share;

  Future<void> load() async {
    final result = await _get(documentId);
    result.when(
      ok: (doc) => emit(state.copyWith(document: doc, loading: false)),
      err: (f) => emit(state.copyWith(loading: false, failure: f)),
    );
  }

  Future<void> rename(String title) async {
    final result = await _rename(documentId, title);
    result.when(
      ok: (doc) => emit(state.copyWith(document: doc, clearFailure: true)),
      err: (f) => emit(state.copyWith(failure: f)),
    );
  }

  Future<bool> delete() async {
    final result = await _delete(documentId);
    return result.when(
      ok: (_) => true,
      err: (f) {
        emit(state.copyWith(failure: f));
        return false;
      },
    );
  }

  /// Builds the file, then opens the OS share sheet. Returns true if the file was produced.
  Future<bool> exportAndShare(ExportFormat format, ExportQuality quality) async {
    final doc = state.document;
    if (doc == null || state.exporting) return false;
    emit(state.copyWith(exporting: true, clearFailure: true));

    final built = await _export(document: doc, format: format, quality: quality);
    final path = built.valueOrNull;
    if (path == null) {
      emit(state.copyWith(exporting: false, failure: built.failureOrNull));
      return false;
    }

    final shared = await _share(path: path, format: format, subject: doc.title);
    emit(state.copyWith(exporting: false, failure: shared.failureOrNull));
    return true;
  }

  /// Builds the file without opening the share sheet (used for QR sharing). Returns its path.
  Future<String?> exportFile(ExportFormat format, ExportQuality quality) async {
    final doc = state.document;
    if (doc == null || state.exporting) return null;
    emit(state.copyWith(exporting: true, clearFailure: true));
    final built = await _export(document: doc, format: format, quality: quality);
    emit(state.copyWith(exporting: false, failure: built.failureOrNull));
    return built.valueOrNull;
  }

  void clearFailure() => emit(state.copyWith(clearFailure: true));
}

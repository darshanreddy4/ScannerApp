import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../domain/entities/scanned_document.dart';
import '../../domain/usecases/document_usecases.dart';

enum LoadStatus { loading, ready, failed }

class DocumentsState extends Equatable {
  const DocumentsState({this.status = LoadStatus.loading, this.documents = const [], this.failure});

  final LoadStatus status;
  final List<ScannedDocument> documents;
  final Failure? failure;

  @override
  List<Object?> get props => [status, documents, failure];
}

class DocumentsCubit extends Cubit<DocumentsState> {
  DocumentsCubit({required ListDocuments listDocuments, required DeleteDocument deleteDocument})
      : _list = listDocuments,
        _delete = deleteDocument,
        super(const DocumentsState());

  final ListDocuments _list;
  final DeleteDocument _delete;

  Future<void> load() async {
    final result = await _list();
    result.when(
      ok: (docs) => emit(DocumentsState(status: LoadStatus.ready, documents: docs)),
      err: (f) => emit(DocumentsState(status: LoadStatus.failed, documents: state.documents, failure: f)),
    );
  }

  Future<Failure?> delete(String id) async {
    final result = await _delete(id);
    final failure = result.failureOrNull;
    if (failure == null) await load();
    return failure;
  }
}

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failures.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/scanned_document.dart';
import '../../../ocr/domain/text_repository.dart';
import '../../domain/usecases/document_usecases.dart';

enum LoadStatus { loading, ready, failed }

enum DocumentSort {
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name (A-Z)');

  const DocumentSort(this.label);
  final String label;
}

class DocumentsState extends Equatable {
  const DocumentsState({
    this.status = LoadStatus.loading,
    this.documents = const [],
    this.folders = const [],
    this.sort = DocumentSort.newest,
    this.gridView = false,
    this.selection = const [],
    this.textMatches = const {},
    this.failure,
  });

  final LoadStatus status;
  final List<ScannedDocument> documents;
  final List<Folder> folders;
  final DocumentSort sort;
  final bool gridView;

  /// Selected document ids, in the order they were picked (merge order).
  final List<String> selection;

  /// Ids of documents whose recognised text matches the current search.
  final Set<String> textMatches;
  final Failure? failure;

  bool get selecting => selection.isNotEmpty;

  List<ScannedDocument> inFolder(String? folderId) => _sorted(documents.where((d) => d.folderId == folderId));

  List<ScannedDocument> _sorted(Iterable<ScannedDocument> source) {
    final list = source.toList();
    switch (sort) {
      case DocumentSort.newest:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case DocumentSort.oldest:
        list.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
      case DocumentSort.name:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    // Stable sort keeps the chosen order inside each group; pinned documents go first.
    return [...list.where((d) => d.pinned), ...list.where((d) => !d.pinned)];
  }

  Set<String> get _lockedFolderIds => {
    for (final f in folders)
      if (f.locked) f.id,
  };

  /// Documents that may appear in cross-folder lists (search, favourites): never those inside a locked folder.
  List<ScannedDocument> get openDocuments => documents.where((d) => !_lockedFolderIds.contains(d.folderId)).toList();

  /// Every document outside locked folders, in the chosen order.
  List<ScannedDocument> get openSorted => _sorted(openDocuments);

  /// Tags in use outside locked folders, most used first; letter case is ignored and the first spelling seen is shown.
  List<String> get allTags {
    final shown = <String, String>{};
    final count = <String, int>{};
    for (final d in openDocuments) {
      for (final t in d.tags) {
        final key = t.toLowerCase();
        shown.putIfAbsent(key, () => t);
        count[key] = (count[key] ?? 0) + 1;
      }
    }
    final keys = count.keys.toList()
      ..sort((a, b) {
        final byCount = count[b]!.compareTo(count[a]!);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return [for (final k in keys) shown[k]!];
  }

  List<ScannedDocument> searchDocuments(String query) {
    final q = query.trim().toLowerCase();
    final tag = q.replaceFirst('#', '');
    return openDocuments
        .where((d) => d.title.toLowerCase().contains(q) || d.tags.any((t) => t.toLowerCase().contains(tag)) || textMatches.contains(d.id))
        .toList();
  }

  List<ScannedDocument> get favoriteDocuments => openDocuments.where((d) => d.favorite).toList();

  List<Folder> get favoriteFolders => folders.where((f) => f.favorite).toList();

  int countIn(String folderId) => documents.where((d) => d.folderId == folderId).length;

  DocumentsState copyWith({
    LoadStatus? status,
    List<ScannedDocument>? documents,
    List<Folder>? folders,
    DocumentSort? sort,
    bool? gridView,
    List<String>? selection,
    Set<String>? textMatches,
    Failure? failure,
  }) => DocumentsState(
    status: status ?? this.status,
    documents: documents ?? this.documents,
    folders: folders ?? this.folders,
    sort: sort ?? this.sort,
    gridView: gridView ?? this.gridView,
    selection: selection ?? this.selection,
    textMatches: textMatches ?? this.textMatches,
    failure: failure,
  );

  @override
  List<Object?> get props => [status, documents, folders, sort, gridView, selection, textMatches, failure];
}

class DocumentsCubit extends Cubit<DocumentsState> {
  DocumentsCubit({
    TextRepository? textRepository,
    required ListDocuments listDocuments,
    required ListFolders listFolders,
    required DeleteDocument deleteDocument,
    required RenameDocument renameDocument,
    required MoveDocument moveDocument,
    required MergeDocuments mergeDocuments,
    required CreateFolder createFolder,
    required RenameFolder renameFolder,
    required UpdateFolderMeta updateFolderMeta,
    required DeleteFolder deleteFolder,
  }) : _list = listDocuments,
       _listFolders = listFolders,
       _delete = deleteDocument,
       _rename = renameDocument,
       _move = moveDocument,
       _merge = mergeDocuments,
       _createFolder = createFolder,
       _renameFolder = renameFolder,
       _updateFolderMeta = updateFolderMeta,
       _deleteFolder = deleteFolder,
       _text = textRepository,
       super(const DocumentsState());

  final ListDocuments _list;
  final ListFolders _listFolders;
  final DeleteDocument _delete;
  final RenameDocument _rename;
  final MoveDocument _move;
  final MergeDocuments _merge;
  final CreateFolder _createFolder;
  final RenameFolder _renameFolder;
  final UpdateFolderMeta _updateFolderMeta;
  final DeleteFolder _deleteFolder;
  final TextRepository? _text;
  String _textQuery = '';

  /// Finds documents whose recognised text contains [query]; the result joins the normal search.
  Future<void> searchInText(String query) async {
    final q = query.trim();
    _textQuery = q;
    final repo = _text;
    if (repo == null || q.length < 2) {
      if (state.textMatches.isNotEmpty) emit(state.copyWith(textMatches: const {}));
      return;
    }
    final found = (await repo.searchText(q)).valueOrNull ?? const <String>{};
    // A newer search started while this one ran.
    if (isClosed || _textQuery != q) return;
    emit(state.copyWith(textMatches: found));
  }

  Future<void> load() async {
    final docs = await _list();
    final folders = await _listFolders();
    // The screen may have closed while the library was loading.
    if (isClosed) return;
    final failure = docs.failureOrNull ?? folders.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(status: LoadStatus.failed, failure: failure));
      return;
    }
    emit(state.copyWith(status: LoadStatus.ready, documents: docs.valueOrNull, folders: folders.valueOrNull));
  }

  // Multi-select

  void toggleSelect(String id) {
    final next = [...state.selection];
    next.contains(id) ? next.remove(id) : next.add(id);
    emit(state.copyWith(selection: next));
  }

  void clearSelection() => emit(state.copyWith(selection: const []));

  /// Merges the selected documents in pick order. Returns the new document id, or the failure.
  Future<({String? id, Failure? failure})> mergeSelected({required String title, required bool deleteOriginals}) async {
    final ids = [...state.selection];
    final first = state.documents.where((d) => d.id == ids.first);
    final result = await _merge(ids: ids, title: title, folderId: first.isEmpty ? null : first.first.folderId, deleteOriginals: deleteOriginals);
    final failure = result.failureOrNull;
    if (failure != null) return (id: null, failure: failure);
    emit(state.copyWith(selection: const []));
    await load();
    return (id: result.valueOrNull?.id, failure: null);
  }

  Future<Failure?> deleteSelected() async {
    Failure? failure;
    for (final id in [...state.selection]) {
      failure = (await _delete(id)).failureOrNull ?? failure;
    }
    emit(state.copyWith(selection: const []));
    await load();
    return failure;
  }

  Future<Failure?> moveSelected(String? folderId) async {
    Failure? failure;
    for (final id in [...state.selection]) {
      failure = (await _move(id, folderId)).failureOrNull ?? failure;
    }
    emit(state.copyWith(selection: const []));
    await load();
    return failure;
  }

  void setSort(DocumentSort sort) => emit(state.copyWith(sort: sort));

  void toggleView() => emit(state.copyWith(gridView: !state.gridView));

  Future<Failure?> _reload(Result<Object?> result) async {
    final failure = result.failureOrNull;
    if (failure == null) await load();
    return failure;
  }

  Future<Failure?> deleteDocument(String id) async => _reload(await _delete(id));

  Future<Failure?> renameDocument(String id, String title) async => _reload(await _rename(id, title));

  Future<Failure?> moveDocument(String id, String? folderId) async => _reload(await _move(id, folderId));

  Future<Failure?> createFolder(String name, {FolderStyle style = const FolderStyle()}) async => _reload(await _createFolder(name, style: style));

  Future<Failure?> renameFolder(String id, String name) async => _reload(await _renameFolder(id, name));

  /// Changes a folder's name and look together.
  Future<Failure?> editFolder(String id, {required String name, required FolderStyle style}) async {
    final renamed = await _renameFolder(id, name);
    final failure = renamed.failureOrNull;
    if (failure != null) return _reload(renamed);
    return _reload(await _updateFolderMeta(id, style: style));
  }

  Future<Failure?> setFolderFlags(String id, {bool? favorite, bool? locked}) async => _reload(await _updateFolderMeta(id, favorite: favorite, locked: locked));

  Future<Failure?> deleteFolder(String id) async => _reload(await _deleteFolder(id));
}

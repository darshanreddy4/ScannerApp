import 'package:doculoom/app/di.dart';
import 'package:doculoom/core/error/failures.dart';
import 'package:doculoom/core/error/result.dart';
import 'package:doculoom/features/documents/domain/entities/scanned_document.dart';
import 'package:doculoom/features/documents/domain/repositories/document_repository.dart';
import 'package:doculoom/features/documents/domain/usecases/document_usecases.dart';

/// Folders kept in memory, so a scan can be filed into one.
class FakeFolders implements FolderRepository {
  final folders = <Folder>[];
  final created = <({String name, FolderStyle style})>[];
  var failList = false;
  var failCreate = false;

  @override
  Future<Result<List<Folder>>> listFolders() async => failList ? const Err(StorageFailure('The folder could not be changed.')) : Ok([...folders]);

  @override
  Future<Result<Folder>> createFolder(String name, {FolderStyle style = const FolderStyle()}) async {
    if (failCreate) return const Err(StorageFailure('The folder could not be changed.'));
    final folder = Folder(id: 'f${folders.length + 1}', name: name, createdAt: DateTime(2026), icon: style.icon, color: style.color);
    folders.add(folder);
    created.add((name: name, style: style));
    return Ok(folder);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

class FakeMover implements DocumentRepository {
  final moves = <({String id, String? folderId})>[];
  var fail = false;

  @override
  Future<Result<void>> moveDocument(String id, String? folderId) async {
    if (fail) return const Err(StorageFailure('The folder could not be changed.'));
    moves.add((id: id, folderId: folderId));
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(invocation.memberName.toString());
}

/// Registers the folder use cases the way the app does, on top of in-memory fakes.
({FakeFolders folders, FakeMover mover}) registerFolderFakes() {
  final folders = FakeFolders();
  final mover = FakeMover();
  sl
    ..registerSingleton(ListFolders(folders))
    ..registerSingleton(CreateFolder(folders))
    ..registerSingleton(MoveDocument(mover));
  return (folders: folders, mover: mover);
}

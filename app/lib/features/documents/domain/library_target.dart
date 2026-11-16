/// A file kept in the library, handed to the screen that edits it so saving puts the new version back in place.
class LibraryTarget {
  const LibraryTarget({required this.path, required this.id});

  /// Where the file is stored.
  final String path;

  /// The library document that owns the file.
  final String id;
}

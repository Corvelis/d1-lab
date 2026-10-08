import 'dart:io';

/// Only files in the app's media folders are eligible for cleanup.
class MediaStorage {
  const MediaStorage(this.directory);
  final Directory directory;

  static String normalize(String path) =>
      File(path).absolute.uri.normalizePath().toFilePath();

  Stream<File> _files() async* {
    for (final name in ['media', 'recordings']) {
      final folder = Directory('${directory.path}/$name');
      if (await FileSystemEntity.type(folder.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      await for (final entry in folder.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) yield entry;
      }
    }
  }

  Future<({int bytes, int files})> usage() async {
    var bytes = 0, count = 0;
    await for (final file in _files()) {
      bytes += await file.length();
      count++;
    }
    return (bytes: bytes, files: count);
  }

  Future<void> removeUnused(Set<String> references) async {
    final keep = references.map(normalize).toSet();
    await for (final file in _files()) {
      if (!keep.contains(normalize(file.path))) await file.delete();
    }
  }
}

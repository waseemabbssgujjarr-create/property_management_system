/// Web stub for dart:io.File.
/// All actual File usage in the codebase is guarded by `if (kIsWeb) return;`.
/// This class exists only to satisfy the Dart analyzer on web targets.
class File {
  const File(String path);
  Future<bool> exists() async => false;
  Future<int> length() async => 0;
}

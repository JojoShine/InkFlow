import 'dart:io';
import 'package:path/path.dart' as p;

class LocalFileStore {
  LocalFileStore(this.root);
  final Directory root;

  File file(String relativePath) {
    final path = p.normalize(p.join(root.absolute.path, relativePath));
    if (p.isAbsolute(relativePath) || !p.isWithin(root.absolute.path, path)) {
      throw const FormatException('作品路径不合法');
    }
    return File(path);
  }

  Future<void> replace(String temporary, String destination) async {
    for (var attempt = 0; ; attempt++) {
      try {
        // Use the same path canonicalization for replacement as dart:io writes.
        // On Windows this also supplies extended-length paths to MoveFileExW.
        await File(temporary).rename(destination);
        return;
      } on FileSystemException catch (error) {
        if (!Platform.isWindows) rethrow;
        final code = error.osError?.errorCode;
        if ((code == 5 || code == 32 || code == 33) && attempt < 4) {
          await Future<void>.delayed(
            Duration(milliseconds: 50 * (attempt + 1)),
          );
          continue;
        }
        throw FileSystemException(
          '无法安全替换作品文件（Windows 错误 $code）',
          destination,
          error.osError,
        );
      }
    }
  }
}

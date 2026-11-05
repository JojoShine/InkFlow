import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
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
    if (!Platform.isWindows) {
      await File(temporary).rename(destination);
      return;
    }
    final library = DynamicLibrary.open('kernel32.dll');
    final move = library
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Utf16>, int)
        >('MoveFileExW');
    final lastError = library.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
    final source = temporary.toNativeUtf16();
    final target = destination.toNativeUtf16();
    try {
      for (var attempt = 0; ; attempt++) {
        // Same-directory rename avoids ReplaceFileW's metadata-merge requirements.
        // Never delete the original before the replacement succeeds.
        if (move(source, target, 0x1 | 0x8) != 0) return;
        final code = lastError();
        // MoveFileExW can report access denied as well as sharing/lock violations
        // while scanners or sync clients briefly hold a file without delete sharing.
        if ((code == 5 || code == 32 || code == 33) && attempt < 4) {
          await Future<void>.delayed(
            Duration(milliseconds: 50 * (attempt + 1)),
          );
          continue;
        }
        throw FileSystemException(
          '无法安全替换作品文件（Windows 错误 $code）',
          destination,
          OSError('Windows file replacement failed', code),
        );
      }
    } finally {
      calloc.free(source);
      calloc.free(target);
    }
  }
}

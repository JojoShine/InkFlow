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
    final source = temporary.toNativeUtf16();
    final target = destination.toNativeUtf16();
    try {
      final int success;
      if (await File(destination).exists()) {
        final replace = library
            .lookupFunction<
              Int32 Function(
                Pointer<Utf16>,
                Pointer<Utf16>,
                Pointer<Utf16>,
                Uint32,
                Pointer<Void>,
                Pointer<Void>,
              ),
              int Function(
                Pointer<Utf16>,
                Pointer<Utf16>,
                Pointer<Utf16>,
                int,
                Pointer<Void>,
                Pointer<Void>,
              )
            >('ReplaceFileW');
        success = replace(target, source, nullptr, 0, nullptr, nullptr);
      } else {
        final move = library
            .lookupFunction<
              Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32),
              int Function(Pointer<Utf16>, Pointer<Utf16>, int)
            >('MoveFileExW');
        success = move(source, target, 8);
      }
      if (success == 0) {
        final code = library.lookupFunction<Uint32 Function(), int Function()>(
          'GetLastError',
        )();
        throw FileSystemException(
          '无法安全替换作品文件',
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

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/local_file_store.dart';
import 'package:inkflow/core/storage/record_store.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-replace-');
  });
  tearDown(() async => root.delete(recursive: true));

  test('replacement waits for a transient Windows sharing lock', () async {
    final original = File('${root.path}/正文.txt');
    final temporary = File('${root.path}/正文.tmp');
    await original.writeAsString('原稿', flush: true);
    await temporary.writeAsString('中文新稿', flush: true);
    final kernel = DynamicLibrary.open('kernel32.dll');
    final create = kernel
        .lookupFunction<
          Pointer<Void> Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            Pointer<Void>,
            Uint32,
            Uint32,
            Pointer<Void>,
          ),
          Pointer<Void> Function(
            Pointer<Utf16>,
            int,
            int,
            Pointer<Void>,
            int,
            int,
            Pointer<Void>,
          )
        >('CreateFileW');
    final close = kernel
        .lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CloseHandle');
    final path = original.path.toNativeUtf16();
    // Permit readers, but deny delete sharing as sync/scanning tools can do.
    final handle = create(path, 0x80000000, 1, nullptr, 3, 0x80, nullptr);
    calloc.free(path);
    expect(handle.address, isNot(-1));
    expect(handle.address, isNot(0xffffffffffffffff));
    var closed = false;
    try {
      final replacement = LocalFileStore(
        root,
      ).replace(temporary.path, original.path);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(await original.readAsString(), '原稿');
      expect(close(handle), isNot(0));
      closed = true;
      await replacement;
      expect(await original.readAsString(), '中文新稿');
      expect(await temporary.exists(), isFalse);
    } finally {
      if (!closed) close(handle);
    }
  }, skip: !Platform.isWindows);

  test('missing replacement leaves the original intact', () async {
    final original = File('${root.path}/正文.txt');
    await original.writeAsString('原稿');
    await expectLater(
      LocalFileStore(root).replace('${root.path}/missing.tmp', original.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.readAsString(), '原稿');
  });

  test(
    'replacement handles both new files and existing Unicode paths',
    () async {
      final store = LocalFileStore(root);
      final target = File('${root.path}/正文.txt');
      for (final text in ['第一稿', '修改后的中文稿']) {
        final temporary = File('${root.path}/正文.tmp');
        await temporary.writeAsString(text, flush: true);
        await store.replace(temporary.path, target.path);
        expect(await target.readAsString(), text);
        expect(await temporary.exists(), isFalse);
      }
    },
  );
  test(
    'saving a readable chapter works when its temporary path exceeds MAX_PATH',
    () async {
      var library = root;
      while (library.path.length < 190) {
        library = Directory('${library.path}/长路径创作资料');
      }
      await library.create(recursive: true);
      final files = LocalFileStore(library);
      final chapter = 'chapters/${List.filled(32, 'a').join()}.txt';
      final original = files.file(chapter);
      expect(original.path.length, lessThan(260));
      expect(original.path.length + 37, greaterThan(260));
      await original.parent.create(recursive: true);
      await original.writeAsString('原稿', flush: true);
      final store = RecordStore(files);
      final before = (await store.read(chapter))!;
      final result = await store.write(
        chapter,
        utf8.encode('新稿'),
        expected: before.version,
      );
      expect(result.state, SaveState.saved, reason: result.message);
      expect(await original.readAsString(), '新稿');
      expect(
        await original.parent
            .list()
            .where((file) => file.path.endsWith('.tmp'))
            .toList(),
        isEmpty,
      );
    },
  );
  test(
    'Windows replacement accepts extended paths with mixed separators',
    () async {
      final directory = Directory('${root.path}/中文作品');
      await directory.create();
      final base = r'\\?\' + root.absolute.path.replaceAll('/', r'\');
      final original = File('$base/中文作品/正文.txt');
      final temporary = File('$base/中文作品/正文.tmp');
      await original.writeAsString('原稿', flush: true);
      await temporary.writeAsString('新稿', flush: true);
      await LocalFileStore(root).replace(temporary.path, original.path);
      expect(await original.readAsString(), '新稿');
    },
    skip: !Platform.isWindows,
  );
}

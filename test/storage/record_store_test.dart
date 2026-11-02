import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/record_store.dart';
import 'package:inkflow/core/storage/local_file_store.dart';

class FailingReplaceStore extends LocalFileStore {
  FailingReplaceStore(super.root);
  @override
  Future<void> replace(String temporary, String destination) async {
    throw const FileSystemException('disk full');
  }
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('inkflow-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('external changes keep both contents instead of overwriting', () async {
    final store = RecordStore(LocalFileStore(dir));
    final saved = await store.write(
      'chapter.txt',
      utf8.encode('原稿'),
      expected: null,
    );
    expect(saved.state, SaveState.saved);
    final base = (await store.read('chapter.txt'))!.version;
    await File('${dir.path}/chapter.txt').writeAsString('另一台电脑');
    final result = await store.write(
      'chapter.txt',
      utf8.encode('本机新稿'),
      expected: base,
    );
    expect(result.state, SaveState.conflict);
    expect(await File('${dir.path}/chapter.txt').readAsString(), '另一台电脑');
    final files = await Directory('${dir.path}/.inkflow/conflicts')
        .list(recursive: true)
        .where((f) => f is File && f.path.endsWith('.bin'))
        .toList();
    final contents = await Future.wait(
      files.map((f) => (f as File).readAsString()),
    );
    expect(contents, containsAll(['本机新稿', '另一台电脑']));
  });

  test('replacement failure keeps the valid original', () async {
    await File('${dir.path}/chapter.txt').writeAsString('原稿');
    final normal = RecordStore(LocalFileStore(dir));
    final base = (await normal.read('chapter.txt'))!.version;
    final failing = RecordStore(FailingReplaceStore(dir));
    final result = await failing.write(
      'chapter.txt',
      utf8.encode('新稿'),
      expected: base,
    );
    expect(result.state, SaveState.failed);
    expect(await File('${dir.path}/chapter.txt').readAsString(), '原稿');
  });

  test('same bytes at a different timestamp do not cause a conflict', () async {
    final store = RecordStore(LocalFileStore(dir));
    await store.write('chapter.txt', utf8.encode('原稿'), expected: null);
    final base = (await store.read('chapter.txt'))!.version;
    await File('${dir.path}/chapter.txt').setLastModified(DateTime(2000));
    final result = await store.write(
      'chapter.txt',
      utf8.encode('新稿'),
      expected: base,
    );
    expect(result.state, SaveState.saved);
    expect(await File('${dir.path}/chapter.txt').readAsString(), '新稿');
  });

  test('deletion checks the expected version before removing a file', () async {
    final store = RecordStore(LocalFileStore(dir));
    await store.write('chapter.txt', utf8.encode('原稿'), expected: null);
    final base = (await store.read('chapter.txt'))!.version;
    await File('${dir.path}/chapter.txt').writeAsString('外部新稿');
    expect(
      (await store.delete('chapter.txt', expected: base)).state,
      SaveState.conflict,
    );
    expect(await File('${dir.path}/chapter.txt').readAsString(), '外部新稿');
  });
}

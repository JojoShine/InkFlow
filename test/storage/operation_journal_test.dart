import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/local_file_store.dart';
import 'package:inkflow/core/storage/record_store.dart';
import 'package:inkflow/core/storage/operation_journal.dart';

class InterruptedStore extends LocalFileStore {
  InterruptedStore(super.root);
  @override
  Future<void> replace(String temporary, String destination) async {
    if (destination.endsWith('/second.txt')) {
      throw const FileSystemException('simulated interruption');
    }
    await super.replace(temporary, destination);
  }
}

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('inkflow-journal-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'interrupted multi-file operation resumes without losing original bytes',
    () async {
      final first = File('${dir.path}/first.txt');
      final second = File('${dir.path}/second.txt');
      await first.writeAsString('原稿一');
      await second.writeAsString('原稿二');
      final store = RecordStore(InterruptedStore(dir));
      final versions = {
        'first.txt': (await store.read('first.txt'))!.version,
        'second.txt': (await store.read('second.txt'))!.version,
      };
      await expectLater(
        OperationJournal(store).apply({
          'first.txt': utf8.encode('新稿一'),
          'second.txt': utf8.encode('新稿二'),
        }, expected: versions),
        throwsA(isA<SaveException>()),
      );
      final reopened = RecordStore(LocalFileStore(dir));
      expect(await OperationJournal(reopened).recover(), isEmpty);
      expect(await first.readAsString(), '新稿一');
      expect(await second.readAsString(), '新稿二');
    },
  );
  test('journal recovery refuses to replace newer external content', () async {
    final store = RecordStore(InterruptedStore(dir));
    await File('${dir.path}/first.txt').writeAsString('原稿一');
    await File('${dir.path}/second.txt').writeAsString('原稿二');
    await expectLater(
      OperationJournal(store).apply(
        {'first.txt': utf8.encode('新稿一'), 'second.txt': utf8.encode('新稿二')},
        expected: {
          'first.txt': (await store.read('first.txt'))!.version,
          'second.txt': (await store.read('second.txt'))!.version,
        },
      ),
      throwsA(isA<SaveException>()),
    );
    await File('${dir.path}/second.txt').writeAsString('外部新稿');
    final issues = await OperationJournal(
      RecordStore(LocalFileStore(dir)),
    ).recover();
    expect(issues, isNotEmpty);
    expect(await File('${dir.path}/second.txt').readAsString(), '外部新稿');
  });
}

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/history_store.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('inkflow-history-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
    'retains the latest 100 distinct snapshots without touching conflicts',
    () async {
      final history = HistoryStore(dir);
      final conflict = File('${dir.path}/.inkflow/conflicts/keep.txt');
      await conflict.parent.create(recursive: true);
      await conflict.writeAsString('冲突稿');
      for (var i = 0; i <= 100; i++) {
        await history.capture(
          'work',
          'chapter',
          utf8.encode('第$i版'),
          DateTime.utc(2026, 11, 2).add(Duration(minutes: i)),
        );
      }
      final entries = await history.list('work', 'chapter');
      expect(entries.length, 100);
      expect(utf8.decode(await history.read(entries.first)), '第1版');
      expect(utf8.decode(await history.read(entries.last)), '第100版');
      expect(await conflict.readAsString(), '冲突稿');
      await history.capture(
        'work',
        'chapter',
        utf8.encode('第100版'),
        DateTime.utc(2026, 11, 3),
      );
      expect((await history.list('work', 'chapter')).length, 100);
    },
  );
}

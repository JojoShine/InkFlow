import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/core/storage/history_store.dart';

void main() {
  test(
    'concurrent identical captures create exactly one recoverable snapshot',
    () async {
      final root = await Directory.systemTemp.createTemp('history-queue');
      final h = HistoryStore(root);
      await Future.wait(
        List.generate(
          8,
          (_) =>
              h.capture('work', 'chapter', utf8.encode('唯一版本'), DateTime.now()),
        ),
      );
      final entries = await h.list('work', 'chapter');
      expect(entries, hasLength(1));
      expect(utf8.decode(await h.read(entries.single)), '唯一版本');
      await root.delete(recursive: true);
    },
  );
  test('capture owns immutable bytes across asynchronous writes', () async {
    final root = await Directory.systemTemp.createTemp('history-bytes');
    final h = HistoryStore(root);
    final bytes = utf8.encode('original');
    final pending = h.capture('work', 'chapter', bytes, DateTime.now());
    bytes[0] = 0;
    await pending;
    final entries = await h.list('work', 'chapter');
    expect(utf8.decode(await h.read(entries.single)), 'original');
    await root.delete(recursive: true);
  });
}

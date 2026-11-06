import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../features/works/work_models.dart';
import 'local_file_store.dart';
import 'record_store.dart';
import 'operation_journal.dart';

class HistoryEntry {
  const HistoryEntry(this.path, this.createdAt, this.hash);
  final String path;
  final DateTime createdAt;
  final String hash;
}

class HistoryStore {
  HistoryStore(this.root);
  final Directory root;
  final _queues = <String, Future<void>>{};
  final _latest = <String, String>{};
  Future<void> drain() => Future.wait(_queues.values.toList());
  void invalidate(String workKey, String recordId) {
    _latest.remove('$workKey/$recordId');
  }

  Future<void> capture(
    String workKey,
    String recordId,
    List<int> bytes,
    DateTime now,
  ) {
    final key = '$workKey/$recordId';
    final snapshot = List<int>.of(bytes);
    final task = (_queues[key] ?? Future<void>.value()).then((_) async {
      try {
        await _capture(workKey, recordId, snapshot, now);
      } catch (_) {
        _latest.remove(key);
        rethrow;
      }
    });
    _queues[key] = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  Future<void> _capture(
    String workKey,
    String recordId,
    List<int> bytes,
    DateTime now,
  ) async {
    final key = '$workKey/$recordId';
    final hash = RecordVersion.of(bytes).hash;
    if (_latest[key] == hash) return;
    await root.create(recursive: true);
    final entries = await _listDisk(workKey, recordId);
    if (entries.isNotEmpty && entries.last.hash == hash) {
      _latest[key] = hash;
      return;
    }
    final path =
        'history/$workKey/$recordId/${now.microsecondsSinceEpoch}-${newId()}.json';
    final result = await RecordStore(LocalFileStore(root)).write(
      path,
      utf8.encode(
        jsonEncode({
          'createdAt': now.toUtc().toIso8601String(),
          'hash': hash,
          'content': base64Encode(bytes),
        }),
      ),
      expected: null,
    );
    if (!result.isSaved) throw SaveException(result);
    final all = [
      ...entries,
      HistoryEntry(LocalFileStore(root).file(path).path, now.toUtc(), hash),
    ];
    for (final old in all.take(all.length > 100 ? all.length - 100 : 0)) {
      await File(old.path).delete();
    }
    _latest[key] = hash;
  }

  Future<List<HistoryEntry>> list(String workKey, String recordId) async {
    await (_queues['$workKey/$recordId'] ?? Future<void>.value());
    invalidate(workKey, recordId);
    return _listDisk(workKey, recordId);
  }

  Future<List<HistoryEntry>> _listDisk(String workKey, String recordId) async {
    final files = LocalFileStore(root);
    final directory = files
        .file('history/$workKey/$recordId/record.json')
        .parent;
    if (!await directory.exists()) return [];
    final entries = <HistoryEntry>[];
    await for (final file in directory.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      final json = jsonDecode(await file.readAsString()) as Map;
      entries.add(
        HistoryEntry(
          file.path,
          DateTime.parse(json['createdAt'] as String),
          json['hash'] as String,
        ),
      );
    }
    entries.sort((a, b) {
      final compared = a.createdAt.compareTo(b.createdAt);
      return compared == 0 ? a.path.compareTo(b.path) : compared;
    });
    return entries;
  }

  Future<List<int>> read(HistoryEntry entry) async {
    final json = jsonDecode(await File(entry.path).readAsString()) as Map;
    final bytes = base64Decode(json['content'] as String);
    if (RecordVersion.of(bytes).hash != entry.hash) {
      throw const FormatException('历史内容校验失败，原文件已保留');
    }
    return bytes;
  }
}

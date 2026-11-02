import 'dart:convert';
import 'dart:io';
import '../../features/works/work_models.dart';
import 'record_store.dart';

class SaveException implements Exception {
  const SaveException(this.outcome);
  final SaveOutcome outcome;
  @override
  String toString() => outcome.message ?? '保存失败';
}

class OperationJournal {
  OperationJournal(this.store);
  final RecordStore store;
  Future<void> apply(
    Map<String, List<int>?> changes, {
    required Map<String, RecordVersion?> expected,
  }) async {
    final id = newId();
    final path = '.inkflow/operations/$id.pending.json';
    final records = <Map<String, Object?>>[];
    for (final entry in changes.entries) {
      store.files.file(entry.key);
      final before = await store.read(entry.key);
      records.add({
        'path': entry.key,
        'beforeHash': expected[entry.key]?.hash,
        'before': before == null ? null : base64Encode(before.bytes),
        'after': entry.value == null ? null : base64Encode(entry.value!),
      });
    }
    final log = await store.write(
      path,
      utf8.encode(jsonEncode({'version': 1, 'id': id, 'records': records})),
      expected: null,
    );
    if (!log.isSaved) throw SaveException(log);
    await _replay(records);
    await store.files.file(path).delete();
  }

  Future<void> _replay(List<dynamic> records) async {
    for (final value in records) {
      if (value is! Map ||
          value['path'] is! String ||
          (value['beforeHash'] != null && value['beforeHash'] is! String) ||
          (value['after'] != null && value['after'] is! String)) {
        throw const FormatException('操作恢复记录损坏');
      }
      final path = value['path'] as String;
      store.files.file(path);
      final bytes = value['after'] == null
          ? null
          : base64Decode(value['after']);
      final after = bytes == null ? null : RecordVersion.of(bytes);
      final current = await store.read(path);
      if (current?.version == after) continue;
      final hash = value['beforeHash'] as String?;
      final expected = hash == null ? null : RecordVersion(hash);
      final result = bytes == null
          ? await store.delete(path, expected: expected)
          : await store.write(path, bytes, expected: expected);
      if (!result.isSaved) throw SaveException(result);
    }
  }

  Future<List<String>> recover() async {
    final directory = store.files.file('.inkflow/operations/dummy').parent;
    if (!await directory.exists()) return [];
    final issues = <String>[];
    final logs = await directory
        .list()
        .where((file) => file is File && file.path.endsWith('.pending.json'))
        .cast<File>()
        .toList();
    logs.sort((a, b) => a.path.compareTo(b.path));
    for (final file in logs) {
      try {
        final log = jsonDecode(await file.readAsString());
        if (log is! Map || log['version'] != 1 || log['records'] is! List) {
          throw const FormatException('操作恢复记录损坏');
        }
        await _replay(log['records']);
        await file.delete();
      } on SaveException catch (error) {
        issues.add(error.toString());
        if (error.outcome.state == SaveState.conflict) {
          await file.rename(
            file.path.replaceFirst('.pending.json', '.blocked.json'),
          );
        }
      } on FormatException catch (error) {
        issues.add(error.message);
      } on FileSystemException catch (error) {
        issues.add(error.message);
      }
    }
    return issues;
  }
}

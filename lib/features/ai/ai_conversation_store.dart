import 'dart:convert';
import 'dart:io';
import '../../core/storage/local_file_store.dart';
import '../../core/storage/record_store.dart';
import '../../core/storage/operation_journal.dart';

class AiConversationStore {
  AiConversationStore(this.root);
  final Directory root;
  Future<void> _pending = Future.value();
  String _path(String workKey) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(workKey)) {
      throw const FormatException('作品标识不合法');
    }
    return 'ai/conversations/$workKey.json';
  }

  Future<Map<String, dynamic>?> load(String workKey) async {
    await _pending;
    final file = File('${root.path}/${_path(workKey)}');
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (value['schemaVersion'] != 1 || value['turns'] is! List) {
      throw const FormatException('本机对话格式不可用，原文件已保留');
    }
    for (final turn in value['turns'] as List) {
      if (turn['state'] == 'receiving' || turn['state'] == 'pending') {
        turn['state'] = 'interrupted';
      }
    }
    return value;
  }

  Future<void> save(String workKey, Map<String, dynamic> conversation) {
    final path = _path(workKey), bytes = utf8.encode(jsonEncode(conversation));
    final task = _pending.then((_) async {
      await root.create(recursive: true);
      final store = RecordStore(LocalFileStore(root));
      final old = await store.read(path);
      final result = await store.write(path, bytes, expected: old?.version);
      if (!result.isSaved) throw SaveException(result);
    });
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<void> flush() => _pending;
}

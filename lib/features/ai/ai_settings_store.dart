import 'dart:convert';
import 'dart:io';
import '../../core/storage/local_file_store.dart';
import '../../core/storage/record_store.dart';
import '../../core/storage/operation_journal.dart';
import 'ai_settings.dart';

class AiSettingsStore {
  AiSettingsStore(this.root);
  final Directory root;
  Future<void> _pending = Future.value();
  Future<(AiProvider?, Map<AiProvider, AiSettings>)> load() async {
    final file = File('${root.path}/ai-settings.json');
    if (!await file.exists()) return (null, <AiProvider, AiSettings>{});
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('AI 设置格式不可用，原文件已保留');
    }
    return (
      json['active'] == null
          ? null
          : AiProvider.values.byName(json['active'] as String),
      {
        for (final item in json['connections'] as List)
          AiSettings.fromJson(Map<String, dynamic>.from(item as Map)).provider:
              AiSettings.fromJson(Map<String, dynamic>.from(item)),
      },
    );
  }

  Future<void> save(AiProvider active, Map<AiProvider, AiSettings> settings) {
    final bytes = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'active': active.name,
        'connections': settings.values.map((s) => s.toJson()).toList(),
      }),
    );
    final task = _pending.then((_) async {
      await root.create(recursive: true);
      final store = RecordStore(LocalFileStore(root));
      final previous = await store.read('ai-settings.json');
      final result = await store.write(
        'ai-settings.json',
        bytes,
        expected: previous?.version,
      );
      if (!result.isSaved) throw SaveException(result);
    });
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }
}

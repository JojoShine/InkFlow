import 'dart:convert';
import 'dart:io';
import '../../core/storage/local_file_store.dart';
import '../../core/storage/record_store.dart';
import '../../core/storage/operation_journal.dart';
import 'device_preferences.dart';

class PreferencesStore {
  PreferencesStore(this.root);
  final Directory root;
  String? warning;
  Future<void> _pending = Future<void>.value();

  Future<DevicePreferences> load() async {
    await root.create(recursive: true);
    final file = File('${root.path}/device-preferences.json');
    if (!await file.exists()) return const DevicePreferences();
    final source = await file.readAsString();
    try {
      return DevicePreferences.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
    } on FormatException {
      await _preserve(file);
    } on TypeError {
      await _preserve(file);
    }
    return const DevicePreferences();
  }

  Future<void> _preserve(File source) async {
    await source.copy(
      '${root.path}/device-preferences.corrupt-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    warning = '设备设置读取失败，原文件已保留，已使用默认外观';
  }

  Future<void> save(DevicePreferences preferences) {
    final bytes = utf8.encode(jsonEncode(preferences.toJson()));
    final task = _pending.then((_) async {
      await root.create(recursive: true);
      final store = RecordStore(LocalFileStore(root));
      final previous = await store.read('device-preferences.json');
      final result = await store.write(
        'device-preferences.json',
        bytes,
        expected: previous?.version,
      );
      if (!result.isSaved) throw SaveException(result);
    });
    _pending = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }
}

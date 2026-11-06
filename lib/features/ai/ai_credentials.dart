import 'package:flutter/services.dart';

abstract interface class AiCredentials {
  Future<bool> contains(String id);
  Future<String?> read(String id);
  Future<void> write(String id, String key);
  Future<void> delete(String id);
}

class PlatformAiCredentials implements AiCredentials {
  static const _channel = MethodChannel('inkflow/ai-credentials');
  final _keys = <String, String?>{};
  @override
  Future<bool> contains(String id) async => _keys.containsKey(id)
      ? (_keys[id]?.isNotEmpty ?? false)
      : await _channel.invokeMethod<bool>('contains', {'id': id}) ?? false;
  @override
  Future<String?> read(String id) async {
    if (_keys.containsKey(id)) return _keys[id];
    final key = await _channel.invokeMethod<String>('read', {'id': id});
    _keys[id] = key;
    return key;
  }

  @override
  Future<void> write(String id, String key) async {
    await _channel.invokeMethod<void>('write', {'id': id, 'key': key});
    _keys[id] = key;
  }

  @override
  Future<void> delete(String id) async {
    await _channel.invokeMethod<void>('delete', {'id': id});
    _keys[id] = null;
  }
}

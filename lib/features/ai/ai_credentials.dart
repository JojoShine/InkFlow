import 'package:flutter/services.dart';

abstract interface class AiCredentials {
  Future<String?> read(String id);
  Future<void> write(String id, String key);
  Future<void> delete(String id);
}

class PlatformAiCredentials implements AiCredentials {
  static const _channel = MethodChannel('inkflow/ai-credentials');
  @override
  Future<String?> read(String id) =>
      _channel.invokeMethod<String>('read', {'id': id});
  @override
  Future<void> write(String id, String key) =>
      _channel.invokeMethod<void>('write', {'id': id, 'key': key});
  @override
  Future<void> delete(String id) =>
      _channel.invokeMethod<void>('delete', {'id': id});
}

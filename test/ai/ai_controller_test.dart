import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_controller.dart';
import 'package:inkflow/features/ai/ai_client.dart';
import 'package:inkflow/features/ai/ai_credentials.dart';
import 'package:inkflow/features/ai/ai_settings.dart';

class MemoryKeys implements AiCredentials {
  final keys = <String, String>{};
  @override
  Future<bool> contains(String id) async => keys[id]?.isNotEmpty ?? false;
  @override
  Future<String?> read(String id) async => keys[id];
  @override
  Future<void> write(String id, String key) async {
    keys[id] = key;
  }

  @override
  Future<void> delete(String id) async {
    keys.remove(id);
  }
}

class FakeAiClient extends AiClient {
  int cancellations = 0;
  final streams = <StreamController<AiEvent>>[];
  final payloads = <List<AiChatMessage>>[];
  @override
  AiRequest start(
    AiSettings settings,
    String key,
    List<AiChatMessage> messages,
  ) {
    final c = StreamController<AiEvent>();
    streams.add(c);
    payloads.add(messages);
    return AiRequest(c.stream, () async {
      cancellations++;
    });
  }
}

void main() {
  test(
    'late tokens cannot cross work switch and completed history stays scoped',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-control');
      final client = FakeAiClient();
      final ai = AiController(root, credentials: MemoryKeys(), client: client);
      await ai.initialize();
      await ai.configure(
        const AiSettings(
          provider: AiProvider.deepseek,
          baseUrl: 'https://api.deepseek.com',
          model: 'test',
        ),
        key: 'sentinel',
      );
      await ai.activateWork('a' * 64);
      await ai.send('人物为何离开');
      client.streams.single.add(const AiTextDelta('部分'));
      await Future<void>.delayed(Duration.zero);
      await ai.activateWork('b' * 64);
      client.streams.single.add(const AiTextDelta('旧作品'));
      await Future<void>.delayed(Duration.zero);
      expect(ai.turns, isEmpty);
      expect(ai.workKey, 'b' * 64);
      final config = await File('${root.path}/ai-settings.json').readAsString();
      expect(config, isNot(contains('sentinel')));
      ai.dispose();
      for (final s in client.streams) {
        await s.close();
      }
      await root.delete(recursive: true);
    },
  );
}

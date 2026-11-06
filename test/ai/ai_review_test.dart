import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_controller.dart';
import 'package:inkflow/features/ai/ai_conversation_store.dart';
import 'package:inkflow/features/ai/ai_context.dart';
import 'package:inkflow/features/ai/ai_client.dart';
import 'package:inkflow/features/ai/ai_settings.dart';
import 'ai_controller_test.dart' show MemoryKeys, FakeAiClient;

class DelayedStore extends AiConversationStore {
  DelayedStore(super.root);
  final gate = Completer<Map<String, dynamic>?>();
  final started = Completer<void>();
  int writes = 0;
  @override
  Future<Map<String, dynamic>?> load(String key) {
    started.complete();
    return gate.future;
  }

  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    writes++;
    return super.save(key, value);
  }
}

class LoadingAi extends AiController {
  LoadingAi(super.root, this.delayed)
    : super(credentials: MemoryKeys(), client: FakeAiClient());
  final DelayedStore delayed;
  @override
  AiConversationStore get conversationStore => delayed;
}

class GateKeys extends MemoryKeys {
  bool delayed = false;
  final gates = <Completer<String?>>[];
  @override
  Future<String?> read(String id) {
    if (!delayed) return super.read(id);
    final gate = Completer<String?>();
    gates.add(gate);
    return gate.future;
  }
}

class SwitchStore extends AiConversationStore {
  bool failWrites = false;
  @override
  Future<void> save(String key, Map<String, dynamic> value) async {
    if (failWrites) throw const FileSystemException('blocked');
    return super.save(key, value);
  }

  SwitchStore(super.root);
  String? hold;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<Map<String, dynamic>?> load(String key) async {
    if (key == hold) {
      started.complete();
      await release.future;
    }
    return super.load(key);
  }
}

class SwitchingAi extends AiController {
  SwitchingAi(super.root, this.storage)
    : super(credentials: MemoryKeys(), client: FakeAiClient());
  final SwitchStore storage;
  @override
  AiConversationStore get conversationStore => storage;
}

const config = AiSettings(
  provider: AiProvider.deepseek,
  baseUrl: 'https://api.deepseek.com',
  model: 'test',
);
void main() {
  test(
    'conversation load is not writable before existing history is installed',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-load');
      final ai = LoadingAi(root, DelayedStore(root));
      await ai.configure(config, key: 'sentinel');
      final loading = ai.activateWork('a' * 64);
      await ai.delayed.started.future;
      expect(ai.busy, isTrue);
      await ai.send('不应发送');
      await ai.stop();
      expect(ai.delayed.writes, 0);
      ai.delayed.gate.complete({
        'schemaVersion': 1,
        'turns': [
          {
            'id': 'old',
            'question': '原问题',
            'answer': '原回复',
            'state': 'completed',
          },
        ],
      });
      await loading;
      expect(ai.turns.single.answer, '原回复');
      ai.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'retry preserves explicit absence of attachment and retains failed partial reply if validation fails',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-retry');
      final client = FakeAiClient(), keys = MemoryKeys();
      final ai = AiController(root, credentials: keys, client: client);
      await ai.configure(config, key: 'sentinel');
      await ai.activateWork('a' * 64);
      await ai.send('原问题');
      client.streams.single.add(const AiTextDelta('已收到部分'));
      client.streams.single.add(const AiFailed('断流'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      ai.attachment = AiAttachment(
        source: AiContextSource.chapter,
        workKey: 'a' * 64,
        chapterId: 'b' * 32,
        chapterTitle: '新草稿附件',
        documentGeneration: 1,
        text: '尚未发送的私密正文',
      );
      ai.purpose = AiPurpose.summarize;
      await ai.retry();
      expect(client.payloads.last.first.content, contains('当前侧重：整理思路'));
      expect(client.payloads.last.last.content, isNot(contains('私密正文')));
      client.streams.last.add(const AiTextDelta('第二次部分'));
      client.streams.last.add(const AiFailed('断流'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      keys.keys.clear();
      await ai.retry();
      expect(ai.turns.last.answer, '第二次部分');
      ai.dispose();
      for (final stream in client.streams) {
        await stream.close();
      }
      await root.delete(recursive: true);
    },
  );
  test(
    'cancelled credential lookup cannot clear a newer send busy state',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-key-race');
      final keys = GateKeys(), client = FakeAiClient();
      final ai = AiController(root, credentials: keys, client: client);
      await ai.configure(config, key: 'sentinel');
      await ai.activateWork('a' * 64);
      keys.delayed = true;
      final first = ai.send('甲');
      await Future<void>.delayed(Duration.zero);
      await ai.stop();
      final second = ai.send('乙');
      await Future<void>.delayed(Duration.zero);
      keys.gates.first.complete('sentinel');
      await first;
      expect(ai.busy, isTrue);
      keys.gates.last.complete('sentinel');
      await second;
      await ai.stop();
      ai.dispose();
      for (final stream in client.streams) {
        await stream.close();
      }
      await root.delete(recursive: true);
    },
  );
  test('a stale attachment from another work cannot be sent', () async {
    final root = await Directory.systemTemp.createTemp('ai-foreign');
    final client = FakeAiClient();
    final ai = AiController(root, credentials: MemoryKeys(), client: client);
    await ai.configure(config, key: 'sentinel');
    await ai.activateWork('a' * 64);
    await ai.send(
      '整理',
      attachment: AiAttachment(
        source: AiContextSource.chapter,
        workKey: 'b' * 64,
        chapterId: 'c' * 32,
        chapterTitle: '另一作品',
        documentGeneration: 1,
        text: '另一作品的内容',
      ),
    );
    final count = client.payloads.length;
    ai.dispose();
    for (final stream in client.streams) {
      await stream.close();
    }
    await root.delete(recursive: true);
    expect(count, 0);
  });
  test(
    'cancelling conversation activation retains the previous work and history',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-activation');
      final ai = SwitchingAi(root, SwitchStore(root));
      await ai.activateWork('a' * 64);
      ai.turns.add(
        AiTurn(question: '甲问题')
          ..answer = '甲回复'
          ..state = 'completed',
      );
      ai.storage.hold = 'b' * 64;
      final loading = ai.activateWork('b' * 64);
      await ai.storage.started.future;
      expect(ai.workKey, 'a' * 64);
      ai.cancelActivation();
      ai.storage.release.complete();
      await loading;
      expect(ai.workKey, 'a' * 64);
      expect(ai.turns.single.answer, '甲回复');
      ai.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'explicitly discarding failed conversation save still cancels its network request',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-discard');
      final ai = SwitchingAi(root, SwitchStore(root));
      await ai.configure(config, key: 'sentinel');
      await ai.activateWork('a' * 64);
      await ai.send('问题');
      ai.storage.failWrites = true;
      await ai.retrySave();
      expect(ai.saveFailed, isTrue);
      ai.discardFailedSave();
      expect(await ai.prepareToQuit(), isTrue);
      final client = ai.client as FakeAiClient;
      expect(client.cancellations, 1);
      ai.dispose();
      for (final stream in client.streams) {
        await stream.close();
      }
      await root.delete(recursive: true);
    },
  );
}

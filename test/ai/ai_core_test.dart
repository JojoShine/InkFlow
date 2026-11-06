import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_settings.dart';
import 'package:inkflow/features/ai/ai_context.dart';
import 'package:inkflow/features/ai/ai_client.dart';
import 'package:inkflow/features/ai/ai_conversation_store.dart';

void main() {
  test(
    'provider address normalization preserves version path and rejects unsafe URLs',
    () {
      final settings = AiSettings(
        provider: AiProvider.glm,
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4/',
        model: 'glm-test',
      );
      expect(
        settings.completionUri.toString(),
        'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      );
      for (final url in [
        'http://example.com',
        'https://user:pass@example.com',
        'https://example.com?key=secret',
        'https://{workspace}.example.com',
      ]) {
        expect(
          () => AiSettings(
            provider: AiProvider.custom,
            baseUrl: url,
            model: 'test',
          ).validate(),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'context uses no manuscript by default and rejects over-budget history',
    () {
      final messages = buildAiMessages(
        purpose: AiPurpose.organize,
        completedHistory: [],
        question: '梳理动机',
      );
      expect(messages.last.content, '梳理动机');
      expect(
        () => buildAiMessages(
          purpose: AiPurpose.organize,
          completedHistory: [AiChatMessage('user', 'x' * 98304)],
          question: '还有呢',
        ),
        throwsFormatException,
      );
    },
  );
  test('SSE parses split UTF8, empty choices and done', () async {
    final bytes = utf8.encode(
      'data: {"choices":[{"delta":{"content":"线索🪶"}}]}\r\n\r\ndata: {"choices":[],"usage":{}}\n\ndata: [DONE]\n\n',
    );
    final events = await parseAiStream(
      Stream.fromIterable(bytes.map((b) => [b])),
    ).toList();
    expect(events.whereType<AiTextDelta>().map((e) => e.text).join(), '线索🪶');
    expect(events.last, isA<AiFinished>());
  });
  test(
    'conversation file preserves partial replies and never contains a key',
    () async {
      final root = await Directory.systemTemp.createTemp('ai-store');
      final store = AiConversationStore(root);
      final value = {
        'schemaVersion': 1,
        'turns': [
          {'question': '原因', 'answer': '部分回复', 'state': 'receiving'},
        ],
      };
      await store.save('a' * 64, value);
      await store.flush();
      final loaded = await store.load('a' * 64);
      expect((loaded!['turns'] as List).single['state'], 'interrupted');
      expect((loaded['turns'] as List).single['answer'], '部分回复');
      await root.delete(recursive: true);
    },
  );
}

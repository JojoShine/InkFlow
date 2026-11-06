import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/ai/ai_settings.dart';
import 'package:inkflow/features/ai/ai_client.dart';

class LoopbackClient implements HttpClient {
  LoopbackClient(this.uri);
  final Uri uri;
  final inner = HttpClient();
  @override
  Future<HttpClientRequest> postUrl(Uri ignored) => inner.postUrl(uri);
  @override
  set connectionTimeout(Duration? value) {
    inner.connectionTimeout = value;
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'transport sends scoped JSON, parses response and redacts error bodies',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map>[];
      var count = 0;
      server.listen((request) async {
        requests.add(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        );
        count++;
        if (count == 1) {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"content":"清楚"}}]}\n\ndata: [DONE]\n\n',
          );
        } else {
          request.response.statusCode = 401;
          request.response.write('secret-sentinel');
        }
        await request.response.close();
      });
      final client = AiClient(
        createHttpClient: () =>
            LoopbackClient(Uri.parse('http://127.0.0.1:${server.port}/chat')),
      );
      const settings = AiSettings(
        provider: AiProvider.deepseek,
        baseUrl: 'https://api.deepseek.com',
        model: 'test',
      );
      final first = await client
          .start(settings, 'secret-sentinel', [
            const AiChatMessage('user', '整理动机'),
          ])
          .events
          .toList();
      expect(first.whereType<AiTextDelta>().single.text, '清楚');
      expect(requests.first['messages'], [
        {'role': 'user', 'content': '整理动机'},
      ]);
      final second = await client
          .start(settings, 'secret-sentinel', [
            const AiChatMessage('user', '测试'),
          ])
          .events
          .toList();
      expect(
        second.whereType<AiFailed>().single.message,
        isNot(contains('secret-sentinel')),
      );
      expect(count, 2);
      await server.close(force: true);
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'ai_settings.dart';

sealed class AiEvent {
  const AiEvent();
}

class AiTextDelta extends AiEvent {
  const AiTextDelta(this.text);
  final String text;
}

class AiProcessing extends AiEvent {
  const AiProcessing();
}

class AiFinished extends AiEvent {
  const AiFinished(this.reason);
  final String reason;
}

class AiFailed extends AiEvent {
  const AiFailed(this.message);
  final String message;
}

Stream<AiEvent> parseAiStream(Stream<List<int>> bytes) async* {
  final data = <String>[];
  await for (final line
      in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.startsWith(':')) {
      yield const AiProcessing();
      continue;
    }
    if (line.startsWith('data:')) {
      data.add(line.substring(5).trimLeft());
      continue;
    }
    if (line.isNotEmpty || data.isEmpty) continue;
    final value = data.join('\n');
    data.clear();
    if (value.trim() == '[DONE]') {
      yield const AiFinished('stop');
      return;
    }
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw const FormatException('模型服务返回错误，请检查配置或稍后重试');
    }
    final choices = json['choices'] as List? ?? [];
    if (choices.isEmpty) {
      yield const AiProcessing();
      continue;
    }
    final choice = choices.first as Map;
    final delta = choice['delta'] as Map? ?? {};
    if (delta['tool_calls'] != null) {
      throw const FormatException('此模型要求工具调用，请使用文本对话模型');
    }
    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      yield AiTextDelta(content);
    } else {
      yield const AiProcessing();
    }
    final reason = choice['finish_reason'];
    if (reason is String) {
      yield AiFinished(reason);
      return;
    }
  }
  throw const FormatException('连接已中断，已收到的内容已保留');
}

class AiRequest {
  AiRequest(this.events, this._cancel);
  final Stream<AiEvent> events;
  final Future<void> Function() _cancel;
  Future<void> cancel() => _cancel();
}

class AiClient {
  AiClient({HttpClient Function()? createHttpClient})
    : _createHttpClient = createHttpClient ?? HttpClient.new;
  final HttpClient Function() _createHttpClient;
  AiRequest start(
    AiSettings settings,
    String key,
    List<AiChatMessage> messages,
  ) {
    settings.validate();
    if (key.trim().isEmpty) throw const FormatException('请先配置 API Key');
    final client = _createHttpClient()
      ..connectionTimeout = const Duration(seconds: 60);
    final events = StreamController<AiEvent>();
    bool cancelled = false;
    void emit(AiEvent event) {
      if (!cancelled && !events.isClosed) events.add(event);
    }

    final deadline = Timer(const Duration(minutes: 5), () {
      emit(const AiFailed('请求超时，请稍后重试'));
      cancelled = true;
      client.close(force: true);
      unawaited(events.close());
    });
    Future<void> run() async {
      try {
        final request = await client
            .postUrl(settings.completionUri)
            .timeout(const Duration(seconds: 60));
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
        final body = <String, Object>{
          'model': settings.model.trim(),
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': true,
          settings.provider == AiProvider.openai
                  ? 'max_completion_tokens'
                  : 'max_tokens':
              2048,
        };
        request.write(jsonEncode(body));
        final response = await request.close().timeout(
          const Duration(seconds: 60),
        );
        if (response.statusCode != 200) {
          final message = switch (response.statusCode) {
            401 || 403 => 'API Key 或模型权限不可用，请检查配置',
            404 => '服务地址或模型 ID 不存在',
            429 => '请求受限或额度不足，请检查服务商账户',
            400 || 413 => '请求未被接受，请检查模型参数或缩小附加内容',
            _ => '模型服务暂不可用，请稍后重试',
          };
          emit(AiFailed(message));
          return;
        }
        final stream = response.timeout(const Duration(seconds: 60));
        if (response.headers.contentType?.mimeType == 'application/json') {
          final value =
              jsonDecode(await utf8.decoder.bind(stream).join()) as Map;
          final choices = value['choices'] as List? ?? [];
          final message = choices.isEmpty
              ? null
              : choices.first['message']?['content'];
          if (message is! String) throw const FormatException('模型未返回文本内容');
          emit(AiTextDelta(message));
          emit(const AiFinished('stop'));
        } else {
          await for (final event in parseAiStream(stream)) {
            emit(event);
          }
        }
      } on TimeoutException {
        emit(const AiFailed('连接或回复等待超时，请稍后重试'));
      } on FormatException catch (error) {
        emit(AiFailed(error.message.toString()));
      } catch (_) {
        emit(const AiFailed('无法连接模型服务，请检查网络与 HTTPS 地址'));
      } finally {
        deadline.cancel();
        client.close(force: true);
        if (!events.isClosed) unawaited(events.close());
      }
    }

    unawaited(run());
    return AiRequest(events.stream, () async {
      cancelled = true;
      deadline.cancel();
      client.close(force: true);
      if (!events.isClosed) unawaited(events.close());
    });
  }
}

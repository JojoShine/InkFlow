import 'dart:convert';
import 'package:crypto/crypto.dart';

enum AiProvider { deepseek, kimi, glm, qwen, openai, custom }

extension AiProviderInfo on AiProvider {
  String get label => const [
    'DeepSeek',
    'Kimi',
    'GLM 智谱',
    'Qwen 通义千问',
    'OpenAI',
    '自定义兼容服务',
  ][index];
  String get defaultUrl => const [
    'https://api.deepseek.com',
    'https://api.moonshot.cn/v1',
    'https://open.bigmodel.cn/api/paas/v4',
    'https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/compatible-mode/v1',
    'https://api.openai.com/v1',
    '',
  ][index];
}

class AiSettings {
  const AiSettings({
    required this.provider,
    required this.baseUrl,
    required this.model,
  });
  final AiProvider provider;
  final String baseUrl, model;
  String get normalizedUrl => baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  Uri get completionUri => Uri.parse('$normalizedUrl/chat/completions');
  String get credentialId =>
      sha256.convert(utf8.encode('${provider.name}|$normalizedUrl')).toString();
  String get connectionId => '$credentialId|$model';
  void validate() {
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'[{}\s]').hasMatch(normalizedUrl) ||
        model.trim().isEmpty) {
      throw const FormatException('请填写 HTTPS 服务地址和模型 ID，替换地址中的占位符');
    }
  }

  Map<String, Object> toJson() => {
    'provider': provider.name,
    'baseUrl': normalizedUrl,
    'model': model.trim(),
  };
  factory AiSettings.fromJson(Map<String, dynamic> value) => AiSettings(
    provider: AiProvider.values.byName(value['provider'] as String),
    baseUrl: value['baseUrl'] as String,
    model: value['model'] as String,
  );
}

class AiChatMessage {
  const AiChatMessage(this.role, this.content);
  final String role, content;
  Map<String, String> toJson() => {'role': role, 'content': content};
}

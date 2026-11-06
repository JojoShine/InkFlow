import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/labeled_field.dart';
import '../../app/ui_actions.dart';
import 'ai_client.dart';
import 'ai_controller.dart';
import 'ai_settings.dart';

Future<void> showAiSettings(BuildContext context, AiController controller) =>
    showDialog<void>(
      context: context,
      builder: (_) => _AiSettingsDialog(controller: controller),
    );

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.controller});
  final AiController controller;
  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  final url = TextEditingController(),
      model = TextEditingController(),
      key = TextEditingController();
  AiProvider? provider;
  bool busy = false;
  String? message;
  AiRequest? testing;
  @override
  void initState() {
    super.initState();
    provider = widget.controller.activeProvider;
    _loadProvider();
  }

  void _loadProvider() {
    final settings = widget.controller.configurations[provider];
    url.text = settings?.baseUrl ?? provider?.defaultUrl ?? '';
    model.text = settings?.model ?? '';
    key.clear();
  }

  AiSettings _settings() {
    if (provider == null) throw const FormatException('请先选择服务商');
    final value = AiSettings(
      provider: provider!,
      baseUrl: url.text,
      model: model.text,
    );
    value.validate();
    return value;
  }

  Future<void> _perform(bool test) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final value = _settings();
      final ai = widget.controller;
      if (test) {
        final secret = key.text.trim().isEmpty
            ? await ai.credentials.read(value.credentialId)
            : key.text.trim();
        if (secret == null || secret.isEmpty) {
          throw const FormatException('请填写此地址的 API Key');
        }
        if (!mounted) return;
        final request = ai.client.start(value, secret, [
          const AiChatMessage('user', '请仅回复“连接成功”。'),
        ]);
        testing = request;
        bool completed = false;
        await for (final event in request.events) {
          if (!mounted) return;
          if (event is AiFailed) throw FormatException(event.message);
          if (event is AiFinished) {
            completed = true;
            break;
          }
        }
        await request.cancel();
        testing = null;
        if (mounted) setState(() => message = completed ? '连接成功' : '连接中断，请重试');
      } else {
        final replacing =
            ai.turns.isNotEmpty &&
            ai.settings?.connectionId != value.connectionId;
        if (replacing) {
          if (!mounted) return;
          final confirmed = await confirmAction(
            context,
            '更换 AI 连接？',
            '当前作品的本机对话将清空，并开始新对话。',
            action: '更换并开启新对话',
          );
          if (!confirmed) return;
        }
        await ai.configure(
          value,
          key: key.text.trim().isEmpty ? null : key.text.trim(),
        );
        if (replacing) await ai.newConversation();
        if (mounted) Navigator.pop(context);
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => message = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => message = '系统凭据或配置保存失败，请检查后重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(testing?.cancel() ?? Future.value());
    url.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('AI 连接设置'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledField(
              label: '服务商',
              child: DropdownButtonFormField<AiProvider>(
                initialValue: provider,
                isExpanded: true,
                hint: const Text('请选择服务商'),
                items: [
                  for (final p in AiProvider.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: busy
                    ? null
                    : (p) => setState(() {
                        provider = p;
                        _loadProvider();
                      }),
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              label: 'Base URL（不含 /chat/completions）',
              child: TextField(
                controller: url,
                enabled: !busy,
                onChanged: (_) {
                  key.clear();
                  setState(() {});
                },
                decoration: const InputDecoration(hintText: 'https://…'),
              ),
            ),
            if (provider == AiProvider.qwen)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '请按控制台填写地域和业务空间地址，API Key 必须与地域匹配。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            LabeledField(
              label: '模型 ID',
              child: TextField(
                controller: model,
                enabled: !busy,
                decoration: const InputDecoration(
                  hintText: '填写服务商提供的文本对话模型 ID',
                ),
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              label: 'API Key',
              child: TextField(
                controller: key,
                enabled: !busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(hintText: '留空保留此地址已保存的密钥'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '密钥保存在本机系统凭据中。保存配置不会联网；测试连接会发送一条固定短消息，可能产生调用费用。',
              style: TextStyle(fontSize: 12, height: 1.6),
            ),
            if (url.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '请求地址：${url.text.trim().replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
                  style: const TextStyle(fontSize: 11, height: 1.5),
                ),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SelectableText(message!),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('正在处理…'),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy || provider == null
                    ? null
                    : () => uiAction(context, () async {
                        final value = _settings();
                        if (await confirmAction(
                          context,
                          '删除此连接的密钥？',
                          '本机对话和作品正文会保留。',
                          action: '删除密钥',
                        )) {
                          await widget.controller.deleteKey(value);
                          key.clear();
                          if (mounted) setState(() => message = '已删除此地址的密钥');
                        }
                      }),
                child: const Text('删除已保存的密钥'),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: busy ? null : () => _perform(true),
        child: const Text('测试连接'),
      ),
      FilledButton(
        onPressed: busy ? null : () => _perform(false),
        child: const Text('保存配置'),
      ),
    ],
  );
}

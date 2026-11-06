import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/labeled_field.dart';
import '../../app/ink_icons.dart';
import '../appearance/theme_presets.dart';
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
  bool advanced = false, checkingKey = false, keyLookupFailed = false;
  bool savedKey = false;
  int _keyLookup = 0;
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
    advanced =
        provider == AiProvider.custom ||
        provider == AiProvider.qwen ||
        (provider != null && url.text != provider!.defaultUrl);
    unawaited(_refreshSavedKey());
  }

  AiSettings _addressSettings() {
    if (provider == null) throw const FormatException('请先选择服务商');
    final value = AiSettings(
      provider: provider!,
      baseUrl: url.text,
      model: 'credential-lookup',
    );
    value.validate();
    return value;
  }

  Future<void> _refreshSavedKey() async {
    final lookup = ++_keyLookup;
    savedKey = false;
    keyLookupFailed = false;
    checkingKey = false;
    AiSettings value;
    try {
      value = _addressSettings();
    } on FormatException {
      if (mounted) setState(() {});
      return;
    }
    checkingKey = true;
    if (mounted) setState(() {});
    try {
      final exists =
          (await widget.controller.credentials.read(
            value.credentialId,
          ))?.isNotEmpty ??
          false;
      if (!mounted || lookup != _keyLookup) return;
      setState(() {
        savedKey = exists;
        checkingKey = false;
      });
    } catch (_) {
      if (!mounted || lookup != _keyLookup) return;
      setState(() {
        keyLookupFailed = true;
        checkingKey = false;
      });
    }
  }

  Future<void> _deleteSavedKey() async {
    await uiAction(context, () async {
      final value = _addressSettings();
      if (!await confirmAction(
        context,
        '删除此连接的密钥？',
        '下次使用此连接时需要重新填写 API 密钥。',
        action: '删除密钥',
      )) {
        return;
      }
      await widget.controller.deleteKey(value);
      if (!mounted) return;
      key.clear();
      await _refreshSavedKey();
      if (mounted) setState(() => message = '已删除此连接的密钥');
    });
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
    _keyLookup++;
    unawaited(testing?.cancel() ?? Future.value());
    url.dispose();
    model.dispose();
    key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final fieldStyle = textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      height: 1.5,
    );
    final keyStatus = checkingKey
        ? '正在检查密钥…'
        : keyLookupFailed
        ? '暂时无法读取密钥状态'
        : key.text.isNotEmpty
        ? '新密钥将在保存后生效'
        : savedKey
        ? '已保存到本机'
        : '尚未保存密钥';
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: const Text('AI 连接设置', style: TextStyle(fontSize: 22)),
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
                  style: fieldStyle.copyWith(color: colors.ink),
                  icon: const Icon(InkIcons.chevronDown, size: 14),
                  hint: const Text('请选择服务商'),
                  items: [
                    for (final p in AiProvider.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: busy
                      ? null
                      : (p) => setState(() {
                          provider = p;
                          message = null;
                          _loadProvider();
                        }),
                ),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: '模型名称（ID）',
                child: TextField(
                  key: const ValueKey('ai-model'),
                  controller: model,
                  enabled: !busy,
                  style: fieldStyle,
                  decoration: const InputDecoration(hintText: '填写服务商控制台中的模型名称'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '可在服务商控制台的模型列表中查看。',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'API 密钥',
                child: TextField(
                  key: const ValueKey('ai-key'),
                  controller: key,
                  enabled: !busy,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  style: fieldStyle,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: savedKey ? '留空继续使用已保存的密钥' : '粘贴服务商提供的 API Key',
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      keyStatus,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ),
                  if (savedKey)
                    TextButton(
                      onPressed: busy ? null : _deleteSavedKey,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: textTheme.labelLarge!.copyWith(fontSize: 12),
                      ),
                      child: const Text('删除已保存的密钥'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    textStyle: textTheme.labelLarge!.copyWith(fontSize: 13),
                  ),
                  onPressed: busy
                      ? null
                      : () => setState(() => advanced = !advanced),
                  icon: RotatedBox(
                    quarterTurns: advanced ? 1 : 0,
                    child: const Icon(InkIcons.chevronRight, size: 12),
                  ),
                  label: const Text('高级连接设置'),
                ),
              ),
              if (advanced) ...[
                const SizedBox(height: 8),
                LabeledField(
                  label: '服务地址（Base URL）',
                  child: TextField(
                    key: const ValueKey('ai-base-url'),
                    controller: url,
                    enabled: !busy,
                    style: fieldStyle,
                    onChanged: (_) {
                      key.clear();
                      message = null;
                      unawaited(_refreshSavedKey());
                    },
                    decoration: const InputDecoration(hintText: 'https://…'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  provider == AiProvider.qwen
                      ? '按控制台填写地域和业务空间地址，密钥需与地域匹配。'
                      : '填写服务商提供的基础地址，不包含 /chat/completions。',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.muted,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                '保存仅写入本机；测试会向当前服务商发送一条短消息，可能产生调用费用。',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.muted,
                  height: 1.6,
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    message!,
                    style: TextStyle(fontSize: 13, color: colors.accent),
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('正在处理…', style: TextStyle(fontSize: 13)),
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
        OutlinedButton(
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
}

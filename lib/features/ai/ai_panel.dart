import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/ink_icons.dart';
import '../../app/ui_actions.dart';
import '../appearance/theme_presets.dart';
import '../workbench/workbench_controller.dart';
import '../workbench/workbench_panel.dart';
import 'ai_controller.dart';
import 'ai_context.dart';
import 'ai_settings_dialog.dart';
import 'ai_settings.dart';

class AiPanel extends StatefulWidget {
  const AiPanel({
    super.key,
    required this.workbench,
    required this.controller,
    this.width = 320,
  });
  final WorkbenchController workbench;
  final AiController controller;
  final double width;
  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final input = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  AiController get ai => widget.controller;
  @override
  void initState() {
    super.initState();
    input.text = ai.draft;
    ai.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (input.text != ai.draft) {
      input.value = TextEditingValue(
        text: ai.draft,
        selection: TextSelection.collapsed(offset: ai.draft.length),
      );
    }
    setState(() {});
  }

  Future<void> _send() async {
    if (ai.busy) return;
    if (ai.workKey != widget.workbench.workKey) {
      ai.failure = '正在切换作品，请加载完成后发送';
      setState(() {});
      return;
    }
    if (ai.needsNewConversation) {
      if (!await confirmAction(
        context,
        '开启新对话？',
        '当前连接与历史对话不同，新对话会清空本机当前对话。',
        action: '开启新对话',
      )) {
        return;
      }
      await ai.newConversation();
      return;
    }
    await ai.send(input.text);
  }

  Future<void> _attach(AiContextSource source) async {
    await uiAction(context, () async {
      final attachment = await captureAiAttachment(
        controller: widget.workbench,
        source: source,
      );
      if (mounted) {
        setState(() => ai.attachment = attachment);
      }
    });
  }

  @override
  void dispose() {
    ai.removeListener(_changed);
    input.dispose();
    focus.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context), attachment = ai.attachment;
    final stale = attachment?.isStale(widget.workbench) ?? false;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border(left: BorderSide(color: colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CreativePanelTabs(controller: widget.workbench),
          if (ai.loadingConversation)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text('正在读取本机对话…', style: TextStyle(fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ai.settings == null
                        ? '讨论与整理'
                        : '${ai.settings!.provider.label} · ${ai.settings!.model}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ),
                IconButton(
                  tooltip: 'AI 连接设置',
                  onPressed: ai.busy ? null : () => showAiSettings(context, ai),
                  icon: const Icon(InkIcons.appearance, size: 17),
                ),
                IconButton(
                  tooltip: '新对话',
                  onPressed: ai.busy
                      ? null
                      : () => uiAction(context, () async {
                          if (ai.turns.isEmpty ||
                              await confirmAction(
                                context,
                                '开启新对话？',
                                '当前作品的本机对话将清空。',
                                action: '开启新对话',
                              )) {
                            await ai.newConversation();
                          }
                        }),
                  icon: const Icon(InkIcons.add, size: 17),
                ),
              ],
            ),
          ),
          Expanded(
            child: ai.turns.isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '一起理清故事的线索。',
                          style: TextStyle(fontSize: 18, height: 1.6),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '可以讨论人物动机、梳理情节，或评价与总结一段已写内容。',
                          style: TextStyle(fontSize: 14, height: 1.9),
                        ),
                        if (ai.settings == null)
                          TextButton(
                            onPressed: () => showAiSettings(context, ai),
                            child: const Text('配置 AI'),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: ai.turns.length,
                    itemBuilder: (context, i) {
                      final turn = ai.turns[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '你',
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              turn.question,
                              style: const TextStyle(fontSize: 14, height: 1.8),
                            ),
                            if (turn.attachment != null)
                              Text(
                                '已附加：${turn.attachment!.chapterTitle} · ${turn.attachment!.characterCount} 字符',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.muted,
                                ),
                              ),
                            const SizedBox(height: 14),
                            Text(
                              'AI · ${switch (turn.state) {
                                'completed' => '已完成',
                                'receiving' => ai.processing ? '模型处理中' : '回复中',
                                'stopped' => '已停止',
                                'failed' => '失败',
                                'interrupted' => '已中断',
                                _ => '准备中',
                              }}',
                              style: TextStyle(
                                color: colors.accent,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              turn.answer.isEmpty ? '…' : turn.answer,
                              style: const TextStyle(fontSize: 14, height: 1.9),
                            ),
                            if (turn.answer.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => Clipboard.setData(
                                    ClipboardData(text: turn.answer),
                                  ),
                                  child: const Text('复制'),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (ai.failure != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ai.failure!,
                    style: TextStyle(fontSize: 12, color: colors.accent),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: ai.busy
                            ? null
                            : ai.saveFailed
                            ? ai.retrySave
                            : ai.retry,
                        child: const Text('重试'),
                      ),
                      if (ai.saveFailed)
                        TextButton(
                          onPressed: () async {
                            if (await confirmAction(
                              context,
                              '放弃本次对话保存？',
                              '作品正文不受影响，本次尚未落盘的 AI 对话可能丢失。',
                              action: '放弃对话保存',
                            )) {
                              ai.discardFailedSave();
                              if (mounted) setState(() {});
                            }
                          },
                          child: const Text('放弃对话保存'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Wrap(
              spacing: 4,
              children: [
                for (final purpose in AiPurpose.values)
                  TextButton(
                    onPressed: () {
                      ai.purpose = purpose;
                      ai.draft = purpose.draft;
                      input.text = ai.draft;
                      setState(() {});
                      focus.requestFocus();
                    },
                    child: Text(
                      purpose.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: () => setState(() => ai.attachment = null),
                  child: const Text('仅对话', style: TextStyle(fontSize: 11)),
                ),
                TextButton(
                  onPressed: widget.workbench.chapterLoading
                      ? null
                      : () => _attach(AiContextSource.selection),
                  child: const Text('选中文字', style: TextStyle(fontSize: 11)),
                ),
                TextButton(
                  onPressed: widget.workbench.chapterLoading
                      ? null
                      : () => _attach(AiContextSource.chapter),
                  child: const Text('当前章节', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          if (attachment != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${attachment.chapterTitle} · ${attachment.characterCount} 字符',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('本次附加内容'),
                            content: SizedBox(
                              width: 600,
                              child: SingleChildScrollView(
                                child: SelectableText(attachment.text),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        ),
                        child: const Text('预览'),
                      ),
                    ],
                  ),
                  if (stale)
                    const Text('正文已变化，可重新附加', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.enter &&
                    !HardwareKeyboard.instance.isShiftPressed) {
                  if (!input.value.composing.isCollapsed &&
                      input.value.composing.isValid) {
                    return KeyEventResult.ignored;
                  }
                  _send();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: input,
                focusNode: focus,
                minLines: 2,
                maxLines: 4,
                onChanged: (text) => ai.draft = text,
                decoration: const InputDecoration(
                  hintText: '写下想讨论的问题，或粘贴一段内容…',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '包含当前对话历史 · 正文仅主动附加',
                    style: TextStyle(fontSize: 10, color: colors.muted),
                  ),
                ),
                TextButton(
                  onPressed: ai.loadingConversation
                      ? null
                      : ai.busy
                      ? ai.stop
                      : _send,
                  child: Text(
                    ai.loadingConversation
                        ? '读取中'
                        : ai.busy
                        ? '停止'
                        : '发送',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

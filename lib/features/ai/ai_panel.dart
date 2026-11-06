import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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
    if (input.text.trim().isEmpty && ai.attachment == null) return;
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
    await ai.send(input.text.trim().isEmpty ? ai.purpose.draft : input.text);
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
    final contextSource = attachment?.source ?? AiContextSource.conversation;
    final replyStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      height: 1.9,
      color: colors.ink,
    );
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
                  icon: const Icon(InkIcons.aiSettings, size: 18),
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
                  icon: const Icon(InkIcons.newChat, size: 18),
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
                            MarkdownBody(
                              data: turn.answer.isEmpty ? '…' : turn.answer,
                              selectable: true,
                              fitContent: false,
                              imageBuilder: (uri, title, alt) => SelectableText(
                                '图片：${alt ?? title ?? uri.toString()}',
                                style: replyStyle,
                              ),
                              styleSheet:
                                  MarkdownStyleSheet.fromTheme(
                                    Theme.of(context),
                                  ).copyWith(
                                    p: replyStyle,
                                    h1: replyStyle.copyWith(
                                      fontSize: 22,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    h2: replyStyle.copyWith(
                                      fontSize: 20,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    h3: replyStyle.copyWith(
                                      fontSize: 18,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    h4: replyStyle.copyWith(
                                      fontSize: 16,
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    h5: replyStyle.copyWith(
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    h6: replyStyle.copyWith(
                                      height: 1.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    listBullet: replyStyle,
                                    tableHead: replyStyle.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    tableBody: replyStyle,
                                    tableBorder: TableBorder.all(
                                      color: colors.line,
                                    ),
                                    tableCellsPadding: const EdgeInsets.all(8),
                                    blockquote: replyStyle.copyWith(
                                      color: colors.muted,
                                    ),
                                    blockquoteDecoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: colors.line,
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    code: replyStyle.copyWith(
                                      fontFamily: 'monospace',
                                      height: 1.5,
                                    ),
                                    codeblockDecoration: BoxDecoration(
                                      color: colors.selection.withValues(
                                        alpha: .4,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    horizontalRuleDecoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(color: colors.line),
                                      ),
                                    ),
                                    blockSpacing: 12,
                                  ),
                            ),
                            if (turn.answer.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Tooltip(
                                    message: '复制这条 AI 回复',
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: colors.muted,
                                        minimumSize: const Size(0, 28),
                                        padding: EdgeInsets.zero,
                                        textStyle: Theme.of(context)
                                            .textTheme
                                            .labelLarge!
                                            .copyWith(
                                              fontSize: 12,
                                              height: 1.4,
                                              fontWeight: FontWeight.normal,
                                            ),
                                      ),
                                      onPressed: () => Clipboard.setData(
                                        ClipboardData(text: turn.answer),
                                      ),
                                      icon: const Icon(InkIcons.copy, size: 13),
                                      label: const Text('复制回复'),
                                    ),
                                  ),
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
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                for (final purpose in AiPurpose.values)
                  Expanded(
                    child: Semantics(
                      key: ValueKey('ai-purpose-${purpose.name}'),
                      selected: ai.purpose == purpose,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => ai.purpose = purpose),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                width: 2,
                                color: ai.purpose == purpose
                                    ? colors.accent
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Text(
                            purpose.label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: ai.purpose == purpose
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: ai.purpose == purpose
                                  ? colors.accent
                                  : colors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colors.paper,
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (attachment != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${attachment.chapterTitle} · ${attachment.characterCount} 字符',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.muted,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '移除附加内容',
                              icon: const Icon(InkIcons.close, size: 14),
                              onPressed: () =>
                                  setState(() => ai.attachment = null),
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
                          const Text(
                            '正文已变化，可重新附加',
                            style: TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                Focus(
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
                    minLines: 3,
                    maxLines: 4,
                    onChanged: (text) => setState(() => ai.draft = text),
                    decoration: InputDecoration(
                      hintText: switch (ai.purpose) {
                        AiPurpose.organize => '写下想讨论的问题，或记录零散想法…',
                        AiPurpose.evaluate => '粘贴内容，或附加正文后说明想评价的方面…',
                        AiPurpose.summarize => '附加正文，或粘贴需要总结的内容…',
                      },
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                    ),
                    style: const TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 8, 8),
                  child: Row(
                    children: [
                      PopupMenuButton<AiContextSource>(
                        key: const ValueKey('ai-context-menu'),
                        tooltip: '选择要附加的正文',
                        constraints: const BoxConstraints.tightFor(width: 144),
                        menuPadding: const EdgeInsets.symmetric(vertical: 4),
                        elevation: 2,
                        shadowColor: colors.ink.withValues(alpha: .12),
                        onSelected: _attach,
                        itemBuilder: (context) => [
                          for (final source in AiContextSource.values)
                            PopupMenuItem(
                              key: ValueKey('ai-source-${source.name}'),
                              value: source,
                              height: 34,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              enabled:
                                  source == AiContextSource.conversation ||
                                  (!widget.workbench.chapterLoading &&
                                      widget.workbench.activeChapterId != null),
                              labelTextStyle: WidgetStateProperty.resolveWith(
                                (states) => Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(
                                      fontSize: 12,
                                      height: 1.4,
                                      fontWeight: source == contextSource
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color:
                                          states.contains(WidgetState.disabled)
                                          ? colors.muted.withValues(alpha: .5)
                                          : source == contextSource
                                          ? colors.accent
                                          : colors.ink,
                                    ),
                              ),
                              child: Semantics(
                                key: ValueKey('ai-source-state-${source.name}'),
                                selected: source == contextSource,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        const [
                                          '不附正文',
                                          '选中片段',
                                          '当前章节',
                                        ][source.index],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 14,
                                      child: source == contextSource
                                          ? Icon(
                                              InkIcons.check,
                                              size: 14,
                                              color: colors.accent,
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                InkIcons.chapter,
                                size: 14,
                                color: colors.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                attachment == null
                                    ? '附加正文'
                                    : const [
                                        '不附正文',
                                        '选中片段',
                                        '当前章节',
                                      ][attachment.source.index],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: attachment == null
                                      ? colors.muted
                                      : colors.accent,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                InkIcons.chevronDown,
                                size: 10,
                                color: colors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton.filled(
                        tooltip: ai.loadingConversation
                            ? '正在读取对话'
                            : ai.busy
                            ? '停止生成'
                            : '发送（Enter）',
                        style: IconButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          backgroundColor: colors.accent,
                          disabledForegroundColor: colors.muted.withValues(
                            alpha: .5,
                          ),
                          disabledBackgroundColor: colors.line.withValues(
                            alpha: .5,
                          ),
                          minimumSize: const Size(32, 32),
                          fixedSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: ai.loadingConversation
                            ? null
                            : ai.busy
                            ? ai.stop
                            : input.text.trim().isNotEmpty || attachment != null
                            ? _send
                            : null,
                        icon: Icon(
                          ai.busy ? InkIcons.close : InkIcons.send,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Enter 发送 · Shift+Enter 换行',
                    style: TextStyle(fontSize: 10, color: colors.muted),
                  ),
                ),
                Tooltip(
                  message: '包含当前对话中已发送的历史内容；正文仅在主动附加后发送。',
                  child: Icon(InkIcons.info, size: 12, color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

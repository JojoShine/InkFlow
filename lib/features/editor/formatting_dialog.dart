import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage/operation_journal.dart';
import '../../app/ui_actions.dart';
import '../workbench/workbench_controller.dart';
import 'text_formatting.dart';

Future<void> showFormatting(BuildContext context, WorkbenchController c) =>
    uiAction(context, () async {
      await c.session.synchronizeNative?.call(true);
      if (!context.mounted || c.activeChapterId == null) return;
      final key = c.workKey, id = c.activeChapterId!;
      final result = await showDialog<FormattingPreview>(
        context: context,
        builder: (_) => _FormattingDialog(controller: c),
      );
      if (result == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('排版已整理'),
          action: SnackBarAction(
            label: '撤销排版',
            onPressed: () => uiAction(
              context,
              () => c.applyFormatting(
                result,
                expectedWorkKey: key,
                expectedChapterId: id,
                undo: true,
              ),
            ),
          ),
        ),
      );
    });

class _FormattingDialog extends StatefulWidget {
  const _FormattingDialog({required this.controller});
  final WorkbenchController controller;
  @override
  State<_FormattingDialog> createState() => _FormattingDialogState();
}

class _FormattingDialogState extends State<_FormattingDialog> {
  late final c = widget.controller;
  late final String source, key, id;
  late final TextSelection selection;
  late bool selected;
  @override
  void initState() {
    super.initState();
    source = c.session.controller.text;
    key = c.workKey;
    id = c.activeChapterId!;
    selection = c.session.controller.selection;
    selected = selection.isValid && !selection.isCollapsed;
  }

  FormattingOptions options = const FormattingOptions();
  bool applying = false;
  String? error;

  Future<void> apply(FormattingPreview preview) async {
    setState(() {
      applying = true;
      error = null;
    });
    try {
      await c.applyFormatting(
        preview,
        expectedWorkKey: key,
        expectedChapterId: id,
      );
      if (mounted) Navigator.pop(context, preview);
    } on FormatException catch (e) {
      error = e.message;
    } on FileSystemException catch (e) {
      error = e.message;
    } on SaveException catch (e) {
      error = e.toString();
    } on PlatformException catch (e) {
      error = e.message ?? '编辑器暂不可用';
    }
    if (mounted) setState(() => applying = false);
  }

  @override
  Widget build(BuildContext context) {
    FormattingPreview? preview;
    try {
      preview = TextFormatting.preview(
        source,
        range: selected
            ? TextRange(start: selection.start, end: selection.end)
            : null,
        options: options,
      );
    } on FormatException catch (e) {
      error = e.message;
    }
    final result = preview;
    return PopScope(
      canPop: !applying,
      child: AlertDialog(
        title: const Text('排版整理'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '整理空白与段落间距，保留原句和标点。',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                if (selection.isValid && !selection.isCollapsed) ...[
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: const Text('选中文字'),
                        selected: selected,
                        onSelected: applying
                            ? null
                            : (_) => setState(() => selected = true),
                      ),
                      ChoiceChip(
                        label: const Text('当前章节'),
                        selected: !selected,
                        onSelected: applying
                            ? null
                            : (_) => setState(() => selected = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                for (final item in <(String, bool, void Function(bool))>[
                  (
                    '清理段首缩进空格',
                    options.trimIndent,
                    (v) => options = options.copyWith(trimIndent: v),
                  ),
                  (
                    '清理段尾空白',
                    options.trimTrailing,
                    (v) => options = options.copyWith(trimTrailing: v),
                  ),
                  (
                    '合并多余空行，保留一个空行',
                    options.collapseBlankLines,
                    (v) => options = options.copyWith(collapseBlankLines: v),
                  ),
                ])
                  CheckboxListTile(
                    title: Text(item.$1, style: const TextStyle(fontSize: 14)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: item.$2,
                    onChanged: applying
                        ? null
                        : (v) => setState(() => item.$3(v!)),
                  ),
                const SizedBox(height: 16),
                if (result != null) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final panes = [
                        pane('整理前', result.before),
                        pane('整理后', result.replacement),
                      ];
                      return constraints.maxWidth < 560
                          ? Column(
                              children: [
                                panes.first,
                                const SizedBox(height: 12),
                                panes.last,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: panes.first),
                                const SizedBox(width: 16),
                                Expanded(child: panes.last),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    result.hasChanges
                        ? '调整 ${result.changedLines} 行 · 移除 ${result.removedBlankLines} 个多余空行'
                        : '当前内容已经整齐，无需调整',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: applying ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: applying || result == null || !result.hasChanges
                ? null
                : () => apply(result),
            child: Text(applying ? '正在整理…' : '应用排版'),
          ),
        ],
      ),
    );
  }

  Widget pane(String title, String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: const TextStyle(fontSize: 14)),
      const SizedBox(height: 12),
      Container(
        height: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? '（空白）' : text,
            style: const TextStyle(fontSize: 14, height: 1.7),
          ),
        ),
      ),
    ],
  );
}

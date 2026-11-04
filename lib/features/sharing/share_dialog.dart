import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/labeled_field.dart';
import '../../app/ui_actions.dart';
import '../workbench/workbench_controller.dart';
import 'share_card.dart';

Future<void> showShareCard(BuildContext context, WorkbenchController c) =>
    uiAction(context, () async {
      await c.session.synchronizeNative?.call(true);
      if (!context.mounted || c.work == null || c.activeChapter == null) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ShareDialog(
          controller: c,
          initial: ShareCard.excerpt(
            c.session.controller.text,
            c.session.controller.selection,
          ),
        ),
      );
    });

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.controller, required this.initial});
  final WorkbenchController controller;
  final String initial;
  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late final body = TextEditingController(text: widget.initial);
  final signature = TextEditingController();
  late final work = widget.controller.work!;
  late final chapter = widget.controller.activeChapter!.title;
  late ShareCardStyle style = widget.controller.appearance.isNight
      ? ShareCardStyle.night
      : ShareCardStyle.paper;
  ShareCardImage? image;
  Timer? debounce;
  int generation = 0;
  bool rendering = true, saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    render();
  }

  void changed() {
    debounce?.cancel();
    generation++;
    setState(() {
      rendering = true;
      error = null;
    });
    debounce = Timer(const Duration(milliseconds: 180), render);
  }

  Future<void> render() async {
    final token = ++generation;
    try {
      final next = await ShareCard.render(
        body: body.text,
        work: work.manifest.title,
        chapter: chapter,
        signature: signature.text,
        style: style,
      );
      if (mounted && token == generation) {
        setState(() {
          image = next;
          rendering = false;
          error = null;
        });
      }
    } on FormatException catch (e) {
      if (mounted && token == generation) {
        setState(() {
          image = null;
          rendering = false;
          error = e.message;
        });
      }
    }
  }

  Future<void> save() async {
    final current = image;
    if (current == null || rendering || saving) return;
    setState(() => saving = true);
    await uiAction(context, () async {
      final name = '${work.manifest.title}-片段'.replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
        '_',
      );
      final saved = await widget.controller.services.saveShareImage(
        current.bytes,
        name,
        workRoot: work.root,
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片已保存')));
      }
    });
    if (mounted) setState(() => saving = false);
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    body.dispose();
    signature.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('片段分享'),
      content: SizedBox(
        width: 900,
        height: math.min(540, MediaQuery.sizeOf(context).height - 220),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fields = SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '把喜欢的文字留成一张卡片。这里的修改不会改变正文。',
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  LabeledField(
                    label: '分享片段',
                    child: TextField(
                      key: const ValueKey('share-body'),
                      controller: body,
                      enabled: !saving,
                      minLines: 4,
                      maxLines: 6,
                      onChanged: (_) => changed(),
                      decoration: InputDecoration(
                        hintText: '写下想分享的文字',
                        helperText: '${body.text.characters.length} / 600 字',
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  LabeledField(
                    label: '署名（选填）',
                    child: TextField(
                      controller: signature,
                      enabled: !saving,
                      maxLength: 80,
                      onChanged: (_) => changed(),
                      decoration: const InputDecoration(hintText: '你的笔名'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('卡片样式', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final item in ShareCardStyle.values)
                        ChoiceChip(
                          label: Text(item.label),
                          selected: style == item,
                          onSelected: saving
                              ? null
                              : (_) {
                                  setState(() => style = item);
                                  changed();
                                },
                        ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
            );
            final preview = Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text(
                    rendering ? '正在生成预览…' : '图片预览',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: image == null
                        ? Center(
                            child: Text(
                              error == null ? '准备卡片…' : '调整片段后即可预览',
                              style: const TextStyle(fontSize: 13),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Image.memory(
                              image!.bytes,
                              key: const ValueKey('share-preview'),
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                  ),
                ],
              ),
            );
            return constraints.maxWidth < 620
                ? SingleChildScrollView(
                    child: Column(
                      children: [
                        fields,
                        const SizedBox(height: 20),
                        SizedBox(height: 360, child: preview),
                      ],
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: fields),
                      const SizedBox(width: 28),
                      Expanded(child: preview),
                    ],
                  );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        OutlinedButton(
          onPressed: saving || body.text.trim().isEmpty
              ? null
              : () => uiAction(context, () async {
                  await Clipboard.setData(ClipboardData(text: body.text));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('片段文字已复制')));
                  }
                }),
          child: const Text('复制文字'),
        ),
        FilledButton(
          onPressed: saving || rendering || image == null || error != null
              ? null
              : save,
          child: Text(saving ? '正在保存…' : '保存图片'),
        ),
      ],
    ),
  );
}

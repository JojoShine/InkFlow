import '../../app/labeled_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import '../../app/ui_actions.dart';
import '../appearance/theme_presets.dart';
import '../typing_sound/typing_sound_settings.dart';
import '../workbench/workbench_controller.dart';
import '../../app/ink_icons.dart';

String writingDuration(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  final minutes = two(duration.inMinutes % 60);
  final seconds = two(duration.inSeconds % 60);
  return duration.inHours == 0
      ? '$minutes:$seconds'
      : '${two(duration.inHours)}:$minutes:$seconds';
}

Future<void> showWritingStatistics(
  BuildContext context,
  WorkbenchController c,
) => showDialog<void>(
  context: context,
  builder: (context) => AnimatedBuilder(
    animation: Listenable.merge([c, c.session.statistics]),
    builder: (context, _) {
      final stats = c.session.statistics;
      final colors = InkPalette.of(context);
      return AlertDialog(
        title: const Text('本次码字统计'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('作品', style: TextStyle(color: colors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                c.work?.manifest.title ?? '',
                style: const TextStyle(fontSize: 19),
              ),
              const SizedBox(height: 18),
              Text('章节', style: TextStyle(color: colors.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                c.activeChapter?.title ?? '',
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: _Metric(
                      label: '码字速率',
                      value: '${stats.wordsPerMinute}',
                      unit: '字 / 分钟',
                    ),
                  ),
                  Expanded(
                    child: _Metric(
                      label: '码字时长',
                      value: writingDuration(stats.elapsed),
                      unit: stats.words == 0 && stats.elapsed == Duration.zero
                          ? '输入后自动开始'
                          : stats.isPaused
                          ? '已暂停'
                          : '正在码字',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '本次手动输入 ${stats.words} 字。停笔 60 秒自动暂停；粘贴、导入和撤销不计入速率。',
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  ),
);

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});
  final String label, value, unit;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(color: InkPalette.of(context).muted, fontSize: 13),
      ),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 30)),
      const SizedBox(height: 6),
      Text(
        unit,
        style: TextStyle(color: InkPalette.of(context).muted, fontSize: 12),
      ),
    ],
  );
}

Future<void> showTypingSound(BuildContext context, WorkbenchController c) =>
    showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          final sound = c.preferences.typingSound;
          final colors = InkPalette.of(context);
          return AlertDialog(
            title: const Text('敲字音效'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('给敲字一点轻轻的回应。', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 20),
                  LabeledField(
                    label: '音效',
                    child: DropdownButtonFormField<TypingSoundPreset>(
                      icon: const Icon(InkIcons.chevronDown, size: 12),
                      initialValue: sound.preset,
                      decoration: const InputDecoration(),
                      items: [
                        for (final preset in TypingSoundPreset.values)
                          DropdownMenuItem(
                            value: preset,
                            child: Text(preset.label),
                          ),
                      ],
                      onChanged: (preset) {
                        if (preset != null) {
                          c.updateTypingSound(sound.copyWith(preset: preset));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Text('音量')),
                      Text(
                        '${(sound.volume * 100).round()}%',
                        style: TextStyle(color: colors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      label: '音效音量',
                      child: CupertinoSlider(
                        value: sound.volume,
                        activeColor: colors.accent,
                        thumbColor: colors.accent,
                        onChanged: (value) =>
                            c.updateTypingSound(sound.copyWith(volume: value)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '只在正文敲字时播放，快捷键和粘贴不会触发。',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.muted,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed:
                    sound.preset == TypingSoundPreset.off || sound.volume == 0
                    ? null
                    : () => uiAction(context, () async {
                        await c.session.previewTypingSound?.call();
                      }),
                icon: const Icon(InkIcons.volumeOn),
                label: const Text('试听'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );

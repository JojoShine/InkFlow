import '../../app/labeled_field.dart';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../app/ui_actions.dart';
import '../workbench/workbench_controller.dart';
import '../works/work_models.dart';
import 'theme_presets.dart';
import 'appearance_settings.dart';
import 'study_surface.dart';
import '../../app/ink_icons.dart';

Future<void> showAppearance(
  BuildContext context,
  WorkbenchController c,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final appearance = c.appearance;
      final current = appearance.current;
      final colors = InkPalette.of(context);
      final layout = c.preferences.layout;
      final fonts = Platform.isWindows
          ? {
              'Songti SC': '默认字体（宋体）',
              'Microsoft YaHei': '微软雅黑',
              'SimSun': '宋体',
              'KaiTi': '楷体',
            }
          : {'Songti SC': '默认字体（宋体）', 'PingFang SC': '苹方', 'Kaiti SC': '楷体'};
      return AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('布置你的书房')),
            IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(InkIcons.close),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          height: 610,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView(
              children: [
                Text('主题', style: TextStyle(color: colors.muted, fontSize: 13)),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, size) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final preset in inkThemePresets)
                        SizedBox(
                          width: (size.maxWidth - 12) / 2,
                          child: _ThemePreview(
                            preset: preset,
                            selected: appearance.presetId == preset.id,
                            onTap: () => c.updateAppearance(
                              appearance.select(preset.id),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text('壁纸', style: TextStyle(color: colors.muted, fontSize: 13)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(InkIcons.image, size: 18),
                      label: Text(
                        current.wallpaperPath == null ? '使用自己的图片' : '更换壁纸',
                      ),
                      onPressed: () => uiAction(context, () async {
                        final file = await openFile(
                          acceptedTypeGroups: [
                            const XTypeGroup(
                              label: '图片',
                              extensions: ['png', 'jpg', 'jpeg', 'webp'],
                              uniformTypeIdentifiers: ['public.image'],
                            ),
                          ],
                        );
                        if (file == null) return;
                        final directory = Directory(
                          p.join(c.dataRoot.path, 'wallpapers'),
                        );
                        await directory.create(recursive: true);
                        final target = p.join(
                          directory.path,
                          '${newId()}${p.extension(file.path)}',
                        );
                        await File(file.path).copy(target);
                        c.updateAppearance(
                          c.appearance.updateCurrent(
                            c.appearance.current.copyWith(
                              wallpaperPath: target,
                            ),
                          ),
                        );
                      }),
                    ),
                    if (current.wallpaperPath != null)
                      TextButton(
                        onPressed: () => c.updateAppearance(
                          appearance.updateCurrent(
                            current.copyWith(clearWallpaper: true),
                          ),
                        ),
                        child: Text(
                          appearance.preset.wallpaperAsset == null
                              ? '移除'
                              : '恢复主题背景',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '强调色',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 14,
                  children: [
                    for (final color in [
                      0xff8b6245,
                      0xff777461,
                      0xff647e85,
                      0xff9b6b70,
                      0xff82708d,
                      0xffad8656,
                    ])
                      Tooltip(
                        message: '选择强调色',
                        child: InkWell(
                          onTap: () => c.updateAppearance(
                            appearance.updateCurrent(
                              current.copyWith(accentColor: color),
                            ),
                          ),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.paper,
                                width: current.accentColor == color ? 3 : 0,
                              ),
                            ),
                            child: current.accentColor == color
                                ? const Icon(
                                    InkIcons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _SettingSlider(
                  label: '编辑区不透明度',
                  value: current.editorOpacity,
                  min: 0.7,
                  max: 1,
                  formatValue: (value) => '${(value * 100).round()}%',
                  onChanged: (value) => c.updateAppearance(
                    appearance.updateCurrent(
                      current.copyWith(editorOpacity: value),
                    ),
                  ),
                ),
                _SettingSlider(
                  label: '背景压暗',
                  value: current.backgroundDim,
                  min: 0,
                  max: 0.7,
                  formatValue: (value) => '${(value * 100).round()}%',
                  onChanged: (value) => c.updateAppearance(
                    appearance.updateCurrent(
                      current.copyWith(backgroundDim: value),
                    ),
                  ),
                ),
                _SettingSlider(
                  label: '背景柔化',
                  value: current.backgroundBlur,
                  min: 0,
                  max: 16,
                  onChanged: (value) => c.updateAppearance(
                    appearance.updateCurrent(
                      current.copyWith(backgroundBlur: value),
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('界面动效'),
                  subtitle: const Text('轻柔的主题与面板过渡'),
                  value: appearance.animationsEnabled,
                  onChanged: (value) =>
                      c.updateAppearance(appearance.withAnimations(value)),
                ),
                const SizedBox(height: 20),
                Divider(color: colors.line),
                const SizedBox(height: 20),
                const Text('阅读与排版', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text(
                  '换主题时，这些习惯会保留。',
                  style: TextStyle(fontSize: 12, color: colors.muted),
                ),
                const SizedBox(height: 20),
                LabeledField(
                  label: '正文字体',
                  child: DropdownButtonFormField<String>(
                    icon: const Icon(InkIcons.chevronDown, size: 12),
                    initialValue: fonts.containsKey(layout.fontFamily)
                        ? layout.fontFamily
                        : fonts.keys.first,
                    decoration: const InputDecoration(),
                    items: fonts.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        c.updateLayout(layout.copyWith(fontFamily: value));
                      }
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _SettingSlider(
                  label: '字号',
                  value: layout.fontSize,
                  min: 12,
                  max: 36,
                  onChanged: (value) => c.updateLayout(
                    layout.copyWith(fontSize: value.roundToDouble()),
                  ),
                ),
                _SettingSlider(
                  label: '行高',
                  value: layout.lineHeight,
                  min: 1.2,
                  max: 2.6,
                  formatValue: (value) => value.toStringAsFixed(1),
                  onChanged: (value) =>
                      c.updateLayout(layout.copyWith(lineHeight: value)),
                ),
                _SettingSlider(
                  label: '段间距',
                  value: layout.paragraphGap,
                  min: 0,
                  max: 32,
                  onChanged: (value) => c.updateLayout(
                    layout.copyWith(paragraphGap: value.roundToDouble()),
                  ),
                ),
                _SettingSlider(
                  label: '首行缩进',
                  value: layout.firstLineIndentEm,
                  min: 0,
                  max: 4,
                  formatValue: (value) => '${value.toStringAsFixed(1)} 字',
                  onChanged: (value) =>
                      c.updateLayout(layout.copyWith(firstLineIndentEm: value)),
                ),
                _SettingSlider(
                  label: '正文宽度',
                  value: layout.maxWidth,
                  min: 480,
                  max: 1000,
                  onChanged: (value) => c.updateLayout(
                    layout.copyWith(maxWidth: value.roundToDouble()),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => c.updateAppearance(appearance.resetCurrent()),
            child: const Text('恢复当前主题默认外观'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('完成'),
          ),
        ],
      );
    },
  ),
);

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.formatValue,
  });
  final String label;
  final double value, min, max;
  final String Function(double)? formatValue;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    final step = (max - min) / 20;
    final increased = (value + step).clamp(min, max);
    final decreased = (value - step).clamp(min, max);
    final format = formatValue ?? (double value) => value.round().toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 14)),
              ),
              Text(
                format(value),
                style: TextStyle(
                  color: InkPalette.of(context).muted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          // Avoid Material Slider's orphaned value-indicator portal on Flutter 3.41.
          // Keep formatted adjustable semantics and desktop keyboard controls.
          Semantics(
            container: true,
            slider: true,
            label: label,
            value: format(value),
            increasedValue: format(increased),
            decreasedValue: format(decreased),
            onIncrease: () => onChanged(increased),
            onDecrease: () => onChanged(decreased),
            child: ExcludeSemantics(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                      onChanged(increased),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      onChanged(increased),
                  const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                      onChanged(decreased),
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      onChanged(decreased),
                  const SingleActivator(LogicalKeyboardKey.home): () =>
                      onChanged(min),
                  const SingleActivator(LogicalKeyboardKey.end): () =>
                      onChanged(max),
                },
                child: Focus(
                  child: Builder(
                    builder: (context) => Listener(
                      onPointerDown: (_) => Focus.of(context).requestFocus(),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: CupertinoSlider(
                          value: value.clamp(min, max),
                          min: min,
                          max: max,
                          activeColor: InkPalette.of(context).accent,
                          thumbColor: InkPalette.of(context).accent,
                          onChanged: onChanged,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.preset,
    required this.selected,
    required this.onTap,
  });
  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final border = Color(preset.accent);
    final preview = InkPalette.from(AppearanceSettings(presetId: preset.id));
    return Semantics(
      button: true,
      selected: selected,
      label: preset.title,
      child: Material(
        color: Color(preset.background),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 116,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? border : InkPalette.of(context).line,
                width: selected ? 2 : 1,
              ),
            ),
            child: StudySurface(
              color: Color(preset.background),
              settings: AppearanceSettings(presetId: preset.id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (preset.wallpaperAsset != null)
                    Image.asset(
                      preset.wallpaperAsset!,
                      fit: BoxFit.cover,
                      cacheWidth: preset.pixelArt ? null : 440,
                      filterQuality: preset.pixelArt
                          ? FilterQuality.none
                          : FilterQuality.low,
                    ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      color: Color(preset.paper).withValues(alpha: .94),
                      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  preset.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: preview.ink,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  preset.description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: preview.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            Icon(InkIcons.checkCircle, color: border, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

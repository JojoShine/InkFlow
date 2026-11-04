import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../app/ui_actions.dart';
import '../../app/desktop_actions.dart';
import '../appearance/appearance_panel.dart';
import '../appearance/theme_presets.dart';
import '../appearance/wallpaper_layer.dart';
import '../appearance/study_surface.dart';
import '../editor/novel_editor.dart';
import '../editor/writing_tools_panel.dart';
import '../editor/formatting_dialog.dart';
import '../sharing/share_dialog.dart';
import '../typing_sound/typing_sound_settings.dart';
import '../library/library_screen.dart';
import '../notes/note_models.dart';
import '../notes/notes_panel.dart';
import '../recovery/recovery_panel.dart';
import '../../core/storage/record_store.dart';
import 'chapter_sidebar.dart';
import 'workbench_controller.dart';
import 'work_actions_menu.dart';
import '../../app/ink_icons.dart';

class WorkbenchScreen extends StatelessWidget {
  const WorkbenchScreen({super.key, required this.controller});
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = InkPalette.of(context);
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          WallpaperLayer(
            settings: c.appearance,
            child: Column(
              children: [
                IgnorePointer(
                  ignoring: c.busy,
                  child: _Toolbar(controller: c),
                ),
                if (c.notice != null)
                  Container(
                    color: colors.selection,
                    padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                    child: Row(
                      children: [
                        Icon(InkIcons.info, size: 18, color: colors.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            c.notice!,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        if (c.work != null &&
                            (c.session.lastOutcome.state ==
                                    SaveState.conflict ||
                                c.hasConflicts))
                          TextButton(
                            onPressed: () => showConflicts(context, c),
                            child: const Text('比较版本'),
                          ),
                        IconButton(
                          tooltip: '收起提示',
                          onPressed: c.dismissNotice,
                          icon: const Icon(InkIcons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                if (c.recoveredDraft != null && !c.libraryVisible)
                  Container(
                    color: colors.selection,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '发现一份未保存的本机草稿',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final restored = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('本机恢复草稿'),
                                content: SizedBox(
                                  width: 680,
                                  height: 400,
                                  child: SingleChildScrollView(
                                    child: SelectableText(
                                      c.recoveredDraft!.text,
                                      style: const TextStyle(height: 1.8),
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: const Text('稍后处理'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: const Text('恢复为当前稿'),
                                  ),
                                ],
                              ),
                            );
                            if (restored == true && context.mounted) {
                              await uiAction(context, c.acceptRecoveredDraft);
                            }
                          },
                          child: const Text('查看与恢复'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: c.busy && (c.libraryVisible || c.work == null)
                      ? const Center(child: CircularProgressIndicator())
                      : c.libraryVisible || c.work == null
                      ? LibraryScreen(controller: c)
                      : LayoutBuilder(
                          builder: (context, size) {
                            final showRight =
                                c.panel != null &&
                                size.maxWidth -
                                        (c.leftVisible ? 224 : 0) -
                                        320 >=
                                    540;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (c.leftVisible)
                                  ChapterSidebar(
                                    key: ValueKey(
                                      'directory-${c.work!.manifest.workId}',
                                    ),
                                    controller: c,
                                  ),
                                Expanded(
                                  key: const ValueKey('editor-pane'),
                                  child: StudySurface(
                                    settings: c.appearance,
                                    color: colors.paper.withValues(
                                      alpha: c.appearance.current.editorOpacity,
                                    ),
                                    child: c.activeChapter == null
                                        ? _EmptyChapter(controller: c)
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      48,
                                                      48,
                                                      48,
                                                      28,
                                                    ),
                                                child: Align(
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: ConstrainedBox(
                                                    constraints: BoxConstraints(
                                                      maxWidth: c
                                                          .preferences
                                                          .layout
                                                          .maxWidth,
                                                    ),
                                                    child: SizedBox(
                                                      width: double.infinity,
                                                      child: Text(
                                                        c.activeChapter!.title,
                                                        style: TextStyle(
                                                          fontSize: 30,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: colors.ink,
                                                          height: 1.4,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: NovelEditor(
                                                  session: c.session,
                                                  overlayOpen:
                                                      c.workMenuOpen || c.busy,
                                                  focusMode: c.focusMode,
                                                  onFileAction: (action) =>
                                                      dispatchDesktopAction(
                                                        c,
                                                        action,
                                                      ),
                                                  onSave: () async {
                                                    if (!c.busy) {
                                                      await c.flushAll();
                                                    }
                                                  },
                                                  onExitFocus: () {
                                                    if (c.focusMode) {
                                                      c.toggleFocus();
                                                    }
                                                  },
                                                  layout: c.preferences.layout,
                                                  typingSound:
                                                      c.preferences.typingSound,
                                                  textColor: colors.ink,
                                                  backgroundColor:
                                                      Platform.isWindows
                                                      ? colors.paper
                                                      : Colors.transparent,
                                                ),
                                              ),
                                              _StatusBar(controller: c),
                                            ],
                                          ),
                                  ),
                                ),
                                if (showRight)
                                  NotesPanel(
                                    key: ValueKey(
                                      '${c.work!.manifest.workId}-${c.panel}',
                                    ),
                                    controller: c,
                                    kind: c.panel!,
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (c.busy && c.work != null && !c.libraryVisible)
            const Positioned.fill(
              child: AbsorbPointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});
  final WorkbenchController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = InkPalette.of(context);
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.96),
        border: Border(bottom: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          DragToMoveArea(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: Platform.isMacOS ? 82 : 20),
                Tooltip(
                  message: 'InkFlow',
                  child: Icon(
                    Icons.eco_outlined,
                    color: colors.accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  height: 22,
                  child: VerticalDivider(color: colors.line, width: 1),
                ),
              ],
            ),
          ),
          if (!c.libraryVisible && c.work != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: '返回书架',
              onPressed: c.showLibrary,
              icon: const Icon(InkIcons.back, size: 18),
            ),
            const SizedBox(width: 8),
          ] else
            const SizedBox(width: 20),
          Expanded(
            child: DragToMoveArea(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  c.libraryVisible ? '书架' : c.work?.manifest.title ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
          if (!c.libraryVisible && c.work != null) ...[
            IconButton(
              tooltip: c.leftVisible ? '收起章节' : '展开章节',
              onPressed: c.toggleLeft,
              icon: const Icon(InkIcons.sidebar, size: 20),
            ),
            IconButton(
              tooltip: c.panel == null ? '展开创作资料' : '收起创作资料',
              onPressed: () {
                if (MediaQuery.sizeOf(context).width < 1100 && c.leftVisible) {
                  c.toggleLeft();
                }
                c.setPanel(c.panel == null ? NoteKind.outline : null);
              },
              icon: const Icon(InkIcons.sidebarRight, size: 20),
            ),
            TextButton.icon(
              onPressed: c.toggleFocus,
              icon: Icon(
                c.focusMode ? InkIcons.exitFocus : InkIcons.focus,
                size: 20,
              ),
              label: Text(c.focusMode ? '退出专注' : '专注'),
            ),
            const SizedBox(width: 8),
          ],
          TextButton.icon(
            onPressed: () => showAppearance(context, c),
            icon: const Icon(InkIcons.appearance, size: 20),
            label: const Text('外观'),
          ),
          if (!c.libraryVisible && c.work != null)
            WorkActionsMenu(controller: c),
          if (c.libraryVisible) LibraryActionsMenu(controller: c),
          const SizedBox(width: 12),
          if (Platform.isWindows) ...[
            IconButton(
              tooltip: '最小化',
              onPressed: windowManager.minimize,
              icon: const Icon(InkIcons.minus, size: 18),
            ),
            IconButton(
              tooltip: '最大化或还原',
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              icon: const Icon(InkIcons.window, size: 16),
            ),
            IconButton(
              tooltip: '关闭',
              onPressed: windowManager.close,
              icon: const Icon(InkIcons.close, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});
  final WorkbenchController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = InkPalette.of(context);
    final status = c.session.isSaving
        ? '正在保存'
        : c.session.lastOutcome.state == SaveState.conflict
        ? '发现冲突'
        : c.session.lastOutcome.state == SaveState.failed
        ? '保存失败'
        : c.session.isDirty || c.notes?.isDirty == true
        ? '待保存'
        : '已保存到本机';
    final toolStyle = TextButton.styleFrom(
      foregroundColor: colors.muted,
      minimumSize: const Size(0, 28),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colors.paper,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final savedLabel = constraints.maxWidth < 620 && status == '已保存到本机'
              ? '已保存'
              : status;
          return Row(
            children: [
              Tooltip(
                message: '全书 ${formatNumber(c.totalWords)} 字',
                child: Text(
                  '${formatNumber(c.chapterWords)} 字',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: toolStyle,
                onPressed: () => showWritingStatistics(context, c),
                icon: const Icon(InkIcons.statistics, size: 16),
                label: const Text('码字统计'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: toolStyle,
                onPressed: c.busy || c.activeChapterId == null
                    ? null
                    : () => showFormatting(context, c),
                icon: const Icon(InkIcons.format, size: 16),
                label: const Text('排版'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: toolStyle,
                onPressed: c.busy || c.activeChapterId == null
                    ? null
                    : () => showShareCard(context, c),
                icon: const Icon(InkIcons.share, size: 16),
                label: const Text('分享'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: toolStyle,
                onPressed: () => showTypingSound(context, c),
                icon: Icon(
                  c.preferences.typingSound.preset == TypingSoundPreset.off
                      ? InkIcons.volumeOff
                      : InkIcons.volumeOn,
                  size: 16,
                ),
                label: const Text('键音'),
              ),
              const SizedBox(width: 20),
              Icon(
                c.session.lastOutcome.isSaved ? InkIcons.check : InkIcons.info,
                size: 14,
                color: colors.muted,
              ),
              const SizedBox(width: 8),
              Text(
                savedLabel,
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyChapter extends StatelessWidget {
  const _EmptyChapter({required this.controller});
  final WorkbenchController controller;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('从第一句开始。', style: TextStyle(fontSize: 24)),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            final name = await askText(context, '新建章节', initial: '第一章');
            if (name != null && context.mounted) {
              await uiAction(context, () => controller.createChapter(name));
            }
          },
          icon: const Icon(InkIcons.add),
          label: const Text('新建章节'),
        ),
      ],
    ),
  );
}

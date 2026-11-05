import 'package:flutter/material.dart';
import '../../app/ui_actions.dart';
import '../appearance/theme_presets.dart';
import '../recovery/recovery_panel.dart';
import '../works/work_models.dart';
import 'workbench_controller.dart';
import '../../app/ink_icons.dart';

typedef _DirectoryEntry = ({
  WorkVolume volume,
  ChapterRecord? chapter,
  bool isHeader,
});

class ChapterSidebar extends StatefulWidget {
  const ChapterSidebar({super.key, required this.controller, this.width = 224});
  final WorkbenchController controller;
  final double width;
  @override
  State<ChapterSidebar> createState() => _ChapterSidebarState();
}

class _ChapterSidebarState extends State<ChapterSidebar> {
  final _collapsed = <String>{};
  WorkbenchController get c => widget.controller;

  Future<void> _newChapter(String volumeId) async {
    final title = await askText(
      context,
      '新建章节',
      initial: '第${c.liveChapters.length + 1}章',
    );
    if (title != null && mounted) {
      await uiAction(context, () => c.createChapter(title, volumeId: volumeId));
      if (mounted) setState(() => _collapsed.remove(volumeId));
    }
  }

  Future<void> _newVolume() async {
    final title = await askText(
      context,
      '新建卷',
      initial: '第${c.work!.manifest.volumes.length + 1}卷',
    );
    if (title == null || !mounted) return;
    await uiAction(context, () async {
      final volume = await c.work!.createVolume(title);
      if (!mounted) return;
      setState(() {
        _collapsed.addAll(
          c.work!.manifest.volumes
              .where((v) => v.id != volume.id)
              .map((v) => v.id),
        );
        _collapsed.remove(volume.id);
      });
      c.selectVolume(volume.id);
    });
  }

  Future<void> _volumeAction(WorkVolume volume, String action) async {
    if (action == 'chapter') {
      await _newChapter(volume.id);
      return;
    }
    if (action == 'rename') {
      final title = await askText(context, '重命名卷', initial: volume.title);
      if (title == null || !mounted) return;
      await uiAction(context, () async {
        await c.work!.renameVolume(volume.id, title);
        c.refresh();
      });
      return;
    }
    if (action == 'delete') {
      final target = c.work!.manifest.volumes.firstWhere(
        (v) => v.id != volume.id,
      );
      final confirm = await confirmAction(
        context,
        '删除“${volume.title}”？',
        '卷内章节将移到“${target.title}”，正文和回收站内容都会保留。',
        action: '删除卷，保留章节',
      );
      if (!confirm || !mounted) return;
      await uiAction(context, () async {
        await c.work!.deleteVolume(volume.id);
        c.refresh();
      });
      return;
    }
    final ids = c.work!.manifest.volumes.map((v) => v.id).toList();
    final index = ids.indexOf(volume.id);
    final target = index + (action == 'up' ? -1 : 1);
    if (target < 0 || target >= ids.length) return;
    ids.insert(target, ids.removeAt(index));
    await uiAction(context, () async {
      await c.work!.reorderVolumes(ids);
      c.refresh();
    });
  }

  Future<void> _moveChapter(ChapterRecord chapter) async {
    final current = c.work!.volumeForChapter(chapter.id);
    final target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移动章节到'),
        children: [
          for (final volume in c.work!.manifest.volumes.where(
            (v) => v.id != current,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, volume.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(InkIcons.folder, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(volume.title)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    await uiAction(context, () async {
      await c.work!.moveChapter(chapter.id, target);
      if (mounted) setState(() => _collapsed.remove(target));
      c.selectVolume(target);
    });
  }

  Future<void> _reorder(
    List<_DirectoryEntry> entries,
    int oldIndex,
    int newIndex,
  ) async {
    final chapter = entries[oldIndex].chapter;
    if (chapter == null) return;
    final remaining = [...entries]..removeAt(oldIndex);
    if (newIndex > oldIndex) newIndex--;
    newIndex = newIndex.clamp(1, remaining.length);
    var target = remaining.first.volume.id;
    for (var index = 0; index < newIndex; index++) {
      if (remaining[index].isHeader) target = remaining[index].volume.id;
    }
    final before =
        newIndex < remaining.length && remaining[newIndex].volume.id == target
        ? remaining[newIndex].chapter?.id
        : null;
    await uiAction(context, () async {
      await c.work!.moveChapter(chapter.id, target, beforeChapterId: before);
      if (mounted) setState(() => _collapsed.remove(target));
      c.selectVolume(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    final work = c.work!;
    final entries = <_DirectoryEntry>[];
    for (final volume in work.manifest.volumes) {
      entries.add((volume: volume, chapter: null, isHeader: true));
      if (_collapsed.contains(volume.id)) continue;
      final chapters = c.liveChapters
          .where((chapter) => work.volumeForChapter(chapter.id) == volume.id)
          .toList();
      if (chapters.isEmpty) {
        entries.add((volume: volume, chapter: null, isHeader: false));
      }
      for (final chapter in chapters) {
        entries.add((volume: volume, chapter: chapter, isHeader: false));
      }
    }
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: .92),
        border: Border(right: BorderSide(color: colors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 16, 20),
            child: Row(
              children: [
                Icon(InkIcons.book, size: 20, color: colors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    work.manifest.title,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 1, color: colors.line),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('目录', style: TextStyle(fontSize: 16)),
                ),
                PopupMenuButton<String>(
                  tooltip: '新建卷或章节',
                  onSelected: (action) => action == 'volume'
                      ? _newVolume()
                      : _newChapter(c.activeVolumeId!),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'volume', child: Text('新建卷')),
                    PopupMenuItem(value: 'chapter', child: Text('新建章节')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(InkIcons.add, size: 14),
                        SizedBox(width: 8),
                        Text('新建', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: entries.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorder(entries, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final entry = entries[index];
                if (entry.isHeader) return _volumeRow(entry.volume);
                if (entry.chapter == null) {
                  return Padding(
                    key: ValueKey('empty-${entry.volume.id}'),
                    padding: const EdgeInsets.only(left: 24, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _newChapter(entry.volume.id),
                        icon: const Icon(InkIcons.add, size: 16),
                        label: const Text('新建章节'),
                      ),
                    ),
                  );
                }
                return _chapterRow(entry.chapter!, index);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Center(
              child: TextButton.icon(
                onPressed: () => showTrash(context, c),
                icon: const Icon(InkIcons.trash, size: 18),
                label: Text(
                  '回收站',
                  style: TextStyle(color: colors.muted, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeRow(WorkVolume volume) {
    final colors = InkPalette.of(context);
    final volumes = c.work!.manifest.volumes;
    final index = volumes.indexWhere((v) => v.id == volume.id);
    final count = c.liveChapters
        .where((chapter) => c.work!.volumeForChapter(chapter.id) == volume.id)
        .length;
    return Material(
      key: ValueKey('volume-${volume.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (!_collapsed.add(volume.id)) _collapsed.remove(volume.id);
          });
          c.selectVolume(volume.id);
        },
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _collapsed.contains(volume.id) ? 0 : .25,
                duration: c.appearance.animationsEnabled
                    ? const Duration(milliseconds: 120)
                    : Duration.zero,
                child: Icon(
                  InkIcons.chevronRight,
                  size: 12,
                  color: colors.muted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  volume.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.activeVolumeId == volume.id
                        ? colors.accent
                        : colors.ink,
                  ),
                ),
              ),
              Text(
                '$count 章',
                style: TextStyle(fontSize: 11, color: colors.muted),
              ),
              PopupMenuButton<String>(
                tooltip: '卷操作',
                icon: Icon(InkIcons.more, size: 16, color: colors.muted),
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'chapter', child: Text('新建章节')),
                  const PopupMenuItem(value: 'rename', child: Text('重命名卷')),
                  PopupMenuItem(
                    value: 'up',
                    enabled: index > 0,
                    child: const Text('上移一卷'),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: index < volumes.length - 1,
                    child: const Text('下移一卷'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: volumes.length > 1,
                    child: const Text('删除卷，保留章节'),
                  ),
                ],
                onSelected: (action) => _volumeAction(volume, action),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chapterRow(ChapterRecord chapter, int index) {
    final colors = InkPalette.of(context);
    final selected = chapter.id == c.activeChapterId;
    return Padding(
      key: ValueKey('chapter-${chapter.id}'),
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? colors.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        child: InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: () => uiAction(context, () => c.selectChapter(chapter.id)),
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                const SizedBox(width: 26),
                Tooltip(
                  message: '拖动调整章节位置',
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(
                      InkIcons.chapter,
                      size: 18,
                      color: selected ? colors.accent : colors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Tooltip(
                    message: chapter.title,
                    child: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '章节操作',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  icon: Icon(InkIcons.more, color: colors.muted),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(
                      value: 'move',
                      enabled: c.work!.manifest.volumes.length > 1,
                      child: const Text('移动到其他卷'),
                    ),
                    const PopupMenuItem(value: 'history', child: Text('历史版本')),
                    const PopupMenuItem(value: 'trash', child: Text('移入回收站')),
                  ],
                  onSelected: (action) async {
                    if (action == 'rename') {
                      final title = await askText(
                        context,
                        '重命名章节',
                        initial: chapter.title,
                      );
                      if (title != null && mounted) {
                        await uiAction(context, () async {
                          await c.work!.renameChapter(chapter.id, title);
                          c.refresh();
                        });
                      }
                    } else if (action == 'move') {
                      await _moveChapter(chapter);
                    } else if (action == 'history') {
                      await showHistory(context, c, chapter.id);
                    } else {
                      await uiAction(context, () => c.trashRecord(chapter.id));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

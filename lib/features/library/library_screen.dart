import '../updates/update_dialog.dart';
import 'package:flutter/material.dart';
import '../../app/ui_actions.dart';
import '../../core/typography.dart';
import '../appearance/theme_presets.dart';
import '../appearance/study_surface.dart';
import '../workbench/workbench_controller.dart';
import '../transfer/transfer_dialogs.dart';
import 'create_work_dialog.dart';
import 'book_cover.dart';
import '../works/work_repository.dart';
import '../../app/ink_icons.dart';
import '../preferences/device_preferences.dart';

const _bookCoverHeight = 180.0;
const _bookInfoHeight = 48.0;

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.controller});
  final WorkbenchController controller;

  static Future<void> createNew(
    BuildContext context,
    WorkbenchController controller,
  ) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => CreateWorkDialog(controller: controller),
  );

  static Future<void> openExisting(
    BuildContext context,
    WorkbenchController controller,
  ) => uiAction(context, () async {
    final root = await controller.services.pickWorkDirectory();
    if (root == null) return;
    final bookmark = await controller.services.bookmark(root);
    await controller.openWork(root, bookmark: bookmark);
  });

  static Future<void> editWork(
    BuildContext context,
    WorkbenchController controller,
    RecentWork entry,
  ) => uiAction(context, () async {
    final root = await controller.services.resolveDirectory(
      entry.path,
      entry.bookmark,
    );
    final snapshot = await WorkRepository.open(root);
    if (snapshot.manifest.workId != entry.workId) {
      throw const FormatException('作品身份已变化，请重新打开作品');
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CreateWorkDialog(
        controller: controller,
        editingWork: snapshot,
        entry: entry,
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    final current = controller.work;
    final savedEntry = current == null
        ? null
        : controller.preferences.recentWorks
                  .where((entry) => entry.path == current.root.path)
                  .firstOrNull ??
              RecentWork(
                path: current.root.path,
                workId: current.manifest.workId,
                title: current.manifest.title,
              );
    final currentEntry = current == null
        ? null
        : savedEntry!
              .withCover(current.manifest.coverFile)
              .withDetails(current.manifest.details);
    final recentWorks = controller.preferences.recentWorks
        .where((recent) => recent.path != current?.root.path)
        .toList();
    return StudySurface(
      settings: controller.appearance,
      color: colors.background.withValues(alpha: .92),
      child: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(48, 72, 48, 80),
                children: [
                  Text('书架', style: TextStyle(fontSize: 34, color: colors.ink)),
                  const SizedBox(height: 12),
                  Text(
                    '让故事，从这里继续。',
                    style: TextStyle(fontSize: 17, color: colors.muted),
                  ),
                  const SizedBox(height: 30),
                  if (controller.preferences.libraryRootPath == null)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.paper,
                        border: Border.all(color: colors.line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('先设置作品书库', style: TextStyle(fontSize: 21)),
                          const SizedBox(height: 12),
                          Text(
                            '选择或新建一个保存作品的文件夹。以后每本作品都会在这里生成独立文件夹，只需设置一次。',
                            style: TextStyle(color: colors.muted, height: 1.8),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: () => uiAction(context, () async {
                                  await controller.chooseLibraryRoot();
                                }),
                                icon: const Icon(InkIcons.folderOpen),
                                label: const Text('选择书库文件夹'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    openExisting(context, controller),
                                child: const Text('打开已有作品'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: () => createNew(context, controller),
                          icon: const Icon(InkIcons.add, size: 18),
                          label: const Text('新建作品'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => openExisting(context, controller),
                          icon: const Icon(InkIcons.folderOpen, size: 18),
                          label: const Text('打开作品文件夹'),
                        ),
                      ],
                    ),
                  if (current != null) ...[
                    const SizedBox(height: 36),
                    Text(
                      '当前作品',
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      key: const ValueKey('current-work-card'),
                      color: colors.paper,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: colors.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        height: 196,
                        child: Row(
                          children: [
                            BookCover(
                              entry: currentEntry!,
                              services: controller.services,
                              width: 196 / 1.5,
                              height: 196,
                              borderRadius: BorderRadius.zero,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            current.manifest.title,
                                            style: const TextStyle(
                                              fontSize: 21,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (current
                                                  .manifest
                                                  .details
                                                  .tags
                                                  .isNotEmpty ||
                                              current
                                                      .manifest
                                                      .details
                                                      .audience !=
                                                  '不限') ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              [
                                                if (current
                                                        .manifest
                                                        .details
                                                        .audience !=
                                                    '不限')
                                                  current
                                                      .manifest
                                                      .details
                                                      .audience,
                                                ...current
                                                    .manifest
                                                    .details
                                                    .tags,
                                              ].join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colors.muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                          if (controller.activeChapter !=
                                              null) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              '上次写到 · ${controller.activeChapter!.title}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: colors.muted,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                          if (current
                                              .manifest
                                              .details
                                              .synopsis
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            _WorkSynopsis(
                                              text: current
                                                  .manifest
                                                  .details
                                                  .synopsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    OutlinedButton.icon(
                                      onPressed: controller.hideLibrary,
                                      icon: const Icon(InkIcons.edit),
                                      label: const Text('继续写作'),
                                    ),
                                    const SizedBox(width: 8),
                                    _WorkItemMenu(
                                      controller: controller,
                                      entry: currentEntry,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 36),
                  if (current == null && recentWorks.isEmpty)
                    Text(
                      controller.preferences.libraryRootPath == null
                          ? '选好书库后，就可以开始写第一部作品。'
                          : '作品保存在所选书库中，离线也能安心写作。',
                      style: TextStyle(color: colors.muted, height: 1.8),
                    ),
                  if (recentWorks.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            current == null ? '最近作品' : '其他作品',
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                        ),
                        for (final view in LibraryView.values)
                          IconButton(
                            tooltip: view == LibraryView.list ? '列表视图' : '卡片视图',
                            isSelected:
                                controller.preferences.libraryView == view,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(32, 32),
                              fixedSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              backgroundColor:
                                  controller.preferences.libraryView == view
                                  ? colors.selection
                                  : Colors.transparent,
                              foregroundColor:
                                  controller.preferences.libraryView == view
                                  ? colors.accent
                                  : colors.muted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                            onPressed: () => controller.updateLibraryView(view),
                            icon: Icon(
                              view == LibraryView.list
                                  ? InkIcons.list
                                  : InkIcons.grid,
                              size: 16,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (controller.preferences.libraryView == LibraryView.list)
                      for (final entry in recentWorks) ...[
                        _WorkListItem(controller: controller, entry: entry),
                        Divider(height: 1, color: colors.line),
                      ]
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final count = ((constraints.maxWidth + 20) / 152)
                              .floor()
                              .clamp(1, 4);
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            itemCount: recentWorks.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: count,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 20,
                                  mainAxisExtent:
                                      _bookCoverHeight +
                                      _bookInfoHeight +
                                      (recentWorks.any(
                                            (entry) => entry
                                                .details
                                                .synopsis
                                                .isNotEmpty,
                                          )
                                          ? 44
                                          : 0),
                                ),
                            itemBuilder: (_, index) => _WorkCard(
                              controller: controller,
                              entry: recentWorks[index],
                            ),
                          );
                        },
                      ),
                  ],
                ],
              ),
            ),
          ),
          if (controller.preferences.libraryRootPath case final String path)
            Positioned(
              bottom: 16,
              right: 24,
              left: 24,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  key: const ValueKey('library-location'),
                  constraints: const BoxConstraints(maxWidth: 540),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(InkIcons.folder, size: 14, color: colors.muted),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '书库位置 · $path',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _openRecent(
  BuildContext context,
  WorkbenchController controller,
  RecentWork entry,
) => uiAction(context, () async {
  final root = await controller.services.resolveDirectory(
    entry.path,
    entry.bookmark,
  );
  if (!await root.exists()) {
    if (!context.mounted) return;
    final choose = await confirmAction(
      context,
      '作品文件夹暂不可访问',
      '最近记录会保留。可以重新选择这个作品的文件夹。',
      action: '重新定位',
    );
    if (choose && context.mounted) {
      await LibraryScreen.openExisting(context, controller);
    }
    return;
  }
  await controller.openWork(
    root,
    bookmark: entry.bookmark,
    chapterId: entry.chapterId,
  );
});

class _WorkSynopsis extends StatelessWidget {
  const _WorkSynopsis({required this.text, this.fontSize = 13});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: InkPalette.of(context).muted,
      fontSize: fontSize,
      height: 1.6,
    ),
  );
}

class _WorkListItem extends StatelessWidget {
  const _WorkListItem({required this.controller, required this.entry});
  final WorkbenchController controller;
  final RecentWork entry;

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openRecent(context, controller, entry),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Row(
            children: [
              BookCover(entry: entry, services: controller.services, width: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 19),
                    ),
                    if (entry.details.synopsis.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _WorkSynopsis(text: entry.details.synopsis),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      entry.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _WorkItemMenu(controller: controller, entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkCard extends StatelessWidget {
  const _WorkCard({required this.controller, required this.entry});
  final WorkbenchController controller;
  final RecentWork entry;

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    return Material(
      key: ValueKey('work-card-${entry.workId}'),
      color: colors.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openRecent(context, controller, entry),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookCover(
                entry: entry,
                services: controller.services,
                width: constraints.maxWidth,
                height: _bookCoverHeight,
                borderRadius: BorderRadius.zero,
              ),
              SizedBox(
                height: _bookInfoHeight,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _WorkItemMenu(controller: controller, entry: entry),
                    ],
                  ),
                ),
              ),
              if (entry.details.synopsis.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _WorkSynopsis(
                    text: entry.details.synopsis,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryActionsMenu extends StatelessWidget {
  const LibraryActionsMenu({super.key, required this.controller});
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '书库管理',
    offset: const Offset(0, 6),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'location',
        child: Text(
          controller.preferences.libraryRootPath == null ? '设置书库位置' : '更改书库位置',
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'restore', child: Text('从备份恢复作品')),
      const PopupMenuItem(value: 'trash', child: Text('作品回收站')),
      if (controller.updates != null) ...[
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'updates', child: Text('关于与更新')),
      ],
    ],
    onSelected: (action) async {
      if (action == 'updates') {
        await showAppUpdates(context, controller.updates!);
      } else if (action == 'location') {
        await uiAction(context, () async {
          await controller.chooseLibraryRoot();
        });
      } else if (action == 'restore') {
        await restoreBackup(context, controller);
      } else {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => _WorkTrashDialog(controller: controller),
        );
      }
    },
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '书库管理',
            style: TextStyle(
              fontFamily: inkFontFamily,
              fontFamilyFallback: inkFontFallback,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 8),
          Icon(InkIcons.more, size: 16),
        ],
      ),
    ),
  );
}

class _WorkItemMenu extends StatelessWidget {
  const _WorkItemMenu({required this.controller, required this.entry});
  final WorkbenchController controller;
  final RecentWork entry;

  @override
  Widget build(BuildContext context) {
    final colors = InkPalette.of(context);
    PopupMenuItem<String> item(
      String value,
      String label,
      IconData icon, {
      bool destructive = false,
    }) => PopupMenuItem(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: destructive
                ? Theme.of(context).colorScheme.error
                : colors.muted,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: destructive
                  ? Theme.of(context).colorScheme.error
                  : colors.ink,
            ),
          ),
        ],
      ),
    );
    return PopupMenuButton<String>(
      tooltip: '${entry.title} 的作品操作',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 12),
      constraints: const BoxConstraints(minWidth: 168, maxWidth: 180),
      elevation: 3,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      icon: const Icon(InkIcons.more, size: 18),
      itemBuilder: (_) => [
        item('edit', '编辑作品', InkIcons.edit),
        const PopupMenuDivider(height: 8),
        item('trash', '删除作品', InkIcons.trash, destructive: true),
      ],
      onSelected: (action) async {
        if (action == 'edit') {
          await LibraryScreen.editWork(context, controller, entry);
        } else {
          final confirmed = await confirmAction(
            context,
            '删除《${entry.title}》？',
            '作品将从本机书架移入“作品回收站”。稿件文件保留在原位置，可在“书库管理”中恢复。',
            action: '移入回收站',
          );
          if (confirmed && context.mounted) {
            await uiAction(context, () => controller.trashWork(entry));
          }
        }
      },
    );
  }
}

class _WorkTrashDialog extends StatelessWidget {
  const _WorkTrashDialog({required this.controller});
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('作品回收站'),
    content: SizedBox(
      width: 520,
      height: 340,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '仅管理本机书架，稿件文件保留在原位置。',
              style: TextStyle(
                color: InkPalette.of(context).muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: controller.preferences.trashedWorks.isEmpty
                  ? const Center(child: Text('没有已删除的作品'))
                  : ListView(
                      children: [
                        for (final entry in controller.preferences.trashedWorks)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(InkIcons.book, size: 20),
                            title: Text(entry.title),
                            subtitle: Text(
                              entry.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: TextButton(
                              onPressed: () => uiAction(
                                context,
                                () => controller.restoreWork(entry),
                              ),
                              child: const Text('恢复到书架'),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}

import 'package:flutter/material.dart';
import '../../app/ui_actions.dart';
import '../../core/typography.dart';
import '../appearance/theme_presets.dart';
import '../recovery/recovery_panel.dart';
import '../transfer/transfer_dialogs.dart';
import 'workbench_controller.dart';
import '../updates/update_dialog.dart';
import '../../app/ink_icons.dart';

class WorkActionsMenu extends StatelessWidget {
  const WorkActionsMenu({super.key, required this.controller});
  final WorkbenchController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = InkPalette.of(context);
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(colors.paper),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(4),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.line),
        ),
      ),
    );
    return MenuButtonTheme(
      data: MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(200, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          iconSize: const WidgetStatePropertyAll(18),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: inkFontFamily,
              fontFamilyFallback: inkFontFallback,
              fontSize: 14,
            ),
          ),
        ),
      ),
      child: MenuAnchor(
        consumeOutsideTap: true,
        onOpen: () => c.setWorkMenuOpen(true),
        onClose: () => c.setWorkMenuOpen(false),
        style: menuStyle.copyWith(alignment: Alignment.bottomLeft),
        alignmentOffset: const Offset(0, 6),
        menuChildren: [
          MenuItemButton(
            leadingIcon: const Icon(InkIcons.save),
            onPressed: () => uiAction(context, () async {
              await c.flushAll();
            }),
            child: const Text('保存全部'),
          ),
          const Divider(height: 12),
          SubmenuButton(
            menuStyle: menuStyle,
            leadingIcon: const Icon(InkIcons.transfer),
            menuChildren: [
              MenuItemButton(
                onPressed: () => importText(context, c),
                child: const Text('导入 TXT 章节'),
              ),
              MenuItemButton(
                onPressed: () => exportText(context, c),
                child: const Text('导出当前章节'),
              ),
              MenuItemButton(
                onPressed: () => exportText(context, c, wholeWork: true),
                child: const Text('导出整部作品'),
              ),
            ],
            child: const Text('导入与导出'),
          ),
          SubmenuButton(
            menuStyle: menuStyle,
            leadingIcon: const Icon(InkIcons.backup),
            menuChildren: [
              MenuItemButton(
                onPressed: () => createBackup(context, c),
                child: const Text('完整作品备份'),
              ),
              MenuItemButton(
                onPressed: () => restoreBackup(context, c),
                child: const Text('从备份恢复作品'),
              ),
            ],
            child: const Text('备份与恢复'),
          ),
          const Divider(height: 12),
          MenuItemButton(
            leadingIcon: const Icon(InkIcons.history),
            onPressed: c.activeChapterId == null
                ? null
                : () => showHistory(context, c, c.activeChapterId!),
            child: const Text('当前章节历史'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(InkIcons.sync),
            onPressed: () => showConflicts(context, c),
            child: const Text('处理同步冲突'),
          ),
          if (c.updates case final updates?)
            MenuItemButton(
              onPressed: () => showAppUpdates(context, updates),
              child: const Text('关于与更新'),
            ),
          MenuItemButton(
            leadingIcon: const Icon(InkIcons.trash),
            onPressed: () => showTrash(context, c),
            child: const Text('作品回收站'),
          ),
        ],
        // Keep Tooltip and MenuAnchor portal identifiers on separate AX nodes.
        builder: (context, menu, child) => Semantics(
          container: true,
          child: Tooltip(
            message: '作品操作',
            child: TextButton.icon(
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              iconAlignment: IconAlignment.end,
              icon: const Icon(InkIcons.more, size: 16),
              label: const Text('作品'),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../features/library/library_screen.dart';
import '../features/transfer/transfer_dialogs.dart';
import '../features/workbench/workbench_controller.dart';
import 'ui_actions.dart';

final inkFlowNavigatorKey = GlobalKey<NavigatorState>();

Future<void> dispatchDesktopAction(WorkbenchController c, String action) async {
  if (c.busy) return;
  final context = inkFlowNavigatorKey.currentContext;
  if (context == null) return;
  switch (action) {
    case 'newWork':
      await LibraryScreen.createNew(context, c);
    case 'open':
      await LibraryScreen.openExisting(context, c);
    case 'newChapter':
      if (c.work == null) {
        await LibraryScreen.createNew(context, c);
        return;
      }
      final title = await askText(
        context,
        '新建章节',
        initial: '第${c.liveChapters.length + 1}章',
      );
      if (title != null && context.mounted) {
        await uiAction(context, () => c.createChapter(title));
      }
    case 'save':
      await c.flushAll();
    case 'import':
      if (c.work != null) await importText(context, c);
    case 'exportChapter':
      if (c.work != null) await exportText(context, c);
    case 'backup':
      if (c.work != null) await createBackup(context, c);
    case 'restore':
      await restoreBackup(context, c);
  }
}

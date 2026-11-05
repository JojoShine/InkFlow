import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/preferences/preferences_store.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/notes/notes_panel.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/workbench/chapter_sidebar.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-panels-');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '测试',
    );
    await work.createChapter('这是一个需要完整查看的很长很长的章节标题');
    await c.openWork(work.root);
    c.setPanel(NoteKind.outline);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  testWidgets(
    'dragging both panels preserves editor and restores widths after restart',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      await tester.pumpAndSettle();
      final editor = tester.state(find.byType(NovelEditor));
      final left = tester.getSize(find.byType(ChapterSidebar)).width;
      final right = tester.getSize(find.byType(NotesPanel)).width;
      final leftHandle = find.byKey(const ValueKey('resize-chapters'));
      expect(leftHandle, findsOneWidget);
      await tester.drag(leftHandle, const Offset(100, 0));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('resize-notes')),
        const Offset(-80, 0),
      );
      await tester.pump();
      final widenedLeft = tester.getSize(find.byType(ChapterSidebar)).width;
      final widenedRight = tester.getSize(find.byType(NotesPanel)).width;
      expect(widenedLeft, greaterThan(left + 50));
      expect(widenedRight, greaterThan(right + 30));
      expect(tester.state(find.byType(NovelEditor)), same(editor));
      await tester.runAsync(c.persistPreferences);
      final restored = await tester.runAsync(
        () => PreferencesStore(c.dataRoot).load(),
      );
      expect(restored!.toJson()['chapterPanelWidth'], widenedLeft);
      expect(restored.toJson()['notesPanelWidth'], widenedRight);
      tester.view.physicalSize = const Size(960, 800);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(NovelEditor)).width,
        greaterThanOrEqualTo(540),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

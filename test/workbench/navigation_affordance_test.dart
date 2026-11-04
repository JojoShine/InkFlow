import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/ink_icons.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/notes/notes_panel.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-affordance-');
    final work = await WorkRepository.create(
      Directory('${root.path}/book'),
      '微光',
    );
    await work.createChapter('第一章', text: '让故事继续。');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
    await c.notes!.create(NoteKind.outline);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });

  testWidgets(
    'navigation keeps one compact disclosure and preserves menu, notes and pane actions',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      final editor = tester.state(find.byType(NovelEditor));
      final value = c.session.controller.value;
      expect(find.byIcon(InkIcons.chevronDown), findsNothing);
      final disclosure = find.byIcon(InkIcons.chevronRight);
      expect(disclosure, findsOneWidget);
      expect(tester.widget<Icon>(disclosure).size, lessThanOrEqualTo(12));
      expect(
        find.descendant(
          of: find.byType(NotesPanel),
          matching: find.byIcon(InkIcons.chevronRight),
        ),
        findsNothing,
      );
      await tester.tap(find.text('第一卷'));
      await tester.pumpAndSettle();
      expect(
        find.text('第一章').hitTestable(),
        findsOneWidget,
      ); // Editor heading remains.
      await tester.tap(find.text('第一卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('新建卷或章节'));
      await tester.pumpAndSettle();
      expect(find.text('新建卷'), findsOneWidget);
      expect(find.text('新建章节'), findsOneWidget);
      await tester.tapAt(const Offset(600, 500));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新大纲'));
      await tester.pumpAndSettle();
      expect(find.text('大纲标题'), findsOneWidget);
      await tester.tap(find.byTooltip('收起创作资料'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesPanel), findsNothing);
      await tester.tap(find.byTooltip('展开创作资料'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesPanel), findsOneWidget);
      expect(tester.state(find.byType(NovelEditor)), same(editor));
      expect(c.session.controller.value, value);
      await tester.tap(find.byTooltip('作品操作'));
      await tester.pumpAndSettle();
      expect(find.text('保存全部'), findsOneWidget);
      await tester.tapAt(const Offset(600, 500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

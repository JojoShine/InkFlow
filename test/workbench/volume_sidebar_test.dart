import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/notes/notes_panel.dart';
import 'package:inkflow/features/workbench/chapter_sidebar.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

Future<void> waitForDirectory(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) return;
  }
  fail('Directory operation did not finish');
}

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-directory-');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '测试作品',
    );
    await work.createChapter('第一章', text: '原文');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async => root.delete(recursive: true));

  Future<void> showWorkbench(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(InkFlowApp(controller: c));
  }

  Future<void> nameAndConfirm(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      name,
    );
    await tester.tap(find.text('确定'));
  }

  testWidgets(
    'new volumes receive new chapters and a chapter can be moved through the directory menu',
    (tester) async {
      await showWorkbench(tester);
      final firstVolume = c.work!.manifest.volumes.single.id;
      expect(find.text('第一卷'), findsOneWidget);
      await tester.tap(find.byTooltip('新建卷或章节'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建卷'));
      await nameAndConfirm(tester, '远行卷');
      await waitForDirectory(
        tester,
        () => c.work!.manifest.volumes.length == 2,
      );
      final secondVolume = c.work!.manifest.volumes.last.id;
      expect(c.activeVolumeId, secondVolume);
      await tester.tap(find.byTooltip('新建卷或章节'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '新建章节'));
      await nameAndConfirm(tester, '远行第一章');
      await waitForDirectory(tester, () => c.activeChapter?.title == '远行第一章');
      final chapterId = c.activeChapterId!;
      expect(c.work!.volumeForChapter(chapterId), secondVolume);
      await tester.tap(find.byTooltip('章节操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到其他卷'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SimpleDialog),
          matching: find.text('第一卷'),
        ),
      );
      await waitForDirectory(
        tester,
        () => c.work!.volumeForChapter(chapterId) == firstVolume,
      );
      expect(c.activeChapterId, chapterId);
      expect(c.activeVolumeId, firstVolume);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets(
    'trash is centered in the sidebar and the notes panel can be collapsed and reopened',
    (tester) async {
      await showWorkbench(tester);
      final trash = find
          .ancestor(
            of: find.text('回收站'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          )
          .first;
      expect(
        tester.getCenter(trash).dx,
        closeTo(tester.getCenter(find.byType(ChapterSidebar)).dx, 1),
      );
      await tester.tap(find.byTooltip('收起创作资料'));
      await tester.pumpAndSettle();
      expect(c.panel, isNull);
      expect(find.byType(NotesPanel), findsNothing);
      await tester.tap(find.byTooltip('展开创作资料'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesPanel), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}

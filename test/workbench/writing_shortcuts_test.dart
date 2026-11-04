import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-shortcuts-');
    final work = await WorkRepository.create(
      Directory('${root.path}/book'),
      '测试',
    );
    await work.createChapter('第一章', text: '　原稿  ');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
    c.session.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 3,
    );
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  testWidgets(
    'footer shortcuts open tools directly and fit both sidebars without recreating the editor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [960.0, 1100.0, 1360.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(InkFlowApp(controller: c));
        await tester.pumpAndSettle();
        final editor = tester.state(find.byType(NovelEditor));
        final stats = tester.getRect(find.widgetWithText(TextButton, '码字统计'));
        final format = tester.getRect(find.widgetWithText(TextButton, '排版'));
        final share = tester.getRect(find.widgetWithText(TextButton, '分享'));
        expect(format.left, greaterThan(stats.right));
        expect(share.left, greaterThan(format.right));
        expect(format.center.dy, stats.center.dy);
        expect(share.center.dy, stats.center.dy);
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(TextButton, '排版'));
        await tester.pumpAndSettle();
        expect(find.text('排版整理'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '分享'));
        await tester.pumpAndSettle();
        expect(find.text('片段分享'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(NovelEditor)), same(editor));
        expect(c.session.controller.text, '　原稿  ');
        expect(
          c.session.controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 3),
        );
        await tester.tap(find.byTooltip('作品操作'));
        await tester.pumpAndSettle();
        expect(find.text('排版整理'), findsNothing);
        expect(find.text('片段分享'), findsNothing);
        await tester.tapAt(const Offset(500, 500));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

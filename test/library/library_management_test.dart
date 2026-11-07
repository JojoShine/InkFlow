import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) return;
  }
  fail('Library update did not finish');
}

void main() {
  testWidgets(
    'book menus confirm deletion, cancel safely and restore through library management',
    (tester) async {
      late Directory root;
      final c = (await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('inkflow-library-ui-');
        final controller = WorkbenchController(
          Directory('${root.path}/device'),
        );
        await controller.initialize();
        final work = await WorkRepository.create(
          Directory('${root.path}/book'),
          '春日来信',
        );
        await work.createChapter('第一章', text: '我在雨中等你。');
        await controller.openWork(work.root);
        await controller.showLibrary();
        return controller;
      }))!;
      c.preferences = c.preferences.copyWith(
        libraryRootPath: '${root.path}/很长的书库位置',
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      final location = tester.getRect(
        find.byKey(const ValueKey('library-location')),
      );
      final currentCard = tester.getRect(
        find.byKey(const ValueKey('current-work-card')),
      );
      expect(location.right, closeTo(currentCard.right, 1));
      expect(location.bottom, closeTo(784, 1));
      await tester.tap(find.byTooltip('删除作品：春日来信'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.preferences.trashedWorks, isEmpty);
      expect(c.work, isNotNull);
      await tester.tap(find.byTooltip('删除作品：春日来信'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移入回收站'));
      await waitFor(tester, () => c.work == null);
      expect(find.text('春日来信'), findsNothing);
      await tester.tap(find.byTooltip('书库管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作品回收站'));
      await tester.pumpAndSettle();
      expect(find.text('春日来信'), findsOneWidget);
      await tester.tap(find.text('恢复到书架'));
      await waitFor(tester, () => c.preferences.trashedWorks.isEmpty);
      expect(find.text('没有已删除的作品'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('春日来信'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}

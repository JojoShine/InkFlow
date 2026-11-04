import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-menu-');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '测试作品',
    );
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async => root.delete(recursive: true));

  for (final size in [const Size(960, 640), const Size(1360, 1000)]) {
    testWidgets(
      'work menu stays below its button and submenus stay on screen at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(InkFlowApp(controller: c));
        final anchor = find.byTooltip('作品操作');
        final anchorBottom = tester.getRect(anchor).bottom;
        await tester.tap(anchor);
        await tester.pumpAndSettle();
        expect(find.text('导入与导出'), findsOneWidget);
        expect(find.text('导入 TXT 章节'), findsNothing);
        expect(
          tester.getRect(find.text('保存全部')).top,
          greaterThanOrEqualTo(anchorBottom),
        );
        expect(
          tester.getRect(find.text('作品回收站')).bottom,
          lessThan(size.height),
        );
        await tester.tap(find.text('导入与导出'));
        await tester.pumpAndSettle();
        for (final text in ['导入 TXT 章节', '导出当前章节', '导出整部作品']) {
          final rect = tester.getRect(find.text(text));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThanOrEqualTo(anchorBottom));
          expect(rect.bottom, lessThan(size.height));
        }
        await tester.tapAt(Offset(size.width / 2, size.height - 120));
        await tester.pumpAndSettle();
        expect(find.text('保存全部'), findsNothing);
        expect(find.text('导入 TXT 章节'), findsNothing);
        expect(c.workMenuOpen, isFalse);

        for (final entry in [
          ('新建卷或章节', '新建卷'),
          ('卷操作', '重命名卷'),
          ('章节操作', '重命名'),
        ]) {
          await tester.tap(find.byTooltip(entry.$1).first);
          await tester.pumpAndSettle();
          expect(find.text(entry.$2), findsOneWidget);
          await tester.tapAt(Offset(size.width / 2, size.height - 120));
          await tester.pumpAndSettle();
          expect(find.text(entry.$2), findsNothing);
        }
        expect(c.session.controller.text, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      },
    );
  }
}

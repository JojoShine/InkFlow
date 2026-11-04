import 'dart:io';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-icons-');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '图标检查',
    );
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async => root.delete(recursive: true));
  testWidgets('workbench, menus and appearance use one outline icon family', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1360, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(InkFlowApp(controller: c));
    void checkIcons() {
      final icons = find
          .byType(Icon)
          .evaluate()
          .map((e) => (e.widget as Icon).icon)
          .whereType<IconData>()
          .toList();
      expect(icons.length, greaterThan(5));
      for (final icon in icons) {
        if (icon == Icons.eco_outlined) continue;
        expect(
          icon.fontFamily,
          CupertinoIcons.iconFont,
          reason: 'mixed icon ${icon.codePoint}',
        );
        expect(icon.fontPackage, CupertinoIcons.iconFontPackage);
      }
    }

    checkIcons();
    await tester.tap(find.byTooltip('作品操作'));
    await tester.pumpAndSettle();
    checkIcons();
    await tester.tapAt(const Offset(600, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    checkIcons();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}

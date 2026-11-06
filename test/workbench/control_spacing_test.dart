import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/ink_icons.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-control-spacing-');
    final work = await WorkRepository.create(
      Directory('${root.path}/book'),
      '春日来信',
    );
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });

  testWidgets(
    'creation label has breathing room and footer controls fit inside its edges',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      final trigger = find.byTooltip('新建卷或章节');
      final label = tester.getRect(
        find.descendant(of: trigger, matching: find.text('新建')),
      );
      final add = tester.getRect(
        find.descendant(of: trigger, matching: find.byIcon(InkIcons.add)),
      );
      expect(label.left - add.right, greaterThanOrEqualTo(8));
      final stats = find.widgetWithText(TextButton, '码字统计');
      final footer = tester.getRect(
        find.ancestor(of: stats, matching: find.byType(Row)).first,
      );
      final button = tester.getRect(stats);
      expect(button.top - footer.top, greaterThanOrEqualTo(4));
      expect(footer.bottom - button.bottom, greaterThanOrEqualTo(4));
      for (final width in [960.0, 1360.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpAndSettle();
        final statsRect = tester.getRect(stats);
        final soundRect = tester.getRect(find.widgetWithText(TextButton, '键音'));
        final status = tester.getRect(find.text('已保存到本机'));
        expect(soundRect.left - statsRect.right, greaterThanOrEqualTo(8));
        expect(status.left - soundRect.right, greaterThanOrEqualTo(16));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'work popup clears the continue action at regular and narrow window widths',
    (tester) async {
      await tester.runAsync(c.showLibrary);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [1100.0, 960.0]) {
        tester.view.physicalSize = Size(width, 800);
        await tester.pumpWidget(InkFlowApp(controller: c));
        await tester.pumpAndSettle();
        final action = tester.getRect(
          find.widgetWithText(OutlinedButton, '继续写作'),
        );
        final continueButton = find.widgetWithText(OutlinedButton, '继续写作');
        final arrow = tester.getRect(
          find.descendant(of: continueButton, matching: find.byType(Icon)),
        );
        expect(
          arrow.left,
          greaterThan(tester.getRect(find.text('继续写作')).right),
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('current-work-card')))
              .height,
          greaterThanOrEqualTo(160),
        );
        final trigger = tester.getRect(find.byTooltip('春日来信 的作品操作'));
        await tester.tap(find.byTooltip('春日来信 的作品操作'));
        await tester.pumpAndSettle();
        final item = find.widgetWithText(PopupMenuItem<String>, '删除作品');
        final menu = tester.getRect(
          find.ancestor(of: item, matching: find.byType(Material)).first,
        );
        expect(menu.top - action.bottom, greaterThanOrEqualTo(8));
        expect(menu.top - trigger.bottom, greaterThanOrEqualTo(8));
        expect(menu.overlaps(action), isFalse);
        expect(menu.right, lessThanOrEqualTo(width - 8));
        await tester.tapAt(const Offset(20, 200));
        await tester.pumpAndSettle();
        expect(item, findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

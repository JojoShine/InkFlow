import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/ai/ai_panel.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  testWidgets('AI tab is reachable and a quick action only fills a draft', (
    tester,
  ) async {
    final fixture = await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('ai-panel');
      final work = await WorkRepository.create(
        Directory('${root.path}/work'),
        '小说',
      );
      await work.createChapter('一', text: '原稿');
      final c = WorkbenchController(Directory('${root.path}/device'));
      await c.initialize();
      await c.openWork(work.root);
      return (root, c);
    });
    final (root, c) = fixture!;
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(InkFlowApp(controller: c));
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.byType(AiPanel), findsOneWidget);
    expect(find.text('配置 AI'), findsOneWidget);
    await tester.tap(find.text('整理思路'));
    await tester.pump();
    expect(c.ai.draft, isNotEmpty);
    expect(c.ai.turns, isEmpty);
    expect(c.session.controller.text, '原稿');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}

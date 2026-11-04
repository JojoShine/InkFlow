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
    root = await Directory.systemTemp.createTemp('inkflow-focus-');
    c = WorkbenchController(Directory('${root.path}/device'));
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '测试作品',
    );
    await work.createChapter('第一章', text: '窗外下着雨。');
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async => root.delete(recursive: true));
  testWidgets(
    'focus mode preserves the editor and accepts continued writing immediately',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      final before = tester.state(find.byType(NovelEditor));
      c.session.controller.selection = TextSelection.collapsed(
        offset: c.session.controller.text.length,
      );
      await tester.tap(find.text('专注'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(NovelEditor)), same(before));
      final input = find.descendant(
        of: find.byType(NovelEditor),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
      expect(
        tester.getRect(find.text('第一章').first).left,
        closeTo(tester.getRect(input).left, 1),
      );
      tester.testTextInput.enterText('窗外下着雨。我继续写下这个故事。');
      await tester.pump();
      await tester.tap(find.text('退出专注'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(NovelEditor)), same(before));
      expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
      expect(c.session.controller.text, '窗外下着雨。我继续写下这个故事。');
      expect(await tester.runAsync(c.flushAll), isTrue);
      final text = await tester.runAsync(
        () async => (await c.work!.readChapter(c.activeChapterId!)).text,
      );
      expect(text, c.session.controller.text);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}

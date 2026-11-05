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
    root = await Directory.systemTemp.createTemp('inkflow-notice-');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '测试',
    );
    await work.createChapter('第一章', text: '继续输入中文');
    await c.openWork(work.root);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  testWidgets('save notices preserve the editor, focus and selection', (
    tester,
  ) async {
    await tester.pumpWidget(InkFlowApp(controller: c));
    await tester.pumpAndSettle();
    final editor = tester.state(find.byType(NovelEditor));
    final input = find.descendant(
      of: find.byType(NovelEditor),
      matching: find.byType(EditableText),
    );
    tester.widget<EditableText>(input).focusNode.requestFocus();
    c.session.controller.selection = const TextSelection.collapsed(offset: 3);
    await tester.pump();
    c.notice = '无法安全替换作品文件';
    c.notifyListeners();
    await tester.pump();
    expect(tester.state(find.byType(NovelEditor)), same(editor));
    expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
    expect(c.session.controller.selection.baseOffset, 3);
    c.dismissNotice();
    await tester.pump();
    expect(tester.state(find.byType(NovelEditor)), same(editor));
    expect(tester.widget<EditableText>(input).focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

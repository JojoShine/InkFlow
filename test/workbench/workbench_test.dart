import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-workbench-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<(WorkbenchController, String, String)> create() async {
    final directory = Directory('${root.path}/作品');
    final work = await WorkRepository.create(directory, '测试作品');
    final first = await work.createChapter('第一章', text: '第一章正文');
    final second = await work.createChapter('第二章', text: '第二章正文');
    final c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(directory);
    return (c, first.id, second.id);
  }

  test('restart resumes last chapter and cursor', () async {
    final (c, _, second) = await create();
    await c.selectChapter(second);
    c.session.controller.selection = const TextSelection.collapsed(offset: 3);
    await c.flushAll();
    c.dispose();
    final restored = WorkbenchController(Directory('${root.path}/device'));
    await restored.initialize();
    expect(restored.activeChapterId, second);
    expect(restored.session.controller.selection.extentOffset, 3);
    restored.dispose();
  });

  test('focus mode restores the previous sidebar state', () async {
    final (c, _, _) = await create();
    c.toggleLeft();
    c.setPanel(NoteKind.character);
    c.toggleFocus();
    expect(c.leftVisible, isFalse);
    expect(c.panel, isNull);
    c.toggleFocus();
    expect(c.leftVisible, isFalse);
    expect(c.panel, NoteKind.character);
    c.dispose();
  });

  test('whole-work count keeps edits after switching away from a chapter', () async {
    final (c, _, second) = await create();
    c.session.controller.text = '1234567890';
    await c.selectChapter(second);
    expect(c.totalWords, 15);
    c.dispose();
  });

  test('synchronizer conflict copies are surfaced without replacing the canonical text', () async {
    final (c, first, _) = await create();
    final copy = File('${c.work!.root.path}/chapters/$first (conflicted copy).txt');
    await copy.writeAsString('另一个设备的内容');
    await c.scanSyncCopies();
    expect(c.notice, contains('同步副本'));
    final conflicts = await Directory('${c.work!.root.path}/.inkflow/conflicts')
      .list(recursive: true).where((entry) => entry.path.endsWith('/info.json')).toList();
    expect(conflicts, hasLength(1));
    expect(await File('${c.work!.root.path}/chapters/$first.txt').readAsString(), '第一章正文');
    expect(await copy.readAsString(), '另一个设备的内容');
    c.dispose();
  });

  test('external change does not replace the active unsaved draft', () async {
    final (c, first, _) = await create();
    c.session.controller.text = '本机草稿';
    await File(
      '${c.work!.root.path}/chapters/$first.txt',
    ).writeAsString('外部新稿');
    expect(await c.flushAll(), isFalse);
    expect(c.session.controller.text, '本机草稿');
    expect(
      await File('${c.work!.root.path}/chapters/$first.txt').readAsString(),
      '外部新稿',
    );
    c.dispose();
  });

  testWidgets('workbench fits a laptop and theme changes preserve composing', (
    tester,
  ) async {
    final (c, _, _) =
        await tester.runAsync(create) ?? (throw StateError('setup failed'));
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(InkFlowApp(controller: c));
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    expect(find.text('InkFlow'), findsNothing);
    expect(find.text('大纲'), findsOneWidget);
    expect(tester.takeException(), isNull);
    c.session.controller.value = const TextEditingValue(
      text: '正在输入中文',
      selection: TextSelection.collapsed(offset: 6),
      composing: TextRange(start: 4, end: 6),
    );
    final before = c.session.controller.value;
    c.updateAppearance(const AppearanceSettings(presetId: 'night'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(c.session.controller.value, before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/typing_sound/typing_sound_settings.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/transfer/backup_service.dart';

Future<T> finishOperation<T>(WidgetTester tester, Future<T> operation) async {
  var completed = false;
  final pending = operation.whenComplete(() => completed = true);
  for (var i = 0; i < 500 && !completed; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(completed, isTrue, reason: 'The storage operation should finish');
  return pending;
}

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-writing-tools-');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '微光',
    );
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'independent restored works keep separate typing statistics despite shared chapter IDs',
    () async {
      final original = c.work!;
      c.session.applyNativeValue({
        'text': '甲',
        'selectionBase': 1,
        'selectionExtent': 1,
      });
      await c.flushAll();
      final backup = File('${root.path}/book.zip');
      await BackupService.create(original, backup);
      final restored = await BackupService.restore(
        backup,
        Directory('${root.path}/restored'),
      );
      expect(restored.manifest.chapterIds, original.manifest.chapterIds);
      await c.openWork(restored.root);
      expect(c.session.statistics.words, 0);
      c.session.applyNativeValue({
        'text': '甲乙',
        'selectionBase': 2,
        'selectionExtent': 2,
      });
      expect(c.session.statistics.words, 1);
      await c.openWork(original.root);
      expect(c.session.statistics.words, 1);
      c.dispose();
    },
  );

  testWidgets(
    'writing tools show names and metrics; sound changes preserve the working editor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      final editor = tester.state(find.byType(NovelEditor));
      c.session.applyNativeValue({
        'text': '你好',
        'selectionBase': 2,
        'selectionExtent': 2,
      });
      await finishOperation(tester, c.session.flush());
      await tester.pump();
      await tester.tap(find.text('码字统计'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      for (final text in ['微光', '第一章', '码字速率', '码字时长']) {
        expect(
          find.descendant(of: dialog, matching: find.text(text)),
          findsOneWidget,
        );
      }
      expect(find.textContaining('本次手动输入 2 字'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('键音'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<TypingSoundPreset>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('机械键盘').last);
      await tester.pumpAndSettle();
      expect(c.preferences.typingSound.preset, TypingSoundPreset.mechanical);
      var previews = 0;
      c.session.previewTypingSound = () async {
        previews++;
      };
      await tester.tap(find.text('试听'));
      await tester.pump();
      expect(previews, 1);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(NovelEditor)), same(editor));
      expect(c.session.controller.text, '你好');
      expect(c.session.controller.selection.baseOffset, 2);
      expect(
        find.descendant(
          of: find.byType(NovelEditor),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await finishOperation(tester, c.flushAll());
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}

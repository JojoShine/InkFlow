import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/editor/formatting_dialog.dart';
import 'package:inkflow/features/editor/text_formatting.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-format-dialog-');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    final work = await WorkRepository.create(
      Directory('${root.path}/book'),
      '测试',
    );
    await work.createChapter('第一章', text: '　第一段  \n\n\n第二段');
    await c.openWork(work.root);
  });
  tearDown(() async {
    c.dispose();
    await root.delete(recursive: true);
  });
  test(
    'work switch during history IO invalidates formatting before replacement',
    () async {
      final original = c.work!;
      final other = await WorkRepository.create(
        Directory('${root.path}/other-history'),
        '另一作品',
      );
      final text = c.session.controller.text;
      final key = c.workKey, id = c.activeChapterId!;
      c.history.invalidate(key, id);
      c.session.synchronizeNative = (_) async {
        Timer.run(() => c.work = other);
      };
      try {
        await expectLater(
          c.applyFormatting(
            TextFormatting.preview(text),
            expectedWorkKey: key,
            expectedChapterId: id,
          ),
          throwsFormatException,
        );
        expect(c.session.controller.text, text);
      } finally {
        c.session.synchronizeNative = null;
        c.work = original;
      }
    },
  );
  testWidgets(
    'preview identity is fixed before a switch to another work with identical text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFormatting(context, c),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final original = c.session.controller.text;
      await tester.runAsync(() async {
        final other = await WorkRepository.create(
          Directory('${root.path}/other'),
          '另一作品',
        );
        await other.createChapter('同内容章节', text: original);
        await c.openWork(other.root);
      });
      await tester.runAsync(() async {
        await tester.tap(find.text('应用排版'));
        await c.prepareToQuit();
      });
      await tester.pumpAndSettle();
      expect(c.session.controller.text, original);
      expect(find.text('章节或正文已变化，请重新打开排版预览'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'preview cancellation is read-only; apply has history and undo rejects new typing',
    (tester) async {
      final source = c.session.controller.text;
      final id = c.activeChapterId!, key = c.workKey;
      c.session.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showFormatting(context, c),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('整理前'), findsOneWidget);
      expect(find.text('整理后'), findsOneWidget);
      expect(c.session.controller.text, source);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(c.session.controller.text, source);
      expect(c.session.controller.selection.extentOffset, 6);
      await tester.runAsync(() async {
        final preview = TextFormatting.preview(source);
        await c.applyFormatting(
          preview,
          expectedWorkKey: key,
          expectedChapterId: id,
        );
        expect(c.session.controller.text, '第一段\n\n第二段');
        final history = await c.history.list(key, id);
        expect(
          await Future.wait(
            history.map((e) async => utf8.decode(await c.history.read(e))),
          ),
          contains(source),
        );
        await c.applyFormatting(
          preview,
          expectedWorkKey: key,
          expectedChapterId: id,
          undo: true,
        );
        expect(c.session.controller.text, source);
        c.session.controller.text = '新的写作';
        await expectLater(
          c.applyFormatting(
            preview,
            expectedWorkKey: key,
            expectedChapterId: id,
          ),
          throwsFormatException,
        );
        expect(c.session.controller.text, '新的写作');
        await expectLater(
          c.applyFormatting(
            TextFormatting.preview('新的写作'),
            expectedWorkKey: 'different',
            expectedChapterId: id,
          ),
          throwsFormatException,
        );
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(c.flushAll);
    },
  );
}

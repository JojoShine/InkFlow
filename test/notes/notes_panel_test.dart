import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/notes/notes_panel.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-notes-ui-');
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

  test(
    'external refresh finishes safely when the workbench is disposed',
    () async {
      final refresh = c.checkExternal();
      c.dispose();
      await refresh;
    },
  );

  Future<void> showPanel(
    WidgetTester tester,
    NoteKind kind, {
    double width = 320,
  }) async {
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: c,
        builder: (context, _) => MaterialApp(
          theme: inkTheme(c.appearance),
          home: Scaffold(
            body: NotesPanel(controller: c, kind: kind, width: width),
          ),
        ),
      ),
    );
  }

  for (final kind in NoteKind.values) {
    testWidgets('${kind.name} list displays all edited text without clipping', (
      tester,
    ) async {
      final note = await tester.runAsync(() => c.notes!.create(kind));
      const title = '这是一个需要换行后才能完整阅读的长标题';
      final body = List.generate(
        20,
        (i) => '第${i + 1}段：这部分内容应当完整展示。',
      ).join('\n');
      final summary = kind == NoteKind.character
          ? List.generate(5, (i) => '角色简介第${i + 1}行。').join('\n')
          : '';
      c.notes!.update(
        note!.copyWith(title: title, summary: summary, body: body),
      );
      expect(await tester.runAsync(c.notes!.flush), isTrue);
      final following = await tester.runAsync(() => c.notes!.create(kind));
      c.notes!.update(following!.copyWith(title: '下一条记录'));
      expect(await tester.runAsync(c.notes!.flush), isTrue);
      await showPanel(tester, kind, width: 260);
      await tester.pump();
      for (final content in [title, if (summary.isNotEmpty) summary, body]) {
        final text = find.text(content);
        expect(text, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
      }
      await tester.scrollUntilVisible(find.text('下一条记录'), 200);
      await tester.pumpAndSettle();
      expect(find.text('下一条记录').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }

  testWidgets(
    'role fields are explicit and edits survive returning to the list',
    (tester) async {
      await tester.runAsync(() => c.notes!.create(NoteKind.character));
      await showPanel(tester, NoteKind.character);
      await tester.tap(find.text('新角色'));
      await tester.pump();
      expect(find.text('返回角色列表'), findsOneWidget);
      expect(find.text('角色名称'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('note-title')), '林晚');
      await tester.enterText(
        find.byKey(const ValueKey('note-summary')),
        '小镇邮递员',
      );
      await tester.enterText(
        find.byKey(const ValueKey('note-body')),
        '习惯收集旧信封。',
      );
      await tester.tap(find.text('返回角色列表'));
      await tester.pump();
      await tester.tap(find.text('林晚'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-summary')))
            .controller!
            .text,
        '小镇邮递员',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-body')))
            .controller!
            .text,
        '习惯收集旧信封。',
      );
      expect(await tester.runAsync(c.notes!.flush), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets(
    'creating a child opens that child with its parent already selected',
    (tester) async {
      final parent = await tester.runAsync(
        () => c.notes!.create(NoteKind.outline),
      );
      c.notes!.update(parent!.copyWith(title: '第一幕'));
      await tester.runAsync(c.notes!.flush);
      await showPanel(tester, NoteKind.outline);
      await tester.tap(find.text('第一幕'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('新建子大纲'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建子大纲'));
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        if (find.byKey(const ValueKey('note-title')).evaluate().isNotEmpty &&
            tester
                    .widget<TextField>(find.byKey(const ValueKey('note-title')))
                    .controller!
                    .text ==
                '新大纲') {
          break;
        }
      }
      final child = c.notes!
          .ofKind(NoteKind.outline)
          .singleWhere((n) => n.id != parent.id);
      expect(child.parentId, parent.id);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('note-title')))
            .controller!
            .text,
        '新大纲',
      );
      expect(find.text('上一级大纲'), findsOneWidget);
      expect(find.text('第一幕'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/core/platform/desktop_services.dart';
import 'package:inkflow/features/library/book_cover.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'book_cover_test.dart' show tinyPng;
import 'library_management_test.dart' show waitFor;

class CoverServices extends DesktopServices {
  Uint8List? image;
  @override
  Future<Uint8List?> pickCoverImage() async => image;
}

void main() {
  testWidgets(
    'cards display covers; compact menu imports, cancels and removes without switching manuscripts',
    (tester) async {
      late Directory root;
      final services = CoverServices();
      final c = (await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('inkflow-library-view-');
        final controller = WorkbenchController(
          Directory('${root.path}/device'),
          services: services,
        );
        await controller.initialize();
        for (final name in ['春', '夏']) {
          final work = await WorkRepository.create(
            Directory('${root.path}/$name'),
            name,
            details: WorkDetails(synopsis: '$name 的故事简介'),
          );
          await work.createChapter('第一章', text: '正在写的正文');
          await controller.openWork(work.root);
        }
        controller.preferences = controller.preferences.copyWith(
          libraryRootPath: root.path,
        );
        await controller.showLibrary();
        return controller;
      }))!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      expect(find.byType(BookCover), findsNWidgets(2));
      final currentCover = find.byType(BookCover).first;
      expect(tester.getSize(currentCover).width, greaterThanOrEqualTo(100));
      final currentCardBounds = tester.getRect(
        find.byKey(const ValueKey('current-work-card')),
      );
      final currentCoverBounds = tester.getRect(currentCover);
      expect(currentCoverBounds.left, closeTo(currentCardBounds.left, .1));
      expect(currentCoverBounds.top, closeTo(currentCardBounds.top, .1));
      expect(currentCoverBounds.bottom, closeTo(currentCardBounds.bottom, .1));
      expect(
        currentCoverBounds.width / currentCoverBounds.height,
        closeTo(2 / 3, .01),
      );
      expect(find.byTooltip('夏 的故事简介'), findsNothing);

      expect(find.byKey(const ValueKey('library-card-grid')), findsOneWidget);
      expect(find.text('春 的故事简介'), findsOneWidget);
      expect(find.byTooltip('春 的故事简介'), findsNothing);
      expect(find.byTooltip(c.preferences.recentWorks.last.path), findsNothing);
      final card = find.byKey(
        ValueKey('work-card-${c.preferences.recentWorks.last.workId}'),
      );
      expect(tester.getSize(card).height, lessThanOrEqualTo(275));
      final defaultCover = find.descendant(
        of: card,
        matching: find.byType(BookCover),
      );
      final coverBounds = tester.getRect(defaultCover);
      final cardBounds = tester.getRect(card);
      expect(coverBounds.left, closeTo(cardBounds.left, .1));
      expect(coverBounds.right, closeTo(cardBounds.right, .1));
      expect(coverBounds.top, closeTo(cardBounds.top, .1));
      expect(coverBounds.width / coverBounds.height, closeTo(2 / 3, .01));
      final otherRoot = c.preferences.recentWorks.last.path;
      final selection = c.session.controller.selection;

      Future<void> edit(String title) async {
        await tester.ensureVisible(find.byTooltip('$title 的作品操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('$title 的作品操作'));
        await tester.pumpAndSettle();
        final delete = find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> && widget.value == 'trash',
        );
        expect(tester.getSize(delete).height, lessThanOrEqualTo(38));
        expect(find.text('设置封面'), findsNothing);
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is PopupMenuItem<String> && widget.value == 'edit',
          ),
        );
        await waitFor(
          tester,
          () => find
              .byKey(const ValueKey('create-work-title'))
              .evaluate()
              .isNotEmpty,
        );
      }

      services.image = tinyPng;
      await edit('春');
      final titleField = find.byKey(const ValueKey('create-work-title'));
      final synopsisField = find.byKey(const ValueKey('create-work-synopsis'));
      expect(tester.widget<TextField>(titleField).controller!.text, '春');
      expect(
        tester.widget<TextField>(synopsisField).controller!.text,
        '春 的故事简介',
      );
      await tester.enterText(titleField, '未保存的修改');
      await tester.tap(find.text('选择封面'));
      await waitFor(tester, () => find.text('更换封面').evaluate().isNotEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final untouched = await tester.runAsync(
        () => WorkRepository.open(Directory(otherRoot)),
      );
      expect(untouched!.manifest.title, '春');
      expect(untouched.manifest.coverFile, isNull);

      await edit('春');
      await tester.enterText(titleField, '春 · 修订');
      await tester.tap(find.text('女频'));
      await tester.tap(find.text('科幻'));
      await tester.ensureVisible(synopsisField);
      await tester.pumpAndSettle();
      await tester.enterText(synopsisField, '修订后的故事简介');
      await tester.ensureVisible(find.text('选择封面'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择封面'));
      await waitFor(tester, () => find.text('更换封面').evaluate().isNotEmpty);
      await tester.tap(find.text('保存修改'));
      await waitFor(
        tester,
        () =>
            c.preferences.recentWorks.last.title == '春 · 修订' &&
            !c.busy &&
            find.byType(AlertDialog).evaluate().isEmpty,
      );
      final edited = await tester.runAsync(
        () => WorkRepository.open(Directory(otherRoot)),
      );
      expect(edited!.manifest.details.audience, '女频');
      expect(edited.manifest.details.tags, ['科幻']);
      expect(edited.manifest.details.synopsis, '修订后的故事简介');
      expect(edited.manifest.coverFile, isNotNull);
      expect(c.work!.manifest.title, '夏');
      expect(c.session.controller.text, '正在写的正文');
      expect(c.session.controller.selection, selection);
      await waitFor(tester, () => find.byType(Image).evaluate().isNotEmpty);
      expect(find.byKey(const ValueKey('library-card-grid')), findsOneWidget);
      expect(find.text('修订后的故事简介'), findsOneWidget);
      await edit('春 · 修订');
      expect(find.text('更换封面'), findsOneWidget);
      expect(tester.widget<TextField>(titleField).controller!.text, '春 · 修订');
      await tester.tap(find.text('移除'));
      await tester.tap(find.text('保存修改'));
      await waitFor(
        tester,
        () =>
            c.preferences.recentWorks.last.coverFile == null &&
            !c.busy &&
            find.byType(AlertDialog).evaluate().isEmpty,
      );
      final other = c.preferences.recentWorks.last;
      c.preferences = c.preferences.copyWith(
        recentWorks: [
          c.preferences.recentWorks.first,
          RecentWork(
            path: other.path,
            workId: other.workId,
            title: '很长的中文作品名称以及很长的英文书名 A very long book title',
          ),
        ],
      );
      tester.view.physicalSize = const Size(960, 800);
      await tester.runAsync(() async {
        c.notifyListeners();
        await c.persistPreferences();
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        c.notifyListeners();
        await c.persistPreferences();
      });
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(c.preferencesStore.load))!.libraryView,
        LibraryView.list,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}

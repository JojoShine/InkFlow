import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/readability.dart';
import 'package:inkflow/features/library/book_cover.dart';
import 'package:inkflow/features/library/library_screen.dart';
import 'package:inkflow/features/preferences/device_preferences.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_models.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController controller;

  Future<void> showLibrary(WidgetTester tester) async {
    root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('inkflow-shelf-search-'),
    ))!;
    controller = WorkbenchController(
      Directory('${root.path}/device'),
      openRepository: (_) => throw StateError('Search must not load works'),
    );
    controller.preferences = controller.preferences.copyWith(
      libraryRootPath: root.path,
      recentWorks: List.generate(
        19,
        (i) => RecentWork(
          path: '${root.path}/book-$i',
          workId: i.toRadixString(16).padLeft(32, 'a'),
          title: '作品${(i + 1).toString().padLeft(2, '0')}',
          details: WorkDetails(
            synopsis: i == 16 ? 'Moon PORT 的故事' : '一段故事简介',
            tags: i == 17 ? ['科幻'] : [],
          ),
        ),
      ),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    });
    await tester.pumpWidget(
      AnimatedBuilder(
        animation: controller,
        builder: (_, _) => MaterialApp(
          theme: inkTheme(controller.appearance),
          home: Scaffold(body: LibraryScreen(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> displayedTitles(WidgetTester tester) => tester
      .widgetList<BookCover>(find.byType(BookCover))
      .map((cover) => cover.entry.title)
      .toList();

  testWidgets('eight compact cards per page use one fixed pagination footer', (
    tester,
  ) async {
    await showLibrary(tester);
    expect(find.byTooltip('列表视图'), findsNothing);
    expect(find.byTooltip('卡片视图'), findsNothing);
    expect(displayedTitles(tester), List.generate(8, (i) => '作品0${i + 1}'));
    expect(find.text('共 19 本 · 每页 8 本'), findsOneWidget);
    final pagerBounds = tester.getRect(
      find.byKey(const ValueKey('library-pagination')),
    );
    await tester.tap(find.byKey(const ValueKey('library-next-page')));
    await tester.pumpAndSettle();
    expect(displayedTitles(tester).first, '作品09');
    expect(displayedTitles(tester).last, '作品16');
    final card = find.byKey(
      ValueKey('work-card-${controller.preferences.recentWorks[8].workId}'),
    );
    final cover = find.descendant(of: card, matching: find.byType(BookCover));
    final coverSize = tester.getSize(cover);
    expect(coverSize.width / coverSize.height, closeTo(2 / 3, .01));
    expect(coverSize.width, lessThanOrEqualTo(160));
    expect(tester.getSize(card).height, lessThanOrEqualTo(305));
    expect(tester.getRect(cover).left, closeTo(tester.getRect(card).left, .1));
    expect(
      tester.getRect(cover).right,
      closeTo(tester.getRect(card).right, .1),
    );
    await tester.tap(find.byKey(const ValueKey('library-next-page')));
    await tester.pumpAndSettle();
    expect(displayedTitles(tester), ['作品17', '作品18', '作品19']);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('library-next-page')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('library-pagination'))),
      pagerBounds,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop cards fit five or six books with compact spacing', (
    tester,
  ) async {
    await showLibrary(tester);
    for (final width in [960.0, 1100.0, 1360.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpAndSettle();
      final rects = find
          .byType(BookCover)
          .evaluate()
          .map((element) => tester.getRect(find.byWidget(element.widget)))
          .toList();
      final firstRow = rects
          .where((rect) => (rect.top - rects.first.top).abs() < 1)
          .toList();
      expect(firstRow.length, inInclusiveRange(5, 6), reason: 'width=$width');
      for (var i = 1; i < firstRow.length; i++) {
        expect(firstRow[i].left - firstRow[i - 1].right, closeTo(16, .1));
      }
      for (final rect in rects) {
        expect(rect.width, lessThanOrEqualTo(160));
        expect(rect.width / rect.height, closeTo(2 / 3, .01));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'search uses all cached metadata and resets paging without opening a book',
    (tester) async {
      await showLibrary(tester);
      final search = find.byKey(const ValueKey('library-search'));
      await tester.tap(find.byKey(const ValueKey('library-next-page')));
      await tester.pumpAndSettle();
      await tester.enterText(search, ' moon port ');
      await tester.pumpAndSettle();
      expect(displayedTitles(tester), ['作品17']);
      expect(find.text('共 1 本 · 每页 8 本'), findsOneWidget);
      await tester.enterText(search, '科幻');
      await tester.pumpAndSettle();
      expect(displayedTitles(tester), ['作品18']);
      await tester.enterText(search, '作品19');
      await tester.pumpAndSettle();
      expect(displayedTitles(tester), ['作品19']);
      await tester.enterText(search, '没有这本书');
      await tester.pumpAndSettle();
      expect(displayedTitles(tester), isEmpty);
      expect(find.text('没有找到匹配的作品'), findsOneWidget);
      await tester.tap(find.byTooltip('清空搜索'));
      await tester.pumpAndSettle();
      expect(displayedTitles(tester).first, '作品01');
      expect(displayedTitles(tester).length, 8);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search includes the current book and handles a narrow shelf', (
    tester,
  ) async {
    await showLibrary(tester);
    controller.work = await tester.runAsync(
      () => WorkRepository.create(Directory('${root.path}/current'), '正在写的书'),
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('current-work-card')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('library-search')), '正在写');
    await tester.pumpAndSettle();
    expect(displayedTitles(tester), ['正在写的书']);
    expect(find.byKey(const ValueKey('current-work-card')), findsNothing);
    tester.view.physicalSize = const Size(480, 800);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('card surfaces stay close to each theme with readable text', (
    tester,
  ) async {
    await showLibrary(tester);
    for (final preset in inkThemePresets) {
      controller.updateAppearance(controller.appearance.select(preset.id));
      await tester.pumpAndSettle();
      final palette = InkPalette.from(controller.appearance);
      final card = tester.widget<Material>(
        find.byKey(
          ValueKey(
            'work-card-${controller.preferences.recentWorks.first.workId}',
          ),
        ),
      );
      final surface = Color.alphaBlend(card.color!, palette.background);
      expect(
        (surface.computeLuminance() - palette.background.computeLuminance())
            .abs(),
        lessThan(.035),
        reason: preset.id,
      );
      expect(
        colorContrast(palette.ink, surface),
        greaterThanOrEqualTo(4.5),
        reason: preset.id,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'production shelf keeps search and page during a library operation',
    (tester) async {
      await showLibrary(tester);
      controller.busy = false;
      await tester.pumpWidget(InkFlowApp(controller: controller));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('library-search'));
      await tester.enterText(search, '作品');
      await tester.tap(find.byKey(const ValueKey('library-next-page')));
      await tester.pumpAndSettle();
      controller.busy = true;
      controller.notifyListeners();
      await tester.pump();
      controller.busy = false;
      controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, '作品');
      expect(displayedTitles(tester).first, '作品09');
    },
  );

  testWidgets(
    'production shelf scrolls setup and current book in a short window',
    (tester) async {
      await showLibrary(tester);
      controller.work = await tester.runAsync(
        () => WorkRepository.create(Directory('${root.path}/current'), '当前作品'),
      );
      controller.preferences = DevicePreferences(
        recentWorks: controller.preferences.recentWorks,
      );
      controller.busy = false;
      tester.view.physicalSize = const Size(960, 640);
      await tester.pumpWidget(InkFlowApp(controller: controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('library-next-page')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byTooltip('作品01 的作品操作'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

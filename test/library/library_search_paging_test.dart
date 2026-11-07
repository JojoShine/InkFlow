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

  testWidgets('twelve smaller cards per page keep only pagination controls', (
    tester,
  ) async {
    await showLibrary(tester);
    expect(find.byTooltip('列表视图'), findsNothing);
    expect(find.byTooltip('卡片视图'), findsNothing);
    expect(
      displayedTitles(tester),
      List.generate(12, (i) => '作品${(i + 1).toString().padLeft(2, '0')}'),
    );
    expect(find.textContaining('每页'), findsNothing);
    final pagerBounds = tester.getRect(
      find.byKey(const ValueKey('library-pagination')),
    );
    await tester.tap(find.byKey(const ValueKey('library-next-page')));
    await tester.pumpAndSettle();
    expect(displayedTitles(tester).first, '作品13');
    expect(displayedTitles(tester).last, '作品19');
    expect(displayedTitles(tester).length, 7);
    final card = find.byKey(
      ValueKey('work-card-${controller.preferences.recentWorks[12].workId}'),
    );
    final cover = find.descendant(of: card, matching: find.byType(BookCover));
    final coverSize = tester.getSize(cover);
    expect(coverSize.width / coverSize.height, closeTo(2 / 3, .01));
    expect(coverSize.width, lessThanOrEqualTo(144));
    expect(tester.getSize(card).height, lessThanOrEqualTo(275));
    expect(tester.getRect(cover).left, closeTo(tester.getRect(card).left, .1));
    expect(
      tester.getRect(cover).right,
      closeTo(tester.getRect(card).right, .1),
    );

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
        expect(rect.width, lessThanOrEqualTo(144));
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
      expect(find.text('搜索结果 · 1 本'), findsOneWidget);
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
      expect(displayedTitles(tester).length, 12);
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
      expect(displayedTitles(tester).first, '作品13');
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
  testWidgets(
    'Chinese composition keeps focus when current book is filtered out',
    (tester) async {
      await showLibrary(tester);
      controller.work = await tester.runAsync(
        () => WorkRepository.create(Directory('${root.path}/ime'), '中文作品'),
      );
      controller.notifyListeners();
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('library-search'));
      await tester.showKeyboard(search);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'zhong',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        ),
      );
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: search, matching: find.byType(EditableText)),
      );
      expect(editable.widget.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(
        editable.widget.controller.value.composing,
        const TextRange(start: 0, end: 5),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '中文',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pumpAndSettle();
      expect(displayedTitles(tester), ['中文作品']);
      expect(editable.widget.focusNode.hasFocus, isTrue);
    },
  );

  testWidgets(
    'book menu stays inside its themed card and controls are compact',
    (tester) async {
      await showLibrary(tester);
      controller.updateAppearance(controller.appearance.select('forest'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        '作品',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byTooltip('清空搜索')).width,
        lessThanOrEqualTo(28),
      );
      final trigger = find.byTooltip('作品01 的作品操作');
      expect(tester.getSize(trigger).width, lessThanOrEqualTo(28));
      final bounds = tester.getRect(
        find.byKey(
          ValueKey(
            'work-card-${controller.preferences.recentWorks.first.workId}',
          ),
        ),
      );
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      final material = find
          .ancestor(
            of: find.widgetWithText(PopupMenuItem<String>, '删除作品'),
            matching: find.byType(Material),
          )
          .first;
      final menu = tester.getRect(material);
      expect(bounds.contains(menu.topLeft), isTrue);
      expect(bounds.contains(menu.bottomRight), isTrue);
      final color = tester.widget<Material>(material).color!;
      expect(
        (color.computeLuminance() -
                InkPalette.from(
                  controller.appearance,
                ).background.computeLuminance())
            .abs(),
        lessThan(.035),
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    },
  );
}

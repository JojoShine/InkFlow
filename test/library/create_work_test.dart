import 'dart:io';
import 'dart:typed_data';
import 'book_cover_test.dart' show tinyPng;
import 'package:inkflow/features/works/work_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/core/platform/desktop_services.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';

class ChoosingDirectory extends DesktopServices {
  ChoosingDirectory(this.directory);
  final Directory directory;
  bool cancelPicker = false;
  Uint8List? cover;
  @override
  Future<Uint8List?> pickCoverImage() async => cover;
  int pickerCalls = 0;
  @override
  Future<Directory?> pickWorkDirectory() async {
    pickerCalls++;
    return cancelPicker ? null : directory;
  }

  @override
  Future<String> bookmark(Directory directory) async =>
      'bookmark:${directory.path}';
  @override
  Future<Directory> resolveDirectory(String path, String bookmark) async =>
      Directory(path);
}

Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (condition()) return;
  }
  fail('The requested library operation did not finish');
}

void main() {
  late Directory root;
  late WorkbenchController c;
  late ChoosingDirectory services;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-create-');
    services = ChoosingDirectory(await Directory('${root.path}/作品书库').create());
    c = WorkbenchController(
      Directory('${root.path}/device'),
      services: services,
    );
    await c.initialize();
  });
  tearDown(() async => root.delete(recursive: true));

  Future<void> setUpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(InkFlowApp(controller: c));
    await tester.tap(find.text('选择书库文件夹'));
    await waitFor(tester, () => find.text('新建作品').evaluate().isNotEmpty);
  }

  Future<void> createWork(WidgetTester tester, String title) async {
    await tester.tap(find.text('新建作品'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-work-title')),
      title,
    );
    await tester.pump();
    await tester.tap(find.text('创建作品'));
    await waitFor(
      tester,
      () =>
          c.work?.manifest.title == title &&
          find.byType(AlertDialog).evaluate().isEmpty,
    );
  }

  testWidgets(
    'first use chooses a library once and every new work gets its own folder there',
    (tester) async {
      await tester.pumpWidget(InkFlowApp(controller: c));
      expect(find.text('选择书库文件夹'), findsOneWidget);
      expect(find.text('新建作品'), findsNothing);
      await setUpLibrary(tester);
      expect(c.work, isNull);
      expect(services.pickerCalls, 1);
      await createWork(tester, '春日来信');
      final first = c.work!.root;
      expect(c.activeChapter!.title, '第1章');
      expect(first.parent.path, services.directory.path);
      expect(services.pickerCalls, 1);
      final returning = c.showLibrary();
      await waitFor(tester, () => c.libraryVisible);
      await returning;
      await createWork(tester, '秋日回声');
      expect(c.work!.root.parent.path, services.directory.path);
      expect(c.work!.root.path, isNot(first.path));
      expect(services.pickerCalls, 1);
      final folders = await tester.runAsync(
        () => services.directory
            .list()
            .where((entry) => entry is Directory)
            .toList(),
      );
      expect(folders, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets(
    'restarting remembers the library and never asks for a per-book location',
    (tester) async {
      await setUpLibrary(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      c = WorkbenchController(
        Directory('${root.path}/device'),
        services: services,
      );
      await tester.runAsync(c.initialize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      expect(find.text('选择书库文件夹'), findsNothing);
      await createWork(tester, '重启后的故事');
      expect(c.work!.root.parent.path, services.directory.path);
      expect(services.pickerCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets('cancelling setup or a new work creates no book', (tester) async {
    services.cancelPicker = true;
    await tester.pumpWidget(InkFlowApp(controller: c));
    await tester.tap(find.text('选择书库文件夹'));
    await waitFor(tester, () => services.pickerCalls == 1);
    expect(find.text('新建作品'), findsNothing);
    expect(c.work, isNull);
    services.cancelPicker = false;
    await tester.tap(find.text('选择书库文件夹'));
    await waitFor(tester, () => find.text('新建作品').evaluate().isNotEmpty);
    await tester.tap(find.text('新建作品'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('create-work-title')),
      '暂时不创建',
    );
    services.cover = tinyPng;
    await tester.tap(find.text('选择封面'));
    await waitFor(tester, () => find.text('更换封面').evaluate().isNotEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(c.work, isNull);
    expect(services.pickerCalls, 2);
    expect(
      await tester.runAsync(() => services.directory.list().isEmpty),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets(
    'an unavailable library keeps the name and never silently writes elsewhere',
    (tester) async {
      await setUpLibrary(tester);
      await tester.runAsync(() => services.directory.delete(recursive: true));
      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-work-title')),
        '等待书库恢复',
      );
      await tester.pump();
      await tester.tap(find.text('创建作品'));
      await waitFor(
        tester,
        () => find.textContaining('书库文件夹暂不可访问').evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('create-work-title')))
            .controller!
            .text,
        '等待书库恢复',
      );
      expect(c.work, isNull);
      expect(services.pickerCalls, 1);
      expect(
        await tester.runAsync(
          () => Directory('${c.dataRoot.path}/works').exists(),
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
  testWidgets(
    'new work collects cover, audience, tags and synopsis and shows synopsis on the bookshelf',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1100, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      services.cover = tinyPng;
      await setUpLibrary(tester);
      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-work-title')),
        '来自未来的信',
      );
      await tester.tap(find.text('选择封面'));
      await waitFor(tester, () => find.text('更换封面').evaluate().isNotEmpty);
      await tester.tap(find.text('女频'));
      await tester.tap(find.text('悬疑'));
      await tester.tap(find.text('科幻'));
      final synopsis = find.byKey(const ValueKey('create-work-synopsis'));
      await tester.ensureVisible(synopsis);
      await tester.pumpAndSettle();
      await tester.enterText(synopsis, '雨停之前，她收到了一封来自未来的信。');
      await tester.tap(find.text('创建作品'));
      await waitFor(
        tester,
        () => c.work != null && find.byType(AlertDialog).evaluate().isEmpty,
      );
      expect(c.work!.manifest.details.audience, '女频');
      expect(c.work!.manifest.details.tags, ['悬疑', '科幻']);
      expect(c.work!.manifest.coverFile, isNotNull);
      final reopened = await tester.runAsync(
        () => WorkRepository.open(c.work!.root),
      );
      expect(reopened!.manifest.details.synopsis, '雨停之前，她收到了一封来自未来的信。');
      final showing = c.showLibrary();
      await waitFor(tester, () => c.libraryVisible);
      await showing;
      expect(find.text('雨停之前，她收到了一封来自未来的信。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );
}

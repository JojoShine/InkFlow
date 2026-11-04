import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/appearance_panel.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/workbench/work_actions_menu.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/works/work_repository.dart';
import 'package:inkflow/features/notes/note_models.dart';

void main() {
  final binding = _AccessibilityBinding();
  late Directory directory;
  late WorkbenchController c;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('inkflow-ax-');
    final work = await WorkRepository.create(
      Directory('${directory.path}/work'),
      '语义检查',
    );
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${directory.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
    await c.notes!.create(NoteKind.character);
  });
  tearDown(() async => directory.delete(recursive: true));
  testWidgets(
    'work menu tooltip and popup never serialize orphan AX nodes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      binding.tree.clear();
      binding.violations.clear();
      await tester.pumpWidget(
        MaterialApp(
          theme: inkTheme(const AppearanceSettings()),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: WorkActionsMenu(controller: c),
            ),
          ),
        ),
      );
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('作品')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(binding.violations, isEmpty);
      await tester.tap(find.text('作品'));
      await tester.pumpAndSettle();
      expect(find.text('保存全部'), findsOneWidget);
      expect(binding.violations, isEmpty);
      await mouse.moveTo(Offset.zero);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      c.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'directory, toolbar and notes remain reachable through hover and page changes',
    (tester) async {
      c.setPanel(NoteKind.character);
      tester.view.physicalSize = const Size(1360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      binding.tree.clear();
      binding.violations.clear();
      await tester.pumpWidget(InkFlowApp(controller: c));
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      for (final message in [
        'InkFlow',
        '返回书架',
        '收起章节',
        '收起创作资料',
        '新建卷或章节',
        '卷操作',
        '拖动调整章节位置',
        '章节操作',
        '作品操作',
      ]) {
        await mouse.moveTo(tester.getCenter(find.byTooltip(message).first));
        await tester.pump(const Duration(milliseconds: 700));
        expect(binding.violations, isEmpty, reason: message);
      }
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(seconds: 1));
      c.toggleFocus();
      await tester.pumpAndSettle();
      c.toggleFocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('新角色'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(600, 500));
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      await mouse.removePointer();
      await tester.tap(find.text('码字统计'));
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('键音'));
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      c.dispose();
    },
    // Exercise the shared desktop semantics with the Flutter editor fallback.
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'appearance dialog sliders keep every AX node connected',
    (tester) async {
      final semantics = tester.ensureSemantics();
      binding.tree.clear();
      binding.violations.clear();
      tester.view.physicalSize = const Size(1360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: inkTheme(c.appearance),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppearance(context, c),
                child: const Text('外观'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      final list = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      );
      // The growing gallery can leave sliders outside ListView's initial cache.
      final adjustable = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.slider == true &&
            widget.properties.label == '编辑区不透明度',
      );
      final opacitySlider = find.descendant(
        of: adjustable,
        matching: find.byType(CupertinoSlider),
      );
      await tester.scrollUntilVisible(adjustable, 200, scrollable: list);
      await Scrollable.ensureVisible(
        tester.element(opacitySlider),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      final sliderRect = tester.getRect(opacitySlider);
      await tester.tapAt(Offset(sliderRect.right - 24, sliderRect.center.dy));
      await tester.pumpAndSettle();
      final opacity = c.appearance.current.editorOpacity;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(c.appearance.current.editorOpacity, lessThan(opacity));
      final node = tester.getSemantics(adjustable);
      expect(
        node.getSemanticsData().hasAction(ui.SemanticsAction.increase),
        isTrue,
      );
      final beforeIncrease = c.appearance.current.editorOpacity;
      node.owner!.performAction(node.id, ui.SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(c.appearance.current.editorOpacity, greaterThan(beforeIncrease));
      expect(binding.violations, isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(binding.violations, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      semantics.dispose();
      c.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );
}

// Replay the native AX bridge's reachability contract on each serialized update.
// Inspecting only Flutter's paint-order semantics tree misses overlay grafting.
class _AccessibilityBinding extends AutomatedTestWidgetsFlutterBinding {
  final tree = <int, List<int>>{};
  final violations = <String>[];
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _UpdateRecorder(this);
}

class _UpdateRecorder extends Fake implements ui.SemanticsUpdateBuilder {
  _UpdateRecorder(this.binding);
  final _AccessibilityBinding binding;
  final updates = <int, List<int>>{};
  final labels = <int, String>{};
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      final id = args[#id] as int;
      updates[id] = List<int>.of(
        args[#childrenInTraversalOrder] as Iterable<int>,
      );
      labels[id] = args[#label] as String;
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    binding.tree.addAll(updates);
    final reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      for (final child in binding.tree[id] ?? <int>[]) {
        visit(child);
      }
    }

    visit(0);
    for (final id in updates.keys) {
      if (!reachable.contains(id)) {
        binding.violations.add(
          'AX node $id (${labels[id]}) is not reachable from root',
        );
      }
    }
    binding.tree.removeWhere((id, _) => !reachable.contains(id));
    return ui.SemanticsUpdateBuilder().build();
  }
}

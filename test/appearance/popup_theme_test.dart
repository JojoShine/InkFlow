import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/notes/note_models.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-popup-');
    final work = await WorkRepository.create(
      Directory('${root.path}/work'),
      '测试作品',
    );
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
    await c.notes!.create(NoteKind.character);
    c.setPanel(NoteKind.character);
  });
  tearDown(() async => root.delete(recursive: true));

  for (final preset in inkThemePresets.map((p) => p.id)) {
    testWidgets(
      'chapter, note and library menus use the current $preset surface',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1360, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        c.preferences = c.preferences.copyWith(
          appearance: AppearanceSettings(presetId: preset),
        );
        await tester.pumpWidget(InkFlowApp(controller: c));
        final paper = InkPalette.from(c.appearance).paper;
        void expectPopupSurface(String item) {
          final materials = find
              .ancestor(of: find.text(item), matching: find.byType(Material))
              .evaluate()
              .map((e) => e.widget as Material)
              .where((m) => m.type == MaterialType.card);
          expect(materials, hasLength(1));
          expect(materials.single.color, paper);
          expect(materials.single.surfaceTintColor, Colors.transparent);
        }

        await tester.tap(find.byTooltip('章节操作'));
        await tester.pumpAndSettle();
        expectPopupSurface('重命名');
        await tester.tapAt(const Offset(600, 500));
        await tester.pumpAndSettle();
        expect(find.text('重命名'), findsNothing);
        await tester.tap(find.text('新角色'));
        await tester.pump();
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        expectPopupSurface('查看历史版本');
        await tester.tapAt(const Offset(600, 500));
        await tester.pumpAndSettle();
        expect(find.text('查看历史版本'), findsNothing);
        final returning = c.showLibrary();
        for (var i = 0; i < 200 && !c.libraryVisible; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await returning;
        await tester.pumpAndSettle();
        expect(find.text('从备份恢复作品'), findsNothing);
        await tester.tap(find.byTooltip('书库管理'));
        await tester.pumpAndSettle();
        expectPopupSurface('从备份恢复作品');
        await tester.tapAt(const Offset(600, 500));
        await tester.pumpAndSettle();
        expect(find.text('从备份恢复作品'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      },
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/editor/novel_editor.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  test(
    'pixel and watercolor presets are offline, keep individual settings and survive restart',
    () {
      var settings = const AppearanceSettings();
      for (final id in ['pixel_meadow', 'pixel_starlight', 'sakura']) {
        settings = settings.select(id);
        expect(File(settings.preset.wallpaperAsset!).existsSync(), isTrue);
        settings = settings.updateCurrent(
          settings.current.copyWith(editorOpacity: .91),
        );
      }
      settings = AppearanceSettings.fromJson(settings.toJson());
      expect(settings.select('pixel_meadow').current.editorOpacity, .91);
      expect(settings.select('pixel_starlight').isNight, isTrue);
      expect(settings.select('sakura').isNight, isFalse);
      expect(settings.select('paper').current.editorOpacity, 1);
    },
  );

  testWidgets(
    'switching every theme preserves the active editor, manuscript and selection',
    (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('inkflow-theme-switch-'),
      ))!;
      final c = (await tester.runAsync(() async {
        final c = WorkbenchController(Directory('${root.path}/device'));
        await c.initialize();
        final work = await WorkRepository.create(
          Directory('${root.path}/book'),
          '主题检查',
        );
        await work.createChapter('一', text: '雨停了，继续写作。');
        await c.openWork(work.root);
        return c;
      }))!;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      final editor = tester.state(find.byType(NovelEditor));
      c.session.controller.selection = const TextSelection.collapsed(offset: 3);
      final value = c.session.controller.value;
      for (final id in [
        'paper',
        'night',
        'pixel_meadow',
        'pixel_starlight',
        'sakura',
        'forest',
      ]) {
        c.updateAppearance(c.appearance.select(id));
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(NovelEditor)), same(editor));
        expect(c.session.controller.value, value);
        expect(c.preferences.layout.fontFamily, 'Songti SC');
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}

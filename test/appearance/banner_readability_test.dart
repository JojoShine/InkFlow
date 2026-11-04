import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/core/storage/recovery_store.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/appearance/readability.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';
import 'package:inkflow/features/works/work_repository.dart';

void main() {
  late Directory root;
  late WorkbenchController c;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('inkflow-readable-banner-');
    final work = await WorkRepository.create(Directory('${root.path}/work'), '提示检查');
    await work.createChapter('第一章');
    c = WorkbenchController(Directory('${root.path}/device'));
    await c.initialize();
    await c.openWork(work.root);
    c.notice = '状态提示';
    c.recoveredDraft = SessionRecovery(chapterId: c.activeChapterId!, text: '草稿', baseHash: c.session.baseVersion!.hash);
  });
  tearDown(() async => root.delete(recursive: true));
  testWidgets('notice and recovery banners retain opaque readable surfaces in every theme', (tester) async {
    tester.view.physicalSize = const Size(1360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final preset in inkThemePresets) {
      c.preferences = c.preferences.copyWith(appearance: AppearanceSettings(presetId: preset.id));
      await tester.pumpWidget(InkFlowApp(controller: c));
      await tester.pumpAndSettle();
      final palette = InkPalette.from(c.appearance);
      for (final label in ['状态提示', '发现一份未保存的本机草稿']) {
        final container = find.ancestor(of: find.text(label), matching: find.byType(Container)).first;
        final background = tester.widget<Container>(container).color!;
        expect(background.a, 1);
        expect(colorContrast(palette.ink, background), greaterThanOrEqualTo(4.5));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}

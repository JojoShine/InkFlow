import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/app/inkflow_app.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/editor/editor_session.dart';
import 'package:inkflow/features/workbench/workbench_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('interface and initial manuscript use one font family', () {
    final theme = inkTheme(const AppearanceSettings());
    final family = theme.textTheme.bodyMedium!.fontFamily;
    expect(family, 'Songti SC');
    for (final style in [
      theme.textTheme.bodySmall,
      theme.textTheme.titleLarge,
      theme.textTheme.labelLarge,
      theme.textTheme.headlineSmall,
    ]) {
      expect(style?.fontFamily, family);
    }
    for (final style in [
      theme.textButtonTheme.style,
      theme.filledButtonTheme.style,
      theme.outlinedButtonTheme.style,
    ]) {
      expect(style!.textStyle!.resolve({})!.fontFamily, family);
    }
    expect(const EditorLayoutSettings().fontFamily, family);
  });
  test(
    'every background theme has a bundled offline image and readable defaults',
    () async {
      for (final preset in inkThemePresets.where(
        (p) => p.wallpaperAsset != null,
      )) {
        final asset = await rootBundle.load(preset.wallpaperAsset!);
        expect(asset.lengthInBytes, greaterThan(0));
        expect(preset.defaults.editorOpacity, inInclusiveRange(.7, 1));
        expect(
          AppearanceSettings.fromJson(
            AppearanceSettings(presetId: preset.id).toJson(),
          ).preset.id,
          preset.id,
        );
      }
    },
  );
  test(
    'custom wallpaper and opacity stay with each theme and reset restores its own defaults',
    () {
      final forest = const AppearanceSettings(presetId: 'forest');
      final selected = forest
          .updateCurrent(
            forest.current.copyWith(
              wallpaperPath: '/my/forest.png',
              editorOpacity: .8,
            ),
          )
          .select('rain');
      final restored = AppearanceSettings.fromJson(selected.toJson());
      expect(restored.isNight, isTrue);
      expect(restored.preset.wallpaperAsset, endsWith('rain.png'));
      final customForest = restored.select('forest');
      expect(customForest.current.wallpaperPath, '/my/forest.png');
      expect(customForest.current.editorOpacity, .8);
      final reset = customForest.resetCurrent();
      expect(reset.current.wallpaperPath, isNull);
      expect(reset.current.editorOpacity, forest.preset.defaults.editorOpacity);
      expect(reset.preset.wallpaperAsset, endsWith('forest.png'));
    },
  );
  testWidgets(
    'appearance gallery shows background themes and selection keeps text layout',
    (tester) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('inkflow-theme-gallery-'),
      );
      final c = WorkbenchController(directory!);
      await tester.runAsync(c.initialize);
      c.preferences = c.preferences.copyWith(
        layout: const EditorLayoutSettings(fontSize: 24),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1360, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(InkFlowApp(controller: c));
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
      for (final label in ['温暖书房', '夜间书房', '雾林晨光', '暮色海岸', '雨夜书窗']) {
        expect(find.text(label), findsOneWidget);
      }
      final list = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(ListView),
      );
      expect(
        find.ancestor(of: list, matching: find.byType(Scrollbar)),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.text('正文字体'),
        200,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );
      expect(
        tester
            .state<ScrollableState>(
              find.descendant(of: list, matching: find.byType(Scrollable)),
            )
            .position
            .pixels,
        greaterThan(0),
      );
      await tester.drag(list, const Offset(0, 1400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('雾林晨光'));
      await tester.pump(const Duration(milliseconds: 180));
      expect(c.appearance.presetId, 'forest');
      expect(c.preferences.layout.fontSize, 24);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      await tester.runAsync(() => directory.delete(recursive: true));
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}

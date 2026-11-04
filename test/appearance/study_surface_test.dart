import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/study_surface.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';
import 'package:inkflow/features/appearance/readability.dart';

void main() {
  for (final id in ['paper', 'night', 'forest']) {
    testWidgets(
      '$id surface draws only its quiet static texture with readable foregrounds',
      (tester) async {
        final settings = AppearanceSettings(presetId: id);
        final palette = InkPalette.from(settings);
        const capture = ValueKey('texture-capture');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: capture,
                child: SizedBox(
                  width: 256,
                  height: 256,
                  child: StudySurface(
                    color: palette.paper,
                    settings: settings,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final bytes = (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return data!.buffer.asUint8List();
        }))!;
        var changed = 0;
        for (var i = 0; i < bytes.length; i += 4) {
          final pixel = Color.fromARGB(
            bytes[i + 3],
            bytes[i],
            bytes[i + 1],
            bytes[i + 2],
          );
          if (pixel != palette.paper) changed++;
          for (final ink in [palette.ink, palette.muted, palette.accent]) {
            expect(colorContrast(ink, pixel), greaterThanOrEqualTo(4.5));
          }
        }
        expect(changed, id == 'forest' ? 0 : greaterThan(100));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse);
      },
    );
  }

  test('custom wallpapers take priority over built-in grain', () {
    final custom = const AppearanceSettings().updateCurrent(
      const ThemeOverrides(wallpaperPath: '/custom.png'),
    );
    expect(custom.texture, StudyTexture.none);
    expect(const AppearanceSettings().texture, StudyTexture.paper);
    expect(
      const AppearanceSettings(presetId: 'night').texture,
      StudyTexture.linen,
    );
  });
}

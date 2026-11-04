import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow/features/appearance/appearance_settings.dart';
import 'package:inkflow/features/appearance/theme_presets.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  for (final preset in inkThemePresets) {
    test('${preset.id} normal, secondary and accent text remain readable', () {
      final palette = InkPalette.from(AppearanceSettings(presetId: preset.id));
      for (final background in [
        palette.background,
        palette.paper,
        palette.selection,
      ]) {
        for (final text in [palette.ink, palette.muted, palette.accent]) {
          expect(contrast(text, background), greaterThanOrEqualTo(4.5));
        }
      }
    });
  }
  test(
    'wallpaper extremes and custom accents preserve readable text at minimum opacity',
    () {
      for (final preset in inkThemePresets) {
        for (final dim in [0.0, .7]) {
          for (final accent in [
            0xffffffff,
            0xff000000,
            0xffffff00,
            0xff00ffff,
            0xffff0000,
          ]) {
            final settings = AppearanceSettings(presetId: preset.id)
                .updateCurrent(
                  ThemeOverrides(
                    wallpaperPath: '/custom.png',
                    editorOpacity: .7,
                    backgroundDim: dim,
                    accentColor: accent,
                  ),
                );
            final original = settings.toJson();
            final palette = InkPalette.from(settings);
            final surfaces = [
              palette.paper,
              palette.background,
              palette.selection,
            ];
            for (final image in [Colors.black, Colors.white]) {
              final tinted = Color.alphaBlend(
                palette.background.withValues(
                  alpha: preset.isNight ? .18 : .32,
                ),
                image,
              );
              final backdrop = Color.alphaBlend(
                Colors.black.withValues(alpha: dim),
                tinted,
              );
              surfaces.addAll([
                Color.alphaBlend(palette.paper.withValues(alpha: .7), backdrop),
                Color.alphaBlend(
                  palette.background.withValues(alpha: .92),
                  backdrop,
                ),
                Color.alphaBlend(
                  palette.paper.withValues(alpha: .96),
                  backdrop,
                ),
              ]);
            }
            for (final surface in surfaces) {
              for (final text in [palette.ink, palette.muted, palette.accent]) {
                expect(
                  contrast(Color(text.toARGB32()), surface),
                  greaterThanOrEqualTo(4.5),
                  reason: '${preset.id} dim=$dim accent=$accent',
                );
              }
            }
            final theme = inkTheme(settings);
            expect(
              contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
              greaterThanOrEqualTo(4.5),
            );
            expect(settings.toJson(), original);
          }
        }
      }
    },
  );
}

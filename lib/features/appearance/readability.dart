import 'package:flutter/material.dart';
import 'appearance_settings.dart';

double colorContrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

Color wallpaperTint(AppearanceSettings settings) => Color(
  settings.preset.background,
).withValues(alpha: settings.isNight ? .18 : .32);

List<Color> readingSurfaces(AppearanceSettings settings) {
  final preset = settings.preset, current = settings.current;
  final paper = Color(preset.paper), background = Color(preset.background);
  final hasImage =
      current.wallpaperPath != null || preset.wallpaperAsset != null;
  final backdrops = hasImage
      ? [Colors.black, Colors.white].map(
          (image) => Color.alphaBlend(
            Colors.black.withValues(alpha: current.backgroundDim),
            Color.alphaBlend(wallpaperTint(settings), image),
          ),
        )
      : [background];
  final surfaces = [
    background,
    paper,
    Color(preset.selection),
    for (final backdrop in backdrops) ...[
      Color.alphaBlend(
        paper.withValues(alpha: current.editorOpacity),
        backdrop,
      ),
      Color.alphaBlend(paper.withValues(alpha: .96), backdrop),
      Color.alphaBlend(background.withValues(alpha: .92), backdrop),
      Color.alphaBlend(background.withValues(alpha: .96), backdrop),
    ],
  ];
  if (settings.texture == StudyTexture.none) return surfaces;
  return [
    for (final surface in surfaces) ...[
      surface,
      Color.alphaBlend(
        (settings.isNight ? Colors.white : Colors.black).withValues(alpha: .05),
        surface,
      ),
    ],
  ];
}

Color readableColor(Color preferred, Color ink, List<Color> surfaces) {
  bool readable(Color color) =>
      surfaces.every((surface) => colorContrast(color, surface) >= 4.6);
  if (readable(preferred)) return preferred;
  var low = 0.0, high = 1.0;
  for (var i = 0; i < 18; i++) {
    final middle = (low + high) / 2;
    if (readable(Color.lerp(preferred, ink, middle)!)) {
      high = middle;
    } else {
      low = middle;
    }
  }
  return Color(Color.lerp(preferred, ink, high)!.toARGB32());
}

Color foregroundOn(Color background, Color ink, Color paper) {
  final chosen =
      colorContrast(ink, background) >= colorContrast(paper, background)
      ? ink
      : paper;
  if (colorContrast(chosen, background) >= 4.5) return chosen;
  return colorContrast(Colors.black, background) >=
          colorContrast(Colors.white, background)
      ? Colors.black
      : Colors.white;
}

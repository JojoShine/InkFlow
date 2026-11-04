import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'appearance_settings.dart';
import 'theme_presets.dart';
import 'readability.dart';
import 'study_surface.dart';

class WallpaperLayer extends StatelessWidget {
  const WallpaperLayer({
    super.key,
    required this.settings,
    required this.child,
  });
  final AppearanceSettings settings;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final current = settings.current;
    final path = current.wallpaperPath;
    final asset = settings.preset.wallpaperAsset;
    final pixelArt = settings.preset.pixelArt && path == null;
    final ImageProvider? wallpaper = path != null
        ? FileImage(File(path))
        : asset == null
        ? null
        : AssetImage(asset);
    return StudySurface(
      settings: settings,
      color: InkPalette.of(context).background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (wallpaper != null) ...[
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: current.backgroundBlur,
                  sigmaY: current.backgroundBlur,
                ),
                child: LayoutBuilder(
                  builder: (context, size) => Image(
                    filterQuality: pixelArt
                        ? FilterQuality.none
                        : FilterQuality.low,
                    image: pixelArt
                        ? wallpaper
                        : ResizeImage.resizeIfNeeded(
                            (size.maxWidth *
                                    MediaQuery.devicePixelRatioOf(context))
                                .ceil()
                                .clamp(1, 1800)
                                .toInt(),
                            null,
                            wallpaper,
                          ),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            ColoredBox(color: wallpaperTint(settings)),
            ColoredBox(
              color: Colors.black.withValues(alpha: current.backgroundDim),
            ),
          ],
          child,
        ],
      ),
    );
  }
}

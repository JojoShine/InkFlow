class ThemeOverrides {
  const ThemeOverrides({
    this.wallpaperPath,
    this.accentColor,
    this.editorOpacity = 1,
    this.backgroundDim = 0,
    this.backgroundBlur = 0,
  });
  final String? wallpaperPath;
  final int? accentColor;
  final double editorOpacity;
  final double backgroundDim;
  final double backgroundBlur;

  ThemeOverrides copyWith({
    String? wallpaperPath,
    bool clearWallpaper = false,
    int? accentColor,
    double? editorOpacity,
    double? backgroundDim,
    double? backgroundBlur,
  }) => ThemeOverrides(
    wallpaperPath: clearWallpaper ? null : wallpaperPath ?? this.wallpaperPath,
    accentColor: accentColor ?? this.accentColor,
    editorOpacity: editorOpacity ?? this.editorOpacity,
    backgroundDim: backgroundDim ?? this.backgroundDim,
    backgroundBlur: backgroundBlur ?? this.backgroundBlur,
  );

  Map<String, Object?> toJson() => {
    'wallpaperPath': wallpaperPath,
    'accentColor': accentColor,
    'editorOpacity': editorOpacity,
    'backgroundDim': backgroundDim,
    'backgroundBlur': backgroundBlur,
  };

  static ThemeOverrides fromJson(Map<String, dynamic> json) => ThemeOverrides(
    wallpaperPath: json['wallpaperPath'] as String?,
    accentColor: json['accentColor'] as int?,
    editorOpacity: ((json['editorOpacity'] as num?)?.toDouble() ?? 1).clamp(
      0.7,
      1,
    ),
    backgroundDim: ((json['backgroundDim'] as num?)?.toDouble() ?? 0).clamp(
      0,
      0.7,
    ),
    backgroundBlur: ((json['backgroundBlur'] as num?)?.toDouble() ?? 0).clamp(
      0,
      16,
    ),
  );
}

enum StudyTexture { none, paper, linen }

class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.title,
    required this.description,
    required this.background,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.line,
    required this.selection,
    required this.accent,
    this.wallpaperAsset,
    this.texture = StudyTexture.none,
    this.pixelArt = false,
    this.isNight = false,
    this.defaults = const ThemeOverrides(),
  });
  final String id, title, description;
  final int background, paper, ink, muted, line, selection, accent;
  final String? wallpaperAsset;
  final StudyTexture texture;
  final bool pixelArt;
  final bool isNight;
  final ThemeOverrides defaults;
}

const inkThemePresets = [
  ThemePreset(
    id: 'paper',
    title: '温暖书房',
    description: '暖纸 · 细纤维',
    texture: StudyTexture.paper,
    background: 0xfff3efe7,
    paper: 0xfffffdf8,
    ink: 0xff302c27,
    muted: 0xff8d8174,
    line: 0xffe3dcd2,
    selection: 0xffe8d8c7,
    accent: 0xff8b6245,
  ),
  ThemePreset(
    id: 'night',
    title: '夜间书房',
    description: '暖夜 · 亚麻纹',
    texture: StudyTexture.linen,
    isNight: true,
    background: 0xff24221f,
    paper: 0xff2d2925,
    ink: 0xffe6ded2,
    muted: 0xffaaa094,
    line: 0xff443d35,
    selection: 0xff514033,
    accent: 0xffcea782,
  ),
  ThemePreset(
    id: 'forest',
    title: '雾林晨光',
    description: '晨雾 · 松绿 · 浅色',
    background: 0xffedf1e7,
    paper: 0xfff8faf3,
    ink: 0xff2b362b,
    muted: 0xff6d7d67,
    line: 0xffd5ddcd,
    selection: 0xffdde7d5,
    accent: 0xff58734f,
    wallpaperAsset: 'assets/themes/forest.png',
    defaults: ThemeOverrides(
      editorOpacity: .88,
      backgroundDim: .04,
      backgroundBlur: .6,
    ),
  ),
  ThemePreset(
    id: 'coast',
    title: '暮色海岸',
    description: '落日 · 海风 · 暖色',
    background: 0xfff4e9df,
    paper: 0xfffff8f0,
    ink: 0xff44362f,
    muted: 0xff927464,
    line: 0xffe5d3c3,
    selection: 0xffecd6c2,
    accent: 0xffaa6e4c,
    wallpaperAsset: 'assets/themes/coast.png',
    defaults: ThemeOverrides(
      editorOpacity: .87,
      backgroundDim: .02,
      backgroundBlur: .4,
    ),
  ),
  ThemePreset(
    id: 'rain',
    title: '雨夜书窗',
    description: '雨滴 · 灯火 · 深色',
    isNight: true,
    background: 0xff1b2832,
    paper: 0xff23313d,
    ink: 0xffecedf0,
    muted: 0xff9eafb9,
    line: 0xff3c505e,
    selection: 0xff3d5666,
    accent: 0xffd3a66e,
    wallpaperAsset: 'assets/themes/rain.png',
    defaults: ThemeOverrides(
      editorOpacity: .88,
      backgroundDim: .12,
      backgroundBlur: .5,
    ),
  ),
  ThemePreset(
    id: 'pixel_meadow',
    title: '像素原野',
    description: '像素 · 草木 · 晨光',
    background: 0xffeeeeda,
    paper: 0xfffbfbed,
    ink: 0xff30382a,
    muted: 0xff6b7559,
    line: 0xffd8dec3,
    selection: 0xffe1e6c9,
    accent: 0xff637747,
    wallpaperAsset: 'assets/themes/pixel_meadow.png',
    pixelArt: true,
    defaults: ThemeOverrides(editorOpacity: .86, backgroundDim: .02),
  ),
  ThemePreset(
    id: 'pixel_starlight',
    title: '像素星夜',
    description: '像素 · 星湖 · 暖灯',
    isNight: true,
    background: 0xff191e32,
    paper: 0xff242b43,
    ink: 0xffeee9df,
    muted: 0xffa9adc2,
    line: 0xff414964,
    selection: 0xff424960,
    accent: 0xffd9b77b,
    wallpaperAsset: 'assets/themes/pixel_starlight.png',
    pixelArt: true,
    defaults: ThemeOverrides(editorOpacity: .87, backgroundDim: .04),
  ),
  ThemePreset(
    id: 'sakura',
    title: '樱下手札',
    description: '水彩 · 樱花 · 浅色',
    background: 0xfff4eae7,
    paper: 0xfffff9f5,
    ink: 0xff423137,
    muted: 0xff8b7079,
    line: 0xffe4d3d4,
    selection: 0xffecd9df,
    accent: 0xff9e6276,
    wallpaperAsset: 'assets/themes/sakura.png',
    defaults: ThemeOverrides(
      editorOpacity: .86,
      backgroundDim: 0,
      backgroundBlur: .3,
    ),
  ),
];

class AppearanceSettings {
  const AppearanceSettings({
    this.presetId = 'paper',
    this.themes = const {},
    this.animationsEnabled = true,
  });
  final String presetId;
  final Map<String, ThemeOverrides> themes;
  final bool animationsEnabled;
  ThemePreset get preset =>
      inkThemePresets.firstWhere((theme) => theme.id == presetId);
  ThemeOverrides get current => themes[presetId] ?? preset.defaults;
  bool get isNight => preset.isNight;
  StudyTexture get texture =>
      current.wallpaperPath == null ? preset.texture : StudyTexture.none;

  AppearanceSettings select(String id) => AppearanceSettings(
    presetId: id,
    themes: themes,
    animationsEnabled: animationsEnabled,
  );
  AppearanceSettings updateCurrent(ThemeOverrides settings) =>
      AppearanceSettings(
        presetId: presetId,
        themes: Map.unmodifiable({...themes, presetId: settings}),
        animationsEnabled: animationsEnabled,
      );
  AppearanceSettings resetCurrent() => AppearanceSettings(
    presetId: presetId,
    themes: Map.unmodifiable({...themes}..remove(presetId)),
    animationsEnabled: animationsEnabled,
  );
  AppearanceSettings withAnimations(bool enabled) => AppearanceSettings(
    presetId: presetId,
    themes: themes,
    animationsEnabled: enabled,
  );

  Map<String, Object?> toJson() => {
    'presetId': presetId,
    'animationsEnabled': animationsEnabled,
    'themes': {
      for (final entry in themes.entries) entry.key: entry.value.toJson(),
    },
  };
  static AppearanceSettings fromJson(Map<String, dynamic> json) {
    final id = json['presetId'] as String? ?? 'paper';
    if (!inkThemePresets.any((theme) => theme.id == id)) {
      throw const FormatException('未知主题');
    }
    return AppearanceSettings(
      presetId: id,
      animationsEnabled: json['animationsEnabled'] as bool? ?? true,
      themes: Map.unmodifiable(
        (json['themes'] as Map<String, dynamic>? ?? {}).map(
          (key, value) => MapEntry(
            key,
            ThemeOverrides.fromJson(value as Map<String, dynamic>),
          ),
        ),
      ),
    );
  }
}

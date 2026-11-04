import 'package:flutter/material.dart';
import '../../core/typography.dart';
import 'appearance_settings.dart';
import 'readability.dart';
import '../../app/ink_icons.dart';

class InkPalette extends ThemeExtension<InkPalette> {
  static final _cache = Expando<InkPalette>();
  const InkPalette({
    required this.background,
    required this.paper,
    required this.ink,
    required this.muted,
    required this.line,
    required this.selection,
    required this.accent,
  });
  final Color background, paper, ink, muted, line, selection, accent;

  factory InkPalette.from(AppearanceSettings settings) {
    return _cache[settings] ??= InkPalette._resolve(settings);
  }

  factory InkPalette._resolve(AppearanceSettings settings) {
    final preset = settings.preset;
    final surfaces = readingSurfaces(settings);
    final ink = readableColor(
      Color(preset.ink),
      settings.isNight ? Colors.white : Colors.black,
      surfaces,
    );
    return InkPalette(
      background: Color(preset.background),
      paper: Color(preset.paper),
      ink: ink,
      muted: readableColor(Color(preset.muted), ink, surfaces),
      line: Color(preset.line),
      selection: Color(preset.selection),
      accent: readableColor(
        Color(settings.current.accentColor ?? preset.accent),
        ink,
        surfaces,
      ),
    );
  }

  static InkPalette of(BuildContext context) =>
      Theme.of(context).extension<InkPalette>()!;
  @override
  InkPalette copyWith({
    Color? background,
    Color? paper,
    Color? ink,
    Color? muted,
    Color? line,
    Color? selection,
    Color? accent,
  }) => InkPalette(
    background: background ?? this.background,
    paper: paper ?? this.paper,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    line: line ?? this.line,
    selection: selection ?? this.selection,
    accent: accent ?? this.accent,
  );
  @override
  InkPalette lerp(covariant InkPalette? other, double t) => other == null
      ? this
      : InkPalette(
          background: Color.lerp(background, other.background, t)!,
          paper: Color.lerp(paper, other.paper, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          muted: Color.lerp(muted, other.muted, t)!,
          line: Color.lerp(line, other.line, t)!,
          selection: Color.lerp(selection, other.selection, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
        );
}

ThemeData inkTheme(AppearanceSettings appearance) {
  final colors = InkPalette.from(appearance);
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textStyle: const WidgetStatePropertyAll(
      TextStyle(
        fontFamily: inkFontFamily,
        fontFamilyFallback: inkFontFallback,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    ),
    iconSize: const WidgetStatePropertyAll(18),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: appearance.isNight ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.paper,
    fontFamily: inkFontFamily,
    fontFamilyFallback: inkFontFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: appearance.isNight ? Brightness.dark : Brightness.light,
      surface: colors.paper,
      onSurface: colors.ink,
      primary: colors.accent,
      onPrimary: foregroundOn(colors.accent, colors.ink, colors.paper),
      onSurfaceVariant: colors.muted,
      surfaceContainerLowest: colors.paper,
      surfaceContainerLow: colors.paper,
      surfaceContainer: colors.paper,
      surfaceContainerHigh: colors.paper,
      surfaceContainerHighest: colors.selection,
      surfaceTint: Colors.transparent,
      outline: colors.line,
      outlineVariant: colors.line,
    ),
    dividerColor: colors.line,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.selection,
      selectionHandleColor: colors.accent,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? colors.accent : colors.line,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? colors.paper : colors.muted,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.line),
      ),
      position: PopupMenuPosition.under,
    ),
    menuTheme: MenuThemeData(
      submenuIcon: const WidgetStatePropertyAll(
        Icon(InkIcons.chevronRight, size: 12),
      ),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.paper),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    extensions: [colors],
    textTheme: TextTheme(
      bodyMedium: TextStyle(fontSize: 15, color: colors.ink),
      bodySmall: TextStyle(fontSize: 13, color: colors.muted),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 450),
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: colors.muted),
      labelStyle: TextStyle(color: colors.muted),
      floatingLabelStyle: TextStyle(color: colors.accent),
      isDense: true,
      border: OutlineInputBorder(borderSide: BorderSide(color: colors.line)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colors.accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.muted,
        iconSize: 20,
        minimumSize: const Size(36, 36),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: buttonStyle.copyWith(elevation: const WidgetStatePropertyAll(0)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.muted.withValues(alpha: .5)
              : colors.ink,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: colors.line)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.muted.withValues(alpha: .5)
              : colors.ink,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.paper,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.paper),
    ),
  );
}

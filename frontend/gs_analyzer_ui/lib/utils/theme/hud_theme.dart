import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_colors.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_text_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

class HudTheme {
  static ThemeData lightTheme(Color accentColor) {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: HudColors.lightBgBase,
      textTheme: HudTextTheme.light,
      colorScheme: ColorScheme.light(
        primary: accentColor,
        surface: HudColors.lightBgPanel,
        onSurface: HudColors.lightTextMain,
        outline: HudColors.lightPrimaryBorder,
        error: HudColors.lightAccentRed,
        onPrimary: HudColors.lightAccentCyan,
        secondary: HudColors.lightAccentGreen,
        tertiary: HudColors.lightAccentAmber,
        onSecondary: HudColors.lightAccentPurple,
        onTertiary: HudColors.lightAccentBlue,
        surfaceDim: HudColors.lightTextDim,
      ),
      cardTheme: CardThemeData(color: HudColors.lightBgPanel),
      dividerTheme: const DividerThemeData(color: Colors.black12),
      extensions: <ThemeExtension<dynamic>>[
        HudThemeExtension(
          background: HudColors.lightBgBase,
          panel: HudColors.lightBgPanel,
          text: HudColors.lightTextMain,
          border: HudColors.lightPrimaryBorder,
          accentRed: HudColors.lightAccentRed,
          accentCyan: HudColors.lightAccentCyan,
          accentGreen: HudColors.lightAccentGreen,
          accentAmber: HudColors.lightAccentAmber,
          accentPurple: HudColors.lightAccentPurple,
          accentBlue: HudColors.lightAccentBlue,
          textDim: HudColors.lightTextDim,
          hudPanelDecoration: BoxDecoration(),
          listItemDecoration: BoxDecoration()
        ),
      ],
    );
  }

  static ThemeData darkTheme(Color accentColor) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HudColors.darkBgBase,
      textTheme: HudTextTheme.dark,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        surface: HudColors.darkBgPanel,
        onSurface: HudColors.darkTextMain,
        outline: HudColors.darkPrimaryBorder,
        error: HudColors.darkAccentRed,
        onPrimary: HudColors.darkAccentCyan,
        secondary: HudColors.darkAccentGreen,
        tertiary: HudColors.darkAccentAmber,
        onSecondary: HudColors.darkAccentPurple,
        onTertiary: HudColors.darkAccentBlue,
        surfaceDim: HudColors.darkTextDim,
      ),
      cardTheme: CardThemeData(color: HudColors.darkBgPanel),
      dividerTheme: const DividerThemeData(color: Colors.white10),
      extensions: <ThemeExtension<dynamic>>[
        HudThemeExtension(
          background: HudColors.darkBgBase,
          panel: HudColors.darkBgPanel,
          text: HudColors.darkTextMain,
          border: HudColors.darkPrimaryBorder,
          accentRed: HudColors.darkAccentRed,
          accentCyan: HudColors.darkAccentCyan,
          accentGreen: HudColors.darkAccentGreen,
          accentAmber: HudColors.darkAccentAmber,
          accentPurple: HudColors.darkAccentPurple,
          accentBlue: HudColors.darkAccentBlue,
          textDim: HudColors.darkTextDim,
          hudPanelDecoration: BoxDecoration(),
          listItemDecoration: BoxDecoration()
        ),
      ],
    );
  }

  static ThemeMode resolveThemeMode(String? theme) {
    switch (theme?.toLowerCase()) {
      case 'cyber_light':
      case 'light':
        return ThemeMode.light;
      case 'cyber_dark':
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }
}
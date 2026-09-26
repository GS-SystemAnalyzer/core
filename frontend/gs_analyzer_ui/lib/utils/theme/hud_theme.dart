import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_text_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

class HudTheme {
  static const String fontCore = 'Courier';

  static ThemeData lightTheme(Color accentColor) {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: HudColor.lightBgBase,
      textTheme: HudTextTheme.light,
      colorScheme: ColorScheme.light(
        primary: accentColor,
        surface: HudColor.lightBgPanel,
        onSurface: HudColor.lightTextMain,
        outline: HudColor.lightPrimaryBorder,
        error: HudColor.lightAccentRed,
        onPrimary: HudColor.lightAccentCyan,
        secondary: HudColor.lightAccentGreen,
        tertiary: HudColor.lightAccentAmber,
        onSecondary: HudColor.lightAccentPurple,
        onTertiary: HudColor.lightAccentBlue,
        surfaceDim: HudColor.lightTextDim,
      ),
      cardTheme: CardThemeData(color: HudColor.lightBgPanel),
      dividerTheme: const DividerThemeData(color: Colors.black12),
      extensions: <ThemeExtension<dynamic>>[
        HudThemeExtension(
          base: HudColor.lightBgBase,
          panel: HudColor.lightBgPanel,
          textMain: HudColor.lightTextMain,
          border: HudColor.lightPrimaryBorder,
          accentRed: HudColor.lightAccentRed,
          accentCyan: HudColor.lightAccentCyan,
          accentGreen: HudColor.lightAccentGreen,
          accentAmber: HudColor.lightAccentAmber,
          accentPurple: HudColor.lightAccentPurple,
          accentBlue: HudColor.lightAccentBlue,
          textMuted: HudColor.lightTextMuted,
          textDim: HudColor.lightTextDim,
          header: TextStyle(
            fontFamily: fontCore,
            color: accentColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 2
          ),
          statGreen: TextStyle(
            fontFamily: fontCore,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: HudColor.lightAccentGreen
          ),
          statCyan: TextStyle(
            fontSize: 13,
            fontFamily: fontCore,
            color: HudColor.lightAccentCyan
          ),
          actionRed: TextStyle(
            fontSize: 14,
            fontFamily: fontCore,
            fontWeight: FontWeight.bold,
            color: HudColor.lightAccentRed
          ),
          label: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            fontFamily: fontCore,
            color: HudColor.lightTextDim
          ),
          body: TextStyle(
            fontSize: 13,
            fontFamily: fontCore,
            color: HudColor.lightTextMuted
          ),
          hudPanelDecoration: BoxDecoration(
            color: HudColor.darkBgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HudColor.lightPrimaryBorder.withValues(alpha: 0.3))
          ), 
          listItemDecoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: HudColor.lightTextMain.withValues(alpha: 0.1)))
          )
        ),
      ],
    );
  }

  static ThemeData darkTheme(Color accentColor) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HudColor.darkBgBase,
      textTheme: HudTextTheme.dark,
      colorScheme: ColorScheme.dark(
        primary: accentColor,
        surface: HudColor.darkBgPanel,
        onSurface: HudColor.darkTextMain,
        outline: HudColor.darkPrimaryBorder,
        error: HudColor.darkAccentRed,
        onPrimary: HudColor.darkAccentCyan,
        secondary: HudColor.darkAccentGreen,
        tertiary: HudColor.darkAccentAmber,
        onSecondary: HudColor.darkAccentPurple,
        onTertiary: HudColor.darkAccentBlue,
        surfaceDim: HudColor.darkTextDim,
      ),
      cardTheme: CardThemeData(color: HudColor.darkBgPanel),
      dividerTheme: const DividerThemeData(color: Colors.white10),
      extensions: <ThemeExtension<dynamic>>[
        HudThemeExtension(
          base: HudColor.darkBgBase,
          panel: HudColor.darkBgPanel,
          textMain: HudColor.darkTextMain,
          border: HudColor.darkPrimaryBorder,
          accentRed: HudColor.darkAccentRed,
          accentCyan: HudColor.darkAccentCyan,
          accentGreen: HudColor.darkAccentGreen,
          accentAmber: HudColor.darkAccentAmber,
          accentPurple: HudColor.darkAccentPurple,
          accentBlue: HudColor.darkAccentBlue,
          textMuted: HudColor.darkTextMuted,
          textDim: HudColor.darkTextDim,
          header: TextStyle(
            fontFamily: fontCore,
            color: accentColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 2
          ),
          statGreen: TextStyle(
            fontFamily: fontCore,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: HudColor.darkAccentGreen
          ),
          statCyan: TextStyle(
            fontSize: 13,
            fontFamily: fontCore,
            color: HudColor.darkAccentCyan
          ),
          actionRed: TextStyle(
            fontSize: 14,
            fontFamily: fontCore,
            fontWeight: FontWeight.bold,
            color: HudColor.darkAccentRed
          ),
          label: TextStyle(
            fontSize: 12,
            letterSpacing: 1,
            fontFamily: fontCore,
            color: HudColor.darkTextDim
          ),
          body: TextStyle(
            fontSize: 13,
            fontFamily: fontCore,
            color: HudColor.darkTextMuted
          ),
          hudPanelDecoration: BoxDecoration(
            color: HudColor.darkBgPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HudColor.darkPrimaryBorder.withValues(alpha: 0.3))
          ), 
          listItemDecoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: HudColor.darkTextMain.withValues(alpha: 0.1)))
          )
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
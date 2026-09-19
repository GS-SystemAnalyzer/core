import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/core/theme/hud_colors.dart';

class HudTextTheme {

  static const String fontCore = 'Courier';

  static const light = TextTheme(
    headlineLarge: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightPrimaryBorder,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
      fontSize: 18
    ),

    headlineMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightPrimaryBorder,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
      fontSize: 18
    ),

    headlineSmall: TextStyle(
      fontFamily: fontCore,
      fontWeight: FontWeight.w600
    ),

    bodyLarge: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightAccentGreen,
      fontSize: 14,
      fontWeight: FontWeight.bold
    ),

    bodyMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightAccentCyan,
      fontSize: 13,
      fontWeight: FontWeight.bold
    ),

    bodySmall: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightAccentGreen,
      fontSize: 12,
      letterSpacing: 1
    ),

    displayMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightAccentRed,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5
    ),

    titleMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.lightTextMuted,
      fontSize: 13
    ),
  );

  static const dark = TextTheme(
    headlineLarge: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkPrimaryBorder,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
      fontSize: 18
    ),

    headlineMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkPrimaryBorder,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
      fontSize: 18
    ),

    headlineSmall: TextStyle(
      fontFamily: fontCore,
      fontWeight: FontWeight.w600
    ),

    bodyLarge: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkAccentGreen,
      fontSize: 14,
      fontWeight: FontWeight.bold
    ),

    bodyMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkAccentCyan,
      fontSize: 13,
      fontWeight: FontWeight.bold
    ),

    bodySmall: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkTextDim,
      fontSize: 12,
      letterSpacing: 1
    ),

    displayMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkAccentRed,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5
    ),

    titleMedium: TextStyle(
      fontFamily: fontCore,
      color: HudColors.darkTextMuted,
      fontSize: 13
    ),
  );
}
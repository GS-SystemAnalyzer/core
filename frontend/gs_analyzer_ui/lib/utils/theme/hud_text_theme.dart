import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';

class HudTextTheme {
  HudTextTheme._();

  static const String fontCore = 'Courier';

  static final TextTheme light = TextTheme(
    displayLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
    ),

    displayMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
    ),

    displaySmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
    ),

    headlineLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 18,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
    ),

    headlineMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 16,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5,
    ),

    headlineSmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    ),

    titleLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),

    titleMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),

    titleSmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),

    bodyLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 14,
    ),

    bodyMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMuted,
      fontSize: 13,
    ),

    bodySmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextDim,
      fontSize: 12,
      letterSpacing: 1,
    ),

    labelLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMain,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),

    labelMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextMuted,
      fontSize: 12,
      letterSpacing: 1,
    ),

    labelSmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.lightTextDim,
      fontSize: 11,
      letterSpacing: 1,
    ),
  );

  static final TextTheme dark = TextTheme(
    displayLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
    ),

    displayMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
    ),

    displaySmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
    ),

    headlineLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 18,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
    ),

    headlineMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 16,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.5,
    ),

    headlineSmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 14,
      fontWeight: FontWeight.bold,
      letterSpacing: 1,
    ),

    titleLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    ),

    titleMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),

    titleSmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMuted,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),

    bodyLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 14,
    ),

    bodyMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMuted,
      fontSize: 13,
    ),

    bodySmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextDim,
      fontSize: 12,
      letterSpacing: 1,
    ),

    labelLarge: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMain,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),

    labelMedium: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextMuted,
      fontSize: 12,
      letterSpacing: 1,
    ),

    labelSmall: const TextStyle(
      fontFamily: fontCore,
      color: HudColor.darkTextDim,
      fontSize: 11,
      letterSpacing: 1,
    ),
  );
}

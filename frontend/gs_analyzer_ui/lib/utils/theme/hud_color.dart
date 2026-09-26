import 'package:flutter/material.dart';

class HudColor {
  // ----------DARK MODE-----------------
  static const Color darkBgBase = Color(0xFF161616);
  static const Color darkBgPanel = Color(0xFF1E1E1E);
  static const Color darkPrimaryBorder = Colors.cyan;

  static const Color darkAccentCyan = Colors.cyanAccent;
  static const Color darkAccentGreen = Colors.greenAccent;
  static const Color darkAccentRed = Colors.redAccent;
  static const Color darkAccentAmber = Colors.amber;
  static const Color darkAccentPurple = Color(0xFFAA20C0);
  static const Color darkAccentBlue = Color(0xFF2864C7);


  static const Color darkTextMain = Colors.white;
  static const Color darkTextMuted = Colors.white70;
  static const darkTextDim = Colors.white54;

  // ----------LIGHT MODE-----------------
  static const Color lightBgBase = Color(0xFFF5F5F5);
  static const Color lightBgPanel = Color(0xFFFFFFFF);
  static const Color lightPrimaryBorder = Color(0xFF0097A7);

  static const Color lightAccentCyan = Colors.cyanAccent;
  static const Color lightAccentGreen = Color(0xFF2E7D32);
  static const Color lightAccentRed = Color(0xFFC62828);
  static const Color lightAccentAmber = Color(0xFFE65100);
  static const Color lightAccentPurple = Color(0xFFE040FB);
  static const Color lightAccentBlue = Color(0xFF448AFF);

  static const Color lightTextMain = Color(0xFF111111);
  static const Color lightTextMuted = Color(0xFF555555);
  static const lightTextDim = Color(0xFF888888);

  static Color resolveAccent(
    String? accentKey, [
    Brightness brightness = Brightness.dark,
  ]) {
    final isDark = brightness == Brightness.dark;

    switch (accentKey?.toLowerCase()) {
      case 'cyan':
      return isDark ? darkAccentCyan : lightAccentCyan;

      case 'green':
      return isDark ? darkAccentGreen : lightAccentGreen;

      case 'amber':
      return isDark ? darkAccentAmber : lightAccentAmber;

      case 'red':
      return isDark ? darkAccentRed : lightAccentRed;

      case 'purple':
      return isDark ? darkAccentPurple : lightAccentPurple;

      case 'blue':
      return isDark ? darkAccentBlue : lightAccentBlue;

      default:
      return isDark ? darkAccentCyan : lightAccentCyan;
    }
  }
}
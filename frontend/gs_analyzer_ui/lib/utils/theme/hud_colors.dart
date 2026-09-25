import 'package:flutter/material.dart';

class HudColors {
  // --------- HUD DARK THEME COLOR ------------------
  static const Color darkBgBase = Color(0xFF161616);
  static const  Color darkBgPanel = Color(0xFF1E1E1E);
  static const darkPrimaryBorder = Colors.cyan;

  // Text Colors
  static const Color darkTextMain = Colors.white;
  static const Color darkTextMuted = Colors.white70;
  static const Color darkTextDim = Colors.white54;

  // --------- HUD LIGHT THEME COLOR -----------------
  static const lightBgBase = Color(0xFFF5F5F5);
  static const  lightBgPanel = Color(0xFFFFFFFFF);
  static const lightPrimaryBorder = Color(0xFF0097A7);

  // Text Colors
  static const lightTextMain = Color(0xFF111111);
  static const lightTextMuted = Color(0xFF555555);
  static const lightTextDim = Color(0xFF8888888);

  // --------- ACCENT COLORS ----------------

  static const Color lightAccentCyan = Colors.cyan;
  static const Color darkAccentCyan = Color(0xFF0097A7);

  static const Color lightAccentGreen = Colors.green;
  static const Color darkAccentGreen = Color(0xFF2E7D32);

  static const Color lightAccentRed = Colors.red;
  static const Color darkAccentRed = Color(0xFFC62828);

  static const Color lightAccentAmber = Colors.amber;
  static const Color darkAccentAmber = Color(0xFFE65100);

  static const Color lightAccentPurple = Colors.purple;
  static const Color darkAccentPurple = Colors.purpleAccent;

  static const Color lightAccentBlue = Colors.blue;
  static const Color darkAccentBlue = Colors.blueAccent;


  static Color resolveAccent(String? accentKey, Brightness brightness) {
    final isdark = brightness == Brightness.dark;

    switch (accentKey?.toLowerCase()) {
      case 'cyan':
        return isdark ? darkAccentCyan : lightAccentCyan;
      case 'green':
        return isdark ? darkAccentGreen : lightAccentGreen;
      case 'amber':
        return isdark ? darkAccentAmber : lightAccentAmber;
      case 'red':
        return isdark ? darkAccentRed : lightAccentRed;
      case 'purple':
        return isdark ? darkAccentPurple : lightAccentPurple;
      case 'blue':
        return isdark ? darkAccentBlue : lightAccentBlue;
      default:
        return isdark ? darkAccentCyan : lightAccentCyan;
    }
  }

  static Color fileTypeColor(String category) {
    switch (category.toLowerCase()) {
      case 'media':
        return const Color(0xFF00FFFF);
      case 'documents':
        return const Color(0xFF4CAF50);
      case 'executables':
        return const Color(0xFFFF5252);
      case 'archives':
        return const Color(0xFFFFB300);
      case 'code':
        return const Color(0xFF9C27B0);
      case 'system':
        return Colors.white38;
      default:
        return Colors.white12;
    }
  }
  
}
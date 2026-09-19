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
  static const lightBgBase = Color(0xFFF4F7F8);
  static const  lightBgPanel = Color(0xFFF0F6FF);
  static const lightPrimaryBorder = Colors.cyan;

  // Text Colors
  static const lightTextMain = Colors.black;
  static const lightTextMuted = Colors.black87;
  static const lightTextDim = Colors.black54;

  // --------- ACCENT COLORS ----------------

  static const Color lightAccentCyan = Colors.cyan;
  static const Color darkAccentCyan = Colors.cyanAccent;

  static const Color lightAccentGreen = Colors.green;
  static const Color darkAccentGreen = Colors.greenAccent;

  static const Color lightAccentRed = Colors.red;
  static const Color darkAccentRed = Colors.redAccent;

  static const Color lightAccentAmber = Colors.amber;
  static const Color darkAccentAmber = Colors.amberAccent;

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
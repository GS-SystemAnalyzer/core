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
  static const lightPrimaryBorder = Color(0XFF00545D);

  // Text Colors
  static const lightTextMain = Color(0xFF172026);
  static const lightTextMuted = Color(0xFF5F6B72);
  static const lightTextDim = Color(0xFF8A969D);

  // --------- ACCENT COLORS ----------------

  static const Color lightAccentCyan = Color(0xFF00E5FF);
  static const Color darkAccentCyan = Color(0xFF00545D);

  static const Color lightAccentGreen = Color(0xFF69F0AE);
  static const Color darkAccentGreen = Color(0xFF006F3A);

  static const Color lightAccentRed = Color(0xFFFF5252);
  static const Color darkAccentRed = Color(0xFF9D0E0E);

  static const Color lightAccentAmber = Color(0xFFFFC107);
  static const Color darkAccentAmber = Color(0xFF896700);

  static const Color lightAccentPurple = Color(0xFFE040FB);
  static const Color darkAccentPurple = Color(0xFF7E0095);

  static const Color lightAccentBlue = Color(0xFF448AFF);
  static const Color darkAccentBlue = Color(0xFF003082);


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
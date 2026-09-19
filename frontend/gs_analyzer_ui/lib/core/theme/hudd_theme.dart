import 'package:flutter/material.dart';

class HudTheme {
  // Core Color Palette
  static const Color bgBase = Color(0xFF161616);
  static const Color bgPanel = Color(0xFF1E1E1E);
  static const Color primaryBorder = Colors.cyan;

  // Accents
  static const Color accentCyan = Colors.cyanAccent;
  static const Color accentGreen = Colors.greenAccent;
  static const Color accentRed = Colors.redAccent;
  static const Color accentAmber = Colors.amber;

  // Text Colors
  static const Color textMain = Colors.white;
  static const Color textMuted = Colors.white70;
  static const textDim = Colors.white54;

  // Typography
  static const String fontCore = 'Courier';

  // For major section titles
  static const TextStyle headerCyan = TextStyle(
    fontFamily: fontCore,
    color: primaryBorder,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
  );

  // for small description text
  static const TextStyle labelMuted = TextStyle(
    fontFamily: fontCore,
    color: textDim,
    fontSize: 12,
    letterSpacing: 1,
  );

  // For live changing numbers like '8.5 GB', '13 / 17'
  static const TextStyle statGreen = TextStyle(
    fontFamily: fontCore,
    color: accentGreen,
    fontSize: 14,
    fontWeight: FontWeight.bold,
  );

  // For numeric data values like sizes, percentages, counts
  static const TextStyle statCyan = TextStyle(
    fontFamily: fontCore,
    color: accentCyan,
    fontSize: 13,
  );

  // for destructive action like 'ABORT SCAN'
  static const TextStyle actionRed = TextStyle(
    fontFamily: fontCore,
    color: accentRed,
    fontSize: 14,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.5,
  );

  // Standard table/tree text
  static const TextStyle bodyText = TextStyle(
    fontFamily: fontCore,
    color: textMuted,
    fontSize: 13,
  );

  // The standard glowing border bos=x used for HUD widgets
  static BoxDecoration hudPanelDecoration = BoxDecoration(
    color: bgPanel,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: primaryBorder.withValues(alpha: 0.3)),
  );

  // A subtle bottom border for list items
  static BoxDecoration listItemDecoration = const BoxDecoration(
    border: Border(bottom: BorderSide(color: Colors.white10)),
  );

  static Color resolveAccent(String? accentKey) {
    switch (accentKey?.toLowerCase()) {
      case 'cyan':
        return Colors.cyanAccent;
      case 'green':
        return Colors.greenAccent;
      case 'amber':
        return Colors.amber;
      case 'red':
        return Colors.redAccent;
      case 'purple':
        return Colors.purpleAccent;
      case 'blue':
        return Colors.blueAccent;
      default:
        return Colors.cyanAccent;
    }
  }

  static Color resolveBgBase(String? theme) {
    switch (theme?.toLowerCase()) {
      case 'cyber_light':
        return const Color(0xFFF0F0F0);
      case 'cyber_dark':
      default:
        return const Color(0xFF161616);
    }
  }

  // Helper for Panel backgrounds in Light Mode
  static Color resolveBgPanel(String? theme) {
    switch (theme?.toLowerCase()) {
      case 'cyber_light':
        return const Color(0xFFFFFFFF); // Pure white panel
      case 'cyber_dark':
        return const Color(0xFF1E1E1E); // Original dark panel
      default:
        return const Color(0xFF1E1E1E);
    }
  }

  // Helper for borders in Light Mode
  static Color resolveBorderColor(String? theme) {
    switch (theme?.toLowerCase()) {
      case 'cyber_light':
        return Colors.grey.shade700;
      case 'cyber_dark':
        return Colors.cyanAccent;
      default:
        return Colors.cyanAccent;
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

import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

class ReportPalette {
  final String bgDark;
  final String bgPanel;
  final String bgCard;
  final String textPrimary;
  final String textDim;
  final String accentCyan;
  final String borderColor;
  final Map<String, String> categoryColors;

  const ReportPalette({
    required this.bgDark,
    required this.bgPanel,
    required this.bgCard,
    required this.textPrimary,
    required this.textDim,
    required this.accentCyan,
    required this.borderColor,
    required this.categoryColors,
  });

  static String toCssHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  factory ReportPalette.fromHudTheme(HudThemeExtension hud) {
    const categories = [
      'media',
      'documents',
      'code',
      'executables',
      'archives',
      'system',
      'other',
    ];

    return ReportPalette(
      bgDark: toCssHex(hud.base),
      bgPanel: toCssHex(hud.panel),
      bgCard: toCssHex(hud.listItemDecoration.color ?? hud.panel),
      textPrimary: toCssHex(hud.textMain),
      textDim: toCssHex(hud.textDim),
      accentCyan: toCssHex(hud.accentCyan),
      borderColor: toCssHex(hud.border),
      categoryColors: {
        for (final cat in categories) cat: toCssHex(hud.fileTypeColor(cat)),
      },
    );
  }
}

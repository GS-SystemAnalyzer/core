import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';

class ReportPalette {
  final String bgBase;
  final String bgPanel;
  final String bgCard;
  final String textPrimary;
  final String textDim;
  final String accentColor;
  final String borderColor;
  final Map<String, String> categoryColors;

  const ReportPalette({
    required this.bgBase,
    required this.bgPanel,
    required this.bgCard,
    required this.textPrimary,
    required this.textDim,
    required this.accentColor,
    required this.borderColor,
    required this.categoryColors,
  });

  String get bgDark => bgBase;
  String get accentCyan => accentColor;

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
      bgBase: toCssHex(hud.base),
      bgPanel: toCssHex(hud.panel),
      bgCard: toCssHex(hud.listItemDecoration.color ?? hud.panel),
      textPrimary: toCssHex(hud.textMain),
      textDim: toCssHex(hud.textDim),
      accentColor: toCssHex(hud.accentColor),
      borderColor: toCssHex(hud.border),
      categoryColors: {
        for (final cat in categories) cat: toCssHex(hud.fileTypeColor(cat)),
      },
    );
  }
}

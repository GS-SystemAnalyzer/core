import 'package:flutter/material.dart';

@immutable
class HudThemeExtension extends ThemeExtension<HudThemeExtension> {
  final Color background;
  final Color panel;
  final Color text;
  final Color border;
  final Color accentRed;
  final Color accentCyan;
  final Color accentGreen;
  final Color accentAmber;
  final Color accentPurple;
  final Color accentBlue;
  final Color textDim;
  final BoxDecoration hudPanelDecoration;
  final BoxDecoration listItemDecoration;

  const HudThemeExtension({
    required this.background,
    required this.panel,
    required this.text,
    required this.border,
    required this.accentRed,
    required this.accentCyan,
    required this.accentGreen,
    required this.accentAmber,
    required this.accentPurple,
    required this.accentBlue,
    required this.textDim,
    required this.hudPanelDecoration,
    required this.listItemDecoration
  });

  @override
  HudThemeExtension copyWith({
    Color? background,
    Color? panel,
    Color? text,
    Color? border,
    Color? accentRed,
    Color? accentCyan,
    Color? accentGreen,
    Color? accentAmber,
    Color? accentPurple,
    Color? accentBlue,
    Color? textDim,
    BoxDecoration? hudPanelDecoration,
    BoxDecoration? listItemDecoration
  }) {
    return HudThemeExtension(
      background: background ?? this.background,
      panel: panel ?? this.panel,
      text: text ?? this.text,
      border: border ?? this.border,
      accentRed: accentRed ?? this.accentRed,
      accentCyan: accentCyan ?? this.accentCyan,
      accentGreen: accentGreen ?? this.accentGreen,
      accentAmber: accentAmber ?? this.accentAmber,
      accentPurple: accentPurple ?? this.accentPurple,
      accentBlue: accentBlue ?? this.accentBlue,
      textDim: textDim ?? this.textDim,
      hudPanelDecoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border!.withValues(alpha: 0.3)),
      ),
      listItemDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: (text ?? Colors.white10).withValues(alpha: 0.1)))
      )
    );
  }

  @override
  HudThemeExtension lerp(covariant HudThemeExtension? other, double t) {
    if (other == null) return this;

    return HudThemeExtension(
      background: Color.lerp(background, other.background, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      text: Color.lerp(text, other.text, t)!,
      border: Color.lerp(border, other.border, t)!,
      accentRed: Color.lerp(accentRed, other.accentRed, t)!,
      accentCyan: Color.lerp(accentCyan, other.accentCyan, t)!,
      accentGreen: Color.lerp(accentGreen, other.accentGreen, t)!,
      accentAmber: Color.lerp(accentAmber, other.accentAmber, t)!,
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      hudPanelDecoration: BoxDecoration.lerp(hudPanelDecoration, other.hudPanelDecoration, t)!,
      listItemDecoration: BoxDecoration.lerp(listItemDecoration, other.listItemDecoration, t)!
    );
  }
}
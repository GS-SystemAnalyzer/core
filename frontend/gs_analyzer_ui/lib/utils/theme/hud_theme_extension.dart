import 'package:flutter/material.dart';

class HudThemeExtension extends ThemeExtension<HudThemeExtension> {
  final Color accentColor;
  final Color base;
  final Color panel;
  final Color border;
  final Color accentCyan;
  final Color accentGreen;
  final Color accentRed;
  final Color accentAmber;
  final Color accentPurple;
  final Color accentBlue;
  final Color textMain;
  final Color textMuted;
  final Color textDim;
  final TextStyle header;
  final TextStyle label;
  final TextStyle statGreen;
  final TextStyle statCyan;
  final TextStyle actionRed;
  final TextStyle body;
  final BoxDecoration hudPanelDecoration;
  final BoxDecoration listItemDecoration;

  const HudThemeExtension({
    required this.accentColor,
    required this.base,
    required this.panel,
    required this.border,
    required this.accentCyan,
    required this.accentGreen,
    required this.accentRed,
    required this.accentAmber,
    required this.accentPurple,
    required this.accentBlue,
    required this.textMain,
    required this.textMuted,
    required this.textDim,
    required this.header,
    required this.label,
    required this.statGreen,
    required this.statCyan,
    required this.actionRed,
    required this.body,
    required this.hudPanelDecoration,
    required this.listItemDecoration
  });

  @override
  HudThemeExtension copyWith({
    Color? accentColor,
    Color? base,
    Color? panel,
    Color? border,
    Color? accentCyan,
    Color? accentGreen,
    Color? accentRed,
    Color? accentAmber,
    Color? accentPurple,
    Color? accentBlue,
    Color? textMain,
    Color? textMuted,
    Color? textDim,
    TextStyle? header,
    TextStyle?label,
    TextStyle? statGreen,
    TextStyle? statCyan,
    TextStyle? actionRed,
    TextStyle? body,
    BoxDecoration? hudPanelDecoration,
    BoxDecoration? listItemDecoration
  }) {
    return HudThemeExtension(
      accentColor: accentColor ?? this.accentColor,
      base: base ?? this.base, 
      panel: panel ?? this.panel, 
      border: border ?? this.border, 
      accentCyan: accentCyan ?? this.accentCyan, 
      accentGreen: accentGreen ?? this.accentGreen, 
      accentRed: accentRed ?? this.accentRed, 
      accentAmber: accentAmber ?? this.accentAmber, 
      accentPurple: accentPurple ?? this.accentPurple, 
      accentBlue: accentBlue ?? this.accentBlue, 
      textMain: textMain ?? this.textMain, 
      textMuted: textMuted ?? this.textMuted, 
      textDim: textDim ?? this.textDim, 
      header: header ?? this.header,
      label: label ?? this.label,
      statGreen: statGreen ?? this.statGreen,
      statCyan: statCyan ?? this.statCyan,
      actionRed: actionRed ?? this.actionRed,
      body: body ?? this.body,
      hudPanelDecoration: hudPanelDecoration ?? this.hudPanelDecoration, 
      listItemDecoration: listItemDecoration ?? this.listItemDecoration
    );
  }

  @override
  HudThemeExtension lerp(covariant HudThemeExtension? other, double t) {
    if (other == null) return this;

    return HudThemeExtension(
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      base: Color.lerp(base, other.base, t)!, 
      panel: Color.lerp(panel, other.panel, t)!, 
      border: Color.lerp(border, other.border, t)!, 
      accentCyan: Color.lerp(accentCyan, other.accentCyan, t)!, 
      accentGreen: Color.lerp(accentGreen, other.accentGreen, t)!, 
      accentRed: Color.lerp(accentRed, other.accentRed, t)!, 
      accentAmber: Color.lerp(accentAmber, other.accentAmber, t)!, 
      accentPurple: Color.lerp(accentPurple, other.accentPurple, t)!, 
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!, 
      textMain: Color.lerp(textMain, other.textMain, t)!, 
      textMuted: Color.lerp(textMuted, other.textMuted, t)!, 
      textDim: Color.lerp(textDim, other.textDim, t)!, 
      header: TextStyle.lerp(header, other.header, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      actionRed: TextStyle.lerp(actionRed, other.actionRed, t)!,
      statGreen: TextStyle.lerp(statGreen, other.statGreen, t)!,
      statCyan: TextStyle.lerp(statCyan, other.statCyan, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      hudPanelDecoration: BoxDecoration.lerp(hudPanelDecoration, other.hudPanelDecoration, t)!,
      listItemDecoration: BoxDecoration.lerp(listItemDecoration, other.listItemDecoration, t)!
    );
  }
}
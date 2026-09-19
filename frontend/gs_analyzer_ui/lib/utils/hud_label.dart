import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class HudLabel extends StatelessWidget {
  final String text;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const HudLabel(
    this.text, {
    super.key,
    this.textAlign,
    this.overflow = TextOverflow.ellipsis,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: HudTheme.labelMuted,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}

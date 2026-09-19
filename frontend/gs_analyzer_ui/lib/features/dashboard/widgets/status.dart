import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class Status extends StatelessWidget {
  final String status;
  
  const Status({
    super.key,
    required this.status
  });

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch(status) {
      'RUNNING' => (HudTheme.accentGreen.withValues(alpha: 0.15), HudTheme.accentGreen),
      'SLEEPING' => (Colors.white.withValues(alpha: 0.06),  HudTheme.textDim),
      'ZOMBIE' => (HudTheme.accentRed.withValues(alpha: 0.15), HudTheme.accentRed),
      _ => (HudTheme.accentRed.withValues(alpha: 0.15), HudTheme.accentRed)
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg, 
        borderRadius: BorderRadius.circular(4)
      ),
      child: Text(
        status,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontFamily: HudTheme.fontCore,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8
        ),
      ),
    );
  }
}
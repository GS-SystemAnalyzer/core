import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class Status extends StatelessWidget {
  final String status;
  
  const Status({
    super.key,
    required this.status
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.HudTheme;
    final (bg, fg) = switch(status) {
      'RUNNING' => (theme.accentGreen.withValues(alpha: 0.15), theme.accentGreen),
      'SLEEPING' => (theme.textMain.withValues(alpha: 0.06),  theme.textDim),
      'ZOMBIE' => (theme.accentRed.withValues(alpha: 0.15), theme.accentRed),
      _ => (theme.accentRed.withValues(alpha: 0.15), theme.accentRed)
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
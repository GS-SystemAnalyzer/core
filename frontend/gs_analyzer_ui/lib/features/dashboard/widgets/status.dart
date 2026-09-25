import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_text_theme.dart';

class Status extends StatelessWidget {
  final String status;
  
  const Status({
    super.key,
    required this.status
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (bg, fg) = switch(status) {
      'RUNNING' => (theme.colorScheme.secondary.withValues(alpha: 0.15), theme.colorScheme.secondary),
      'SLEEPING' => (theme.colorScheme.onSurface.withValues(alpha: 0.06),  theme.colorScheme.surfaceDim),
      'ZOMBIE' => (theme.colorScheme.error.withValues(alpha: 0.15), theme.colorScheme.error),
      _ => (theme.colorScheme.error.withValues(alpha: 0.15), theme.colorScheme.error)
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
          fontFamily: HudTextTheme.fontCore,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8
        ),
      ),
    );
  }
}
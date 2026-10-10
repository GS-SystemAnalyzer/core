import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'dart:math';

import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';


String formatBytes(int bytes) {
  if (bytes < 0) return "--";
  if (bytes == 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (log(bytes) / log(1024)).floor();
  double val = bytes / pow(1024, i);
  return '${val < 10 && i > 0 ? val.toStringAsFixed(1) : val.toStringAsFixed(0)} ${suffixes[i]}';
}

class DriveTelemetryWidget extends ConsumerWidget {
  const DriveTelemetryWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(currentDriveProvider);

    final alertSettings = ref.watch(settingsProvider).currentSettings?.alerts;
    final redThreshold = alertSettings?.diskThresholdPercent ?? 90;
    final hud = context.hudTheme;

    if (stats == null) {
      return SizedBox(
        height: 60,
        child: Center(
          child: LinearProgressIndicator(color: hud.accentCyan),
        ),
      );
    }

    final double usageFraction = stats.percentageUsed / 100.0;
    final bool isCritical = stats.percentageUsed >= redThreshold;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: hud.base,
        border: Border(
          top: BorderSide(
            color: isCritical ? hud.accentRed : hud.textMain.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HudLabel('CAPACITY (${stats.name})'),
              if (isCritical)
                Text('LOW SPACE ALERT', style: hud.actionRed),
              Text(
                '${stats.percentageFree.toStringAsFixed(1)}% FREE',
                style: isCritical ? hud.actionRed : hud.statGreen,
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usageFraction,
            backgroundColor: hud.textMain.withValues(alpha: 0.1),
            color: isCritical ? hud.accentRed : hud.accentGreen,
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HudLabel('${formatBytes(stats.usedBytes)} USED'),
              HudLabel('${formatBytes(stats.totalBytes)} TOTAL'),
            ],
          ),
        ],
      ),
    );
  }
}

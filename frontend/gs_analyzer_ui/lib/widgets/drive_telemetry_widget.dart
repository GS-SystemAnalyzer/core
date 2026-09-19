import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'dart:math';

import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

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

    if (stats == null) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: LinearProgressIndicator(color: HudTheme.accentCyan),
        ),
      );
    }

    final double usageFraction = stats.percentageUsed / 100.0;
    final bool isCritical = stats.percentageUsed >= redThreshold;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: HudTheme.bgBase,
        border: Border(
          top: BorderSide(
            color: isCritical ? HudTheme.accentRed : Colors.white10,
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
                const Text('LOW SPACE ALERT', style: HudTheme.actionRed),
              Text(
                '${stats.percentageFree.toStringAsFixed(1)}% FREE',
                style: isCritical ? HudTheme.actionRed : HudTheme.statGreen,
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usageFraction,
            backgroundColor: Colors.white10,
            color: isCritical ? HudTheme.accentRed : HudTheme.accentGreen,
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

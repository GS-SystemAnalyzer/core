import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gs_analyzer_ui/models/cpu_snapshot.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class CpuSummaryDialog extends StatelessWidget {
  final CpuSnapshot snapshot;
  final List<double> history;

  const CpuSummaryDialog({
    super.key,
    required this.snapshot,
    this.history = const [],
  });

  @override
  Widget build(BuildContext context) {
    final hud = context.hudTheme;

    final double minLoad = history.isNotEmpty
        ? history.reduce(math.min)
        : snapshot.averageLoad;
    final double maxLoad = history.isNotEmpty
        ? history.reduce(math.max)
        : snapshot.averageLoad;
    final double avgLoad = history.isNotEmpty
        ? history.reduce((a, b) => a + b) / history.length
        : snapshot.averageLoad;

    // Identify hottest core
    String hottestCore = 'N/A';
    double highestLoad = -1.0;
    int totalCores = 0;
    for (final entry in snapshot.coreGroups.entries) {
      for (final load in entry.value) {
        totalCores++;
        if (load > highestLoad) {
          highestLoad = load;
          hottestCore = entry.key;
        }
      }
    }

    final isCritical = snapshot.averageLoad >= 95.0;
    final isPressure = snapshot.averageLoad >= 80.0 && !isCritical;
    final statusColor = isCritical
        ? hud.accentRed
        : isPressure
            ? hud.accentAmber
            : hud.accentCyan;
    final statusLabel = isCritical
        ? 'CRITICAL LOAD'
        : isPressure
            ? 'HIGH PRESSURE'
            : 'NORMAL STATUS';

    return AlertDialog(
      backgroundColor: hud.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: statusColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.query_stats, color: hud.accentCyan, size: 22),
              const SizedBox(width: 8),
              Text(
                'CPU TELEMETRY SUMMARY',
                style: hud.header.copyWith(fontSize: 16),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              border: Border.all(color: statusColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('REAL-TIME UTILIZATION', style: hud.label),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildMetricCard(
                    context,
                    label: 'CURRENT LOAD',
                    value: '${snapshot.averageLoad.toStringAsFixed(1)}%',
                    color: statusColor,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    context,
                    label: 'DELTA',
                    value: '${snapshot.delta >= 0 ? '+' : ''}${snapshot.delta.toStringAsFixed(1)}%',
                    color: snapshot.delta > 0 ? hud.accentAmber : hud.accentCyan,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    context,
                    label: 'SESSION AVG',
                    value: '${avgLoad.toStringAsFixed(1)}%',
                    color: hud.accentCyan,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildMetricCard(
                    context,
                    label: 'SESSION MIN',
                    value: '${minLoad.toStringAsFixed(1)}%',
                    color: hud.accentGreen,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    context,
                    label: 'SESSION MAX',
                    value: '${maxLoad.toStringAsFixed(1)}%',
                    color: maxLoad > 80 ? hud.accentAmber : hud.accentCyan,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricCard(
                    context,
                    label: 'FREQUENCY',
                    value: '${snapshot.currentFrequencyGhz.toStringAsFixed(2)} GHz',
                    color: hud.accentCyan,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: hud.textMain.withValues(alpha: 0.1)),
              const SizedBox(height: 8),
              Text('SYSTEM & PROCESS TELEMETRY', style: hud.label),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildInfoChip(context, 'PROCESSES', '${snapshot.totalProcesses}'),
                  const SizedBox(width: 8),
                  _buildInfoChip(context, 'THREADS', '${snapshot.totalThreads}'),
                  const SizedBox(width: 8),
                  _buildInfoChip(context, 'HANDLES', '${snapshot.totalHandles}'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildInfoChip(context, 'L1 CACHE', snapshot.l1Cache),
                  const SizedBox(width: 8),
                  _buildInfoChip(context, 'L2 CACHE', snapshot.l2Cache),
                  const SizedBox(width: 8),
                  _buildInfoChip(context, 'L3 CACHE', snapshot.l3Cache),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: hud.textMain.withValues(alpha: 0.1)),
              const SizedBox(height: 8),
              Text('CORE TOPOLOGY', style: hud.label),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildInfoChip(context, 'ACTIVE CORES', '$totalCores cores'),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    context,
                    'HOTTEST CORE',
                    highestLoad >= 0
                        ? '$hottestCore (${highestLoad.toStringAsFixed(1)}%)'
                        : 'N/A',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: hud.accentCyan.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: () {
            final summaryText = '''
[CPU TELEMETRY REPORT]
Status: $statusLabel
Current Load: ${snapshot.averageLoad.toStringAsFixed(1)}% (Delta: ${snapshot.delta >= 0 ? '+' : ''}${snapshot.delta.toStringAsFixed(1)}%)
Session Range: Min ${minLoad.toStringAsFixed(1)}% | Max ${maxLoad.toStringAsFixed(1)}% | Avg ${avgLoad.toStringAsFixed(1)}%
Clock Frequency: ${snapshot.currentFrequencyGhz.toStringAsFixed(2)} GHz
Processes: ${snapshot.totalProcesses} | Threads: ${snapshot.totalThreads} | Handles: ${snapshot.totalHandles}
Caches: L1: ${snapshot.l1Cache} | L2: ${snapshot.l2Cache} | L3: ${snapshot.l3Cache}
Cores: $totalCores active (Peak: $hottestCore @ ${highestLoad.toStringAsFixed(1)}%)
''';
            Clipboard.setData(ClipboardData(text: summaryText));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
                content: Text(
                  'TELEMETRY SUMMARY COPIED TO CLIPBOARD',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
          icon: Icon(Icons.copy, size: 16, color: hud.accentCyan),
          label: Text(
            'COPY METRICS',
            style: TextStyle(
              fontFamily: HudTheme.fontCore,
              color: hud.accentCyan,
              fontSize: 12,
            ),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: hud.accentCyan.withValues(alpha: 0.15),
            foregroundColor: hud.accentCyan,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: hud.accentCyan),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'CLOSE',
            style: TextStyle(
              fontFamily: HudTheme.fontCore,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    final hud = context.hudTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: hud.base.withValues(alpha: 0.6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: hud.label.copyWith(fontSize: 10)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, String label, String value) {
    final hud = context.hudTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: hud.base.withValues(alpha: 0.4),
          border: Border.all(color: hud.textMain.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: hud.label.copyWith(fontSize: 9)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                fontSize: 12,
                color: hud.textMain,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';
import 'package:gs_analyzer_ui/providers/disk_io_provider.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/utils/hud_theme.dart';

class DiskIoCard extends ConsumerWidget {
  final DiskIoSnapshot? overrideDisk;

  const DiskIoCard({super.key, this.overrideDisk});

  Color _getQueueColor(double queueLength) {
    if (queueLength < 2.0) return HudTheme.accentGreen;
    if (queueLength <= 5.0) return HudTheme.accentAmber;
    return HudTheme.accentRed;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(diskIoProvider);
    final disk = overrideDisk ?? ref.watch(currentDriveDiskIoProvider);

    if (disk == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HudTheme.bgBase,
          border: Border.all(color: Colors.white10),
        ),
        child: const SizedBox(
          height: 80,
          child: Center(
            child: LinearProgressIndicator(color: HudTheme.accentCyan),
          ),
        ),
      );
    }

    final lettersLabel = disk.driveLetters.isNotEmpty
        ? disk.driveLetters.map((l) => '[$l]').join(' ')
        : 'UNMAPPED';

    final isUnmapped = disk.driveLetters.isEmpty;

    final clampedActivePercent = disk.activeTimePercent > 100.0
        ? 100.0
        : disk.activeTimePercent;

    final queueColor = _getQueueColor(disk.avgQueueLength);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HudTheme.bgBase,
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  HudLabel('DISK_${disk.id}'),
                  const SizedBox(width: 8),
                  Text(
                    lettersLabel,
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isUnmapped ? HudTheme.textDim : HudTheme.accentCyan,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  disk.model,
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    fontSize: 11,
                    color: HudTheme.textDim,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Throughput rates
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    '▼ READ: ',
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: HudTheme.accentCyan,
                    ),
                  ),
                  Text(
                    formatRate(disk.readBytesPerSec),
                    style: const TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: HudTheme.accentCyan,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    '▲ WRITE: ',
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: HudTheme.accentAmber,
                    ),
                  ),
                  Text(
                    formatRate(disk.writeBytesPerSec),
                    style: const TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: HudTheme.accentAmber,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Pressure row: ACTIVE % and QUEUE
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tooltip(
                message: 'Raw: ${disk.activeTimePercent.toStringAsFixed(1)}%',
                child: Row(
                  children: [
                    const Text(
                      'ACTIVE: ',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                    Text(
                      '${clampedActivePercent.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontFamily: HudTheme.fontCore,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  const Text(
                    'QUEUE: ',
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  Text(
                    disk.avgQueueLength.toStringAsFixed(2),
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: queueColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sparkline Chart (60 rolling points)
          SizedBox(
            height: 70,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 59,
                minY: 0,
                maxY: state.rollingMaxY,
                titlesData: const FlTitlesData(show: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  // Read Rate (Cyan)
                  LineChartBarData(
                    spots: state.readRollingSpots.isNotEmpty
                        ? state.readRollingSpots
                        : [const FlSpot(0, 0)],
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: HudTheme.accentCyan,
                    barWidth: 1.8,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: HudTheme.accentCyan.withValues(alpha: 0.1),
                    ),
                  ),
                  // Write Rate (Amber)
                  LineChartBarData(
                    spots: state.writeRollingSpots.isNotEmpty
                        ? state.writeRollingSpots
                        : [const FlSpot(0, 0)],
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: HudTheme.accentAmber,
                    barWidth: 1.8,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: HudTheme.accentAmber.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Session totals row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SESSION READ: ${formatBytes(disk.sessionReadBytes)}',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  fontSize: 11,
                  color: Colors.white54,
                ),
              ),
              Text(
                'SESSION WRITE: ${formatBytes(disk.sessionWriteBytes)}',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  fontSize: 11,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

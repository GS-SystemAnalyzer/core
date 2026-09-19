import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class CpuBarChart extends StatelessWidget {
  final Map<String, List<double>> coreGroups;

  const CpuBarChart({super.key, required this.coreGroups});

  @override
  Widget build(BuildContext context) {
    final labels = coreGroups.keys.toList();
    final barGroups = <BarChartGroupData>[];

    int x = 0;
    for (final entry in coreGroups.entries) {
      barGroups.add(
        BarChartGroupData(
          x: x++,
          barsSpace: 6,
          barRods: entry.value.map((load) {
            return BarChartRodData(
              toY: load,
              color: load > 80 ? HudTheme.accentAmber : HudTheme.accentCyan,
              width: 14,
              borderRadius: BorderRadius.circular(3),
            );
          }).toList(),
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: 100,
        minY: 0,
        barGroups: barGroups,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: Colors.white12,
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(labels[index], style: HudTheme.labelMuted),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class CpuLineChart extends StatelessWidget {
  final List<double> history;

  const CpuLineChart({
    super.key,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final hud = context.hudTheme;

    // Ensure we have at least 2 spots to draw a line segment
    final List<double> safePoints = history.isEmpty
        ? const [0.0, 0.0]
        : history.length == 1
            ? [history.first, history.first]
            : history;

    final latestValue = safePoints.last;
    final isHigh = latestValue > 80.0;
    final lineColor = isHigh ? hud.accentAmber : hud.accentCyan;

    final spots = <FlSpot>[];
    for (int i = 0; i < safePoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), safePoints[i].clamp(0.0, 100.0)));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        minX: 0,
        maxX: (safePoints.length - 1).toDouble().clamp(1.0, double.infinity),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => hud.panel,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}%',
                  TextStyle(
                    color: lineColor,
                    fontFamily: HudTheme.fontCore,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: hud.textMain.withValues(alpha: 0.12),
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: hud.textMain.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 50,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == 50 || value == 100) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: Text(
                      '${value.toInt()}%',
                      style: hud.label.copyWith(fontSize: 9),
                      textAlign: TextAlign.right,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: lineColor,
            barWidth: 2.2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: safePoints.length <= 1,
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  lineColor.withValues(alpha: 0.25),
                  lineColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/models/cpu_snapshot.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';

class CpuMetricsScreen extends ConsumerStatefulWidget {
  const CpuMetricsScreen({super.key});

  @override
  ConsumerState<CpuMetricsScreen> createState() => _CpuMetricsScreenState();
}

class _CpuMetricsScreenState extends ConsumerState<CpuMetricsScreen> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final cpuState = ref.watch(cpuProvider);
    final snapshot = cpuState.snapshot;
    final d = ref.watch(hudDensityProvider);
    final theme = context.HudTheme;

    return Padding(
      padding: EdgeInsets.all(d.panelPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CPU TELEMETRY MODULE', style: theme.header),

              // Custom Toggle Strip
              Row(
                children: [
                  _buildToggleBtn('LIVE VIEW', !_showHistory),
                  _buildToggleBtn('HISTORY', _showHistory),
                ],
              ),

              if (cpuState.isCritical && !_showHistory)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.accentRed.withValues(alpha: 0.2),
                    border: Border.all(color: theme.accentRed),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('CRITICAL LOAD', style: theme.actionRed),
                ),
            ],
          ),
          SizedBox(height: d.gap * 2),
          if (_showHistory)
            const Expanded(child: TelemetryHistoryChart(metricKey: 'cpu'))
          else if (snapshot == null)
            Expanded(
              child: Center(
                child: CircularProgressIndicator(color: theme.border),
              ),
            )
          else
            d.isMax
                ? Expanded(child: _buildDashBoard(context, snapshot, d))
                : Expanded(
                    child: SingleChildScrollView(
                      child: _buildDashBoard(context, snapshot, d),
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool isSelected) {
    final theme = context.HudTheme;
    return InkWell(
      onTap: () {
        setState(() {
          _showHistory = label == 'HISTORY';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.accentCyan.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? theme.accentCyan : theme.textMain.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: isSelected ? theme.accentCyan : theme.textDim,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildDashBoard(
    BuildContext context,
    CpuSnapshot snapshot,
    HudDensity d,
  ) {
    final theme = context.HudTheme;
    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: theme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('CPU UTILIZATION [AVG]', style: theme.label),
              Icon(Icons.memory_outlined, color: theme.accentCyan, size: 24),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${snapshot.averageLoad.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: theme.accentCyan,
                  fontSize: d.valueSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: HudTheme.fontCore,
                ),
              ),
            ],
          ),
          SizedBox(height: d.gap),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'FREQ → ${snapshot.currentFrequencyGhz} Ghz | PROC → ${snapshot.totalProcesses} | THREADS → ${snapshot.totalThreads} | HANDLES → ${snapshot.totalHandles}',
              style: theme.body,
            ),
          ),
          SizedBox(height: d.gap),
          Wrap(
            spacing: d.gap,
            runSpacing: d.gap,
            children: [
              _buildCacheChip('L1', snapshot.l1Cache),
              _buildCacheChip('L2', snapshot.l2Cache),
              _buildCacheChip('L3', snapshot.l3Cache),
            ],
          ),
          SizedBox(height: d.gap * 2),
          d.isMax
              ? Expanded(child: _buildCoreCharts(snapshot.coreGroups))
              : SizedBox(
                  height: 300,
                  child: _buildCoreCharts(snapshot.coreGroups),
                ),
        ],
      ),
    );
  }

  Widget _buildCacheChip(String label, String value) {
    final theme = context.HudTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.accentCyan.withValues(alpha: 0.1),
        border: Border.all(color: theme.accentCyan.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: theme.statGreen.copyWith(
          color: theme.accentCyan,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCoreCharts(Map<String, List<double>> coreGroups) {
    final theme = context.HudTheme;
    List<BarChartGroupData> barGroups = [];
    List<String> groupLabels = [];
    int xIndex = 0;

    for (var entry in coreGroups.entries) {
      groupLabels.add(entry.key);
      List<BarChartRodData> rods = [];
      for (var coreLoad in entry.value) {
        rods.add(
          BarChartRodData(
            toY: coreLoad,
            color: coreLoad > 80.0 ? theme.accentAmber : theme.accentCyan,
            width: 12,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        );
      }
      barGroups.add(BarChartGroupData(x: xIndex, barRods: rods, barsSpace: 6));
      xIndex++;
    }

    return BarChart(
      BarChartData(
        maxY: 100,
        minY: 0,
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: theme.textMain.withValues(alpha: 0.12),
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (value.toInt() >= 0 && value.toInt() < groupLabels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      groupLabels[value.toInt()],
                      style: theme.label
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
      ),
      duration: Duration.zero,
    );
  }
}

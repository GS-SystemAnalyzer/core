import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gs_analyzer_ui/providers/telemetry_history_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:intl/intl.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';

class TelemetryHistoryChart extends ConsumerStatefulWidget {
  final String metricKey;

  const TelemetryHistoryChart({super.key, required this.metricKey});

  @override
  ConsumerState<TelemetryHistoryChart> createState() =>
      _TelemetryHistoryChartState();
}

class _TelemetryHistoryChartState extends ConsumerState<TelemetryHistoryChart> {
  late String _currentMetricKey;

  @override
  void initState() {
    super.initState();
    _currentMetricKey = widget.metricKey;
  }

  @override
  void didUpdateWidget(covariant TelemetryHistoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metricKey != widget.metricKey &&
        !widget.metricKey.startsWith('ram')) {
      _currentMetricKey = widget.metricKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(telemetryHistoryProvider(_currentMetricKey));
    final notifier = ref.read(
      telemetryHistoryProvider(_currentMetricKey).notifier,
    );
    final theme = context.HudTheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.panel,
        border: Border.all(color: theme.textMain.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header & Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildHeaderTitle(),
                Row(
                  children: [
                    if (widget.metricKey.startsWith('ram')) _buildRamToggle(),
                    const SizedBox(width: 16),
                    _buildTimeRangeSelector(state.minutes, notifier.setMinutes),
                  ],
                ),
              ],
            ),
          ),

          Divider(height: 1, color: theme.textMain.withValues(alpha: 0.1)),

          // Chart Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _buildChartContent(state),
            ),
          ),

          Divider(height: 1, color: theme.textMain.withValues(alpha: 0.1)),

          // Stats Strip
          if (state.response != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatChip(
                    'MIN',
                    state.response!.stats.min,
                    state.response!.unit,
                  ),
                  _buildStatChip(
                    'AVG',
                    state.response!.stats.avg,
                    state.response!.unit,
                  ),
                  _buildStatChip(
                    'MAX',
                    state.response!.stats.max,
                    state.response!.unit,
                  ),
                  _buildStatChip(
                    'NOW',
                    state.response!.stats.current,
                    state.response!.unit,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderTitle() {
    final theme = context.HudTheme;
    if (_currentMetricKey == 'network_rx') {
      return Text('NETWORK RX (DOWNLOAD)', style: theme.header);
    }
    if (_currentMetricKey == 'network_tx') {
      return Text(
        'NETWORK TX (UPLOAD)',
        style: TextStyle(
          fontFamily: HudTheme.fontCore,
          color: theme.accentAmber,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      );
    }
    String title = _currentMetricKey.toUpperCase().replaceAll('_', ' ');
    return Text(title, style: theme.header);
  }

  Widget _buildRamToggle() {
    final isPercent = _currentMetricKey == 'ram_percent';
    final theme = context.HudTheme;
    return Row(
      children: [
        Text('GB', style: isPercent ? theme.label : theme.statCyan),
        Switch(
          value: isPercent,
          activeThumbColor: theme.accentCyan,
          onChanged: (val) {
            setState(() {
              _currentMetricKey = val ? 'ram_percent' : 'ram';
            });
          },
        ),
        Text('%', style: isPercent ? theme.statCyan : theme.label),
      ],
    );
  }

  Widget _buildTimeRangeSelector(int currentMinutes, Function(int) onSelect) {
    final theme = context.HudTheme;
    return Row(
      children: [5, 15, 30, 60].map((mins) {
        final isSelected = currentMinutes == mins;
        final label = mins == 60 ? '1H' : '${mins}M';
        return InkWell(
          onTap: () => onSelect(mins),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? theme.accentCyan : theme.textMain.withValues(alpha: 0.1),
              ),
              color: isSelected
                  ? theme.accentCyan.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: isSelected ? theme.accentCyan : theme.textDim,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatChip(String label, double value, String unit) {
    final displayValue = unit == 'B/s'
        ? formatRate(value)
        : '${value.toStringAsFixed(1)} $unit';
        final theme = context.HudTheme;
    return Row(
      children: [
        Text('$label: ', style: theme.label),
        Text(displayValue, style: theme.statGreen),
      ],
    );
  }

  Widget _buildChartContent(TelemetryHistoryState state) {
    final theme = context.HudTheme;
    if (state.isLoading &&
        (state.response == null || state.response!.points.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.accentCyan),
            SizedBox(height: 16),
            Text('LOADING HISTORY...', style: theme.label),
          ],
        ),
      );
    }

    if (state.response == null || state.response!.points.isEmpty) {
      return Center(
        child: Text(
          'COLLECTING DATA — CHECK BACK IN A MOMENT',
          style: theme.label,
        ),
      );
    }

    final points = state.response!.points;
    final unit = state.response!.unit;
    final isPercent = unit == '%' || _currentMetricKey.contains('percent');
    final isRate = unit == 'B/s' || _currentMetricKey.startsWith('network_');
    final chartColor = _currentMetricKey == 'network_tx'
        ? theme.accentAmber
        : theme.accentCyan;

    final spots = points.map((p) {
      return FlSpot(p.timestamp.millisecondsSinceEpoch.toDouble(), p.value);
    }).toList();

    final double maxX = spots.last.x;
    final double minX = maxX - (state.minutes * 60 * 1000);

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: isPercent ? 0 : null,
        maxY: isPercent ? 100 : null,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          drawHorizontalLine: true,
          horizontalInterval: isPercent ? 25 : null,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: theme.textMain.withValues(alpha: 0.1),
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(color: theme.textMain.withValues(alpha: 0.1), strokeWidth: 1);
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: isRate ? 55 : 40,
              getTitlesWidget: (value, meta) {
                if (isRate) {
                  return Text(
                    formatRate(value),
                    style: theme.label.copyWith(fontSize: 9),
                    textAlign: TextAlign.right,
                  );
                }
                return Text(
                  isPercent
                      ? value.toInt().toString()
                      : value.toStringAsFixed(1),
                  style: theme.label.copyWith(fontSize: 10),
                  textAlign: TextAlign.right,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (maxX - minX) / 5, // 5 evenly spaced ticks
              getTitlesWidget: (value, meta) {
                if (value == minX || value == maxX) return const SizedBox();
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    DateFormat('HH:mm').format(date),
                    style: theme.label.copyWith(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: theme.textMain.withValues(alpha: 0.1)),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => theme.panel,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(
                  spot.x.toInt(),
                );
                final timeStr = DateFormat('HH:mm:ss').format(date);
                final valStr = isRate ? formatRate(spot.y) : '${spot.y} $unit';
                return LineTooltipItem(
                  '$timeStr\n$valStr',
                  TextStyle(
                    color: chartColor,
                    fontFamily: HudTheme.fontCore,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: chartColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: chartColor.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

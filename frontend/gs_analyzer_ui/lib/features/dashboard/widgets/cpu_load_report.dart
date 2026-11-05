import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_bar_chart.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_line_chart.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_summary_dialog.dart';
import 'package:gs_analyzer_ui/models/cpu_snapshot.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

enum CpuChartType {
  line,
  bar,
}

class CpuLoadReport extends ConsumerStatefulWidget {
  const CpuLoadReport({super.key});

  @override
  ConsumerState<CpuLoadReport> createState() => _CpuLoadReportState();
}

class _CpuLoadReportState extends ConsumerState<CpuLoadReport> {
  CpuChartType _chartType = CpuChartType.line;

  void _showSummaryDialog(
    BuildContext context,
    CpuSnapshot snapshot,
    List<double> history,
  ) {
    showDialog(
      context: context,
      builder: (context) => CpuSummaryDialog(
        snapshot: snapshot,
        history: history,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cpuState = ref.watch(cpuProvider);
    final snapShot = cpuState.snapshot;
    final hud = context.hudTheme;

    if (snapShot == null) {
      return CustomContainer(
        color: hud.panel,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 240,
          child: Center(
            child: Text(
              'COLLECTING DATA — CHECK BACK IN A MOMENT',
              style: hud.label,
            ),
          ),
        ),
      );
    }

    final effectiveHistory = cpuState.history.isNotEmpty
        ? cpuState.history
        : [snapShot.averageLoad];

    return CustomContainer(
      color: hud.panel,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ListTile(
            isThreeLine: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'CPU LOAD [AVG]',
              style: hud.label,
            ),
            subtitle: Row(
              children: [
                RichText(
                  text: TextSpan(
                    text: snapShot.averageLoad.toStringAsFixed(1),
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      color: hud.accentCyan,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    children: const [
                      TextSpan(
                        text: '%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            trailing: PopupMenuButton<CpuChartType>(
              tooltip: 'Switch Graph Type',
              initialValue: _chartType,
              color: hud.panel,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: hud.accentCyan.withValues(alpha: 0.5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              onSelected: (type) {
                setState(() {
                  _chartType = type;
                });
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: CpuChartType.line,
                  child: Row(
                    children: [
                      Icon(Icons.show_chart, size: 16, color: hud.accentCyan),
                      const SizedBox(width: 8),
                      Text(
                        'LINE (TREND)',
                        style: TextStyle(
                          fontFamily: HudTheme.fontCore,
                          color: _chartType == CpuChartType.line
                              ? hud.accentCyan
                              : hud.textMain,
                          fontWeight: _chartType == CpuChartType.line
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: CpuChartType.bar,
                  child: Row(
                    children: [
                      Icon(Icons.bar_chart, size: 16, color: hud.accentCyan),
                      const SizedBox(width: 8),
                      Text(
                        'BAR (CORES)',
                        style: TextStyle(
                          fontFamily: HudTheme.fontCore,
                          color: _chartType == CpuChartType.bar
                              ? hud.accentCyan
                              : hud.textMain,
                          fontWeight: _chartType == CpuChartType.bar
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: hud.accentCyan.withValues(alpha: 0.1),
                  border: Border.all(
                    color: hud.accentCyan.withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _chartType == CpuChartType.line
                          ? Icons.show_chart
                          : Icons.bar_chart,
                      size: 16,
                      color: hud.accentCyan,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _chartType == CpuChartType.line ? 'LINE' : 'BAR',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: hud.accentCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: hud.accentCyan,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onSecondaryTapDown: (_) =>
                _showSummaryDialog(context, snapShot, effectiveHistory),
            onLongPress: () =>
                _showSummaryDialog(context, snapShot, effectiveHistory),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Tooltip(
                message: 'Right-click for telemetry summary',
                waitDuration: const Duration(milliseconds: 600),
                child: SizedBox(
                  height: 140,
                  child: _chartType == CpuChartType.line
                      ? CpuLineChart(history: effectiveHistory)
                      : CpuBarChart(coreGroups: snapShot.coreGroups),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

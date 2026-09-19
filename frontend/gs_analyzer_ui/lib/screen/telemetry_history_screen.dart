import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';

class TelemetryHistoryScreen extends ConsumerWidget {
  const TelemetryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(hudDensityProvider);
    return Scaffold(
      backgroundColor: HudTheme.bgBase,
      body: Padding(
        padding: EdgeInsets.all(d.panelPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TELEMETRY HISTORY',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: HudTheme.primaryBorder,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 8),
            const Text('SYSTEM-WIDE METRIC TRENDS', style: HudTheme.labelMuted),
            const SizedBox(height: 24),
            Expanded(
              child: ListView(
                children: [
                  SizedBox(
                    height: 400,
                    child: TelemetryHistoryChart(metricKey: 'cpu'),
                  ),
                  SizedBox(height: d.gap * 2),
                  SizedBox(
                    height: 400,
                    child: TelemetryHistoryChart(metricKey: 'ram'),
                  ),
                  SizedBox(height: d.gap * 2),
                  SizedBox(
                    height: 400,
                    child: TelemetryHistoryChart(
                      metricKey: 'thermal_cpu_package',
                    ),
                  ),
                  SizedBox(height: d.gap * 2),
                  SizedBox(
                    height: 400,
                    child: TelemetryHistoryChart(metricKey: 'network_rx'),
                  ),
                  SizedBox(height: d.gap * 2),
                  SizedBox(
                    height: 400,
                    child: TelemetryHistoryChart(metricKey: 'network_tx'),
                  ),
                  SizedBox(height: 48), // Padding at bottom
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

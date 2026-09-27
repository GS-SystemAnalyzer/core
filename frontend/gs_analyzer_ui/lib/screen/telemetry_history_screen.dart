import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';

class TelemetryHistoryScreen extends ConsumerWidget {
  const TelemetryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.HudTheme;
    final d = ref.watch(hudDensityProvider);
    final hud = context.HudTheme;
    return Scaffold(
      backgroundColor: theme.base,
      body: Padding(
        padding: EdgeInsets.all(d.panelPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TELEMETRY HISTORY',
              style:hud.header
            ),
            const SizedBox(height: 8),
            Text('SYSTEM-WIDE METRIC TRENDS', style: hud.label),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import '../providers/directory_provider.dart';
import '../services/api_service.dart';

class TelemetryHudWidget extends ConsumerWidget {
  const TelemetryHudWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryProvider);
    final double calculateProgress = telemetry.total > 0
        ? telemetry.completed / telemetry.total
        : 0.0;
    final double displayPercentage = calculateProgress * 100;
    final hud = context.hudTheme;

    return Center(
      child: Container(
        width: 500, // Fixed width
        padding: const EdgeInsets.all(24),
        decoration: hud.hudPanelDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: hud.accentCyan,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '${telemetry.status}...',
                    style: hud.header,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            if (telemetry.total > 0) ...[
              LinearProgressIndicator(
                value: calculateProgress,
                color: hud.accentGreen,
                backgroundColor: hud.textMain.withValues(alpha: 0.1),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SECTORS SCANNED: ${telemetry.completed} / ${telemetry.total}',
                    style: hud.statGreen,
                  ),
                  Text(
                    '${displayPercentage.toStringAsFixed(1)}%',
                    style: hud.statGreen,
                  ),
                ],
              ),
            ] else ...[
              Text('CALCULATING SECTORS...', style: hud.statGreen),
            ],
            const SizedBox(height: 16),
            Text(
              'TARGET: ${telemetry.target}',
              style: hud.label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.bottomRight,
              child: TextButton(
                onPressed: () async {
                  await ApiService().abortScan();
                  ref.read(directoryProvider.notifier).purgeStaleCache();
                  snackbarKey.currentState?.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Scan Aborted',
                        style: TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: hud.accentAmber,
                    ),
                  );
                },
                child: Text('ABORT SCAN', style: hud.actionRed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

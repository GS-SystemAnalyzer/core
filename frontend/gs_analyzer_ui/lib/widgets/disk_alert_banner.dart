import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/disk_alert.dart';
import 'package:gs_analyzer_ui/providers/disk_alert_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

/// Renders a list of stacked disk alert banners at the top of the Storage screen,
/// ordered by usedPercent descending.
class DiskAlertBannerList extends ConsumerWidget {
  const DiskAlertBannerList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertMap = ref.watch(diskAlertsProvider);
    if (alertMap.isEmpty) {
      return const SizedBox.shrink();
    }

    final d = ref.watch(hudDensityProvider);
    final sortedAlerts = alertMap.values.toList()
      ..sort((a, b) => b.usedPercent.compareTo(a.usedPercent));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: d.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: sortedAlerts.map((alert) {
          return Padding(
            padding: EdgeInsets.only(bottom: d.gap),
            child: DiskAlertBannerCard(alert: alert, d: d),
          );
        }).toList(),
      ),
    );
  }
}

class DiskAlertBannerCard extends ConsumerWidget {
  final DiskAlert alert;
  final HudDensity d;

  const DiskAlertBannerCard({
    super.key,
    required this.alert,
    required this.d,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCritical = alert.isCritical;
    final alertColor = isCritical ? Colors.redAccent : Colors.amber;
    final badgeBg = alertColor.withValues(alpha: 0.15);

    final titleText = isCritical ? 'CRITICAL DISK SPACE' : 'LOW DISK SPACE WARNING';
    final freeText = alert.freeFormatted.isNotEmpty
        ? alert.freeFormatted
        : '${(alert.freeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    final displayText =
        '${alert.displayName} is ${alert.usedPercent.toStringAsFixed(1)}% full — $freeText free';

    return Container(
      padding: EdgeInsets.all(d.panelPad * 0.8),
      decoration: BoxDecoration(
        color: HudTheme.bgPanel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: alertColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: alertColor.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: badgeBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCritical ? Icons.error_outline : Icons.warning_amber_rounded,
              color: alertColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      titleText,
                      style: HudTheme.headerCyan.copyWith(
                        color: alertColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${alert.usedPercent.toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: alertColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Consolas',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  displayText,
                  style: HudTheme.bodyText.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            key: Key('cleanup_btn_${alert.driveName}'),
            onPressed: () {
              // Select the alerting drive
              ref.read(selectedDriveNameProvider.notifier).state =
                  alert.driveName;
              // Open Temp Cleaner scoped to that drive
              ref.read(storageModeProvider.notifier).state =
                  StorageMode.tempFileCleaner;
              ref.read(storageViewProvider.notifier).state =
                  StorageView.analyzer;
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: alertColor.withValues(alpha: 0.2),
              foregroundColor: alertColor,
              elevation: 0,
              side: BorderSide(color: alertColor, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: const Text(
              'CLEAN UP',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

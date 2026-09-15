import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/drive_info.dart';
import '../providers/drive_stats_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/hud_theme.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/widgets/file_type_analyzer_panel.dart';
import 'package:gs_analyzer_ui/widgets/undo_history_panel.dart';
import 'package:gs_analyzer_ui/widgets/watcher_event_log_panel.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/scan_diff_provider.dart';
import 'package:gs_analyzer_ui/screen/scan_diff_screen.dart';
import 'package:gs_analyzer_ui/widgets/disk_alert_banner.dart';
import 'package:gs_analyzer_ui/providers/disk_alert_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/widgets/export_scan_dialog.dart';

class StorageScreen extends ConsumerWidget {
  const StorageScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDrive = ref.watch(currentDriveProvider);
    final drives = ref.watch(drivesProvider);
    final d = ref.watch(hudDensityProvider);

    Widget buildBody() {
      if (drives.isEmpty) {
        return Center(
          child: CircularProgressIndicator(color: HudTheme.accentCyan),
        );
      }

      if (currentDrive == null) {
        return const SizedBox.shrink();
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DiskAlertBannerList(),
          _DriveSelectorBar(drives: drives, selectedDrive: currentDrive),
          const Divider(color: Colors.white10, height: 1),

          Expanded(
            child: ListView(
              children: [
                Padding(
                  padding: EdgeInsets.all(d.panelPad),
                  child: _DriveDetailCard(drive: currentDrive, d: d),
                ),
                FileTypeAnalyzerPanel(driveName: currentDrive.name),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: d.panelPad),
                  child: Column(
                    children: [
                      _ScanLaunchTile(
                        title: 'DIRECTORY SCANNER',
                        subtitle: 'Index every sector on ${currentDrive.name}',
                        icon: Icons.account_tree_outlined,
                        d: d,
                        onLaunch: () => _enterAnalyzer(
                          ref,
                          currentDrive,
                          StorageMode.diskAnalyzer,
                        ),
                      ),
                      _ScanLaunchTile(
                        title: 'DUPLICATE HUNTER',
                        subtitle:
                            'Scan for duplicate files on ${currentDrive.name}',
                        icon: Icons.copy_all_outlined,
                        d: d,
                        onLaunch: () => _enterAnalyzer(
                          ref,
                          currentDrive,
                          StorageMode.duplicateScanner,
                        ),
                      ),
                      _ScanLaunchTile(
                        title: 'TEMP CLEANER',
                        subtitle:
                            'Purge temporary files across all system cache locations',
                        icon: Icons.cleaning_services_outlined,
                        d: d,
                        onLaunch: () => _enterAnalyzer(
                          ref,
                          currentDrive,
                          StorageMode.tempFileCleaner,
                        ),
                      ),
                      _ScanLaunchTile(
                        title: 'PERMISSION AUDIT',
                        subtitle:
                            'Detect world-writable paths and orphaned files',
                        icon: Icons.security_outlined,
                        d: d,
                        onLaunch: () => _enterAnalyzer(
                          ref,
                          currentDrive,
                          StorageMode.permissionAudit,
                        ),
                      ),
                    ],
                  ),
                ),
                const WatcherEventLogPanel(),
                UndoHistoryPanel(),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: HudTheme.bgPanel,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('STORAGE MATRICES', style: HudTheme.headerCyan),
        actions: [
          if (currentDrive != null)
            _ExportScanButton(drive: currentDrive),
        ],
      ),
      body: buildBody(),
    );
  }

  void _enterAnalyzer(WidgetRef ref, DriveInfo drive, StorageMode mode) {
    ref.read(selectedDriveNameProvider.notifier).state = drive.name;
    ref.read(storageModeProvider.notifier).state = mode;

    if (mode == StorageMode.diskAnalyzer) {
      // Force refresh so the TelemetryHudWidget tracks the exact duration of the real scan.
      ref
          .read(directoryProvider.notifier)
          .scanDirectory(drive.name, forceRefresh: true);
    }

    ref.read(storageViewProvider.notifier).state = StorageView.analyzer;
  }
}

class _ScanLaunchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onLaunch;
  final HudDensity d;

  const _ScanLaunchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onLaunch,
    required this.d,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: d.gap),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onLaunch,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.all(d.panelPad),
            decoration: HudTheme.hudPanelDecoration,
            child: Row(
              children: [
                Icon(icon, color: HudTheme.accentCyan),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: HudTheme.headerCyan.copyWith(
                          color: HudTheme.accentCyan,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: HudTheme.bodyText.copyWith(
                          color: HudTheme.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: HudTheme.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriveSelectorBar extends ConsumerWidget {
  final List<DriveInfo> drives;
  final DriveInfo selectedDrive;

  const _DriveSelectorBar({required this.drives, required this.selectedDrive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: drives.map((drive) {
          final isSelected = drive.name == selectedDrive.name;
          return GestureDetector(
            onTap: () =>
                ref.read(selectedDriveNameProvider.notifier).state = drive.name,
            child: _DriveTab(drive: drive, isActive: isSelected),
          );
        }).toList(),
      ),
    );
  }
}

class _DriveTab extends ConsumerWidget {
  final DriveInfo drive;
  final bool isActive;

  const _DriveTab({required this.drive, required this.isActive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    IconData getIcon() {
      if (drive.type.toLowerCase() == 'removable') return Icons.usb;
      if (drive.type.toLowerCase() == 'network') return Icons.cloud;
      return Icons.storage;
    }

    // Connect threshold to user settings!
    final alertSettings = ref.watch(settingsProvider).currentSettings?.alerts;
    final redThreshold = alertSettings?.diskThresholdPercent ?? 90;

    final activeAlert = ref.watch(diskAlertsProvider)[drive.name];
    final bool isAlerting = activeAlert != null;
    final Color alertDotColor =
        (activeAlert?.isCritical ?? false) ? Colors.redAccent : Colors.amber;

    Color getStatusColor() {
      if (drive.percentageUsed >= redThreshold) return Colors.redAccent;
      if (drive.percentageUsed >= redThreshold - 10) return Colors.amber;
      return HudTheme.accentCyan; // Green or Cyan for healthy
    }

    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isActive ? HudTheme.accentCyan : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                getIcon(),
                color: isActive ? HudTheme.accentCyan : HudTheme.textDim,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  drive.displayName,
                  style: HudTheme.bodyText.copyWith(
                    color: isActive ? HudTheme.accentCyan : HudTheme.textDim,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAlerting) ...[
                const SizedBox(width: 6),
                Container(
                  key: Key('alert_dot_${drive.name}'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: alertDotColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: alertDotColor.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: drive.percentageUsed / 100,
            backgroundColor: Colors.white10,
            color: getStatusColor(),
            minHeight: 2,
          ),
        ],
      ),
    );
  }
}

class _DriveDetailCard extends ConsumerWidget {
  final DriveInfo drive;
  final HudDensity d;

  const _DriveDetailCard({required this.drive, required this.d});

  String _formatGB(int bytes) =>
      (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertSettings = ref.watch(settingsProvider).currentSettings?.alerts;
    final redThreshold = alertSettings?.diskThresholdPercent ?? 90;

    final Color statusColor = drive.percentageUsed >= redThreshold
        ? Colors.redAccent
        : (drive.percentageUsed >= redThreshold - 10
              ? Colors.amber
              : HudTheme.accentCyan);

    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'DRIVE: ${drive.displayName}',
                  style: HudTheme.headerCyan.copyWith(
                    color: HudTheme.accentCyan,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (drive.percentageUsed >= redThreshold)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '● CRITICAL SPACE',
                    style: HudTheme.bodyText.copyWith(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              _WhatChangedButton(drive: drive),
            ],
          ),
          Divider(color: Colors.white10, height: d.gap * 3, thickness: 1),

          Wrap(
            spacing: d.gap * 3,
            runSpacing: d.gap,
            children: [
              _buildMetaTag('TYPE', drive.type.toUpperCase()),
              _buildMetaTag('FORMAT', drive.format.toUpperCase()),
              _buildMetaTag('MOUNT', drive.name.toUpperCase()),
            ],
          ),
          SizedBox(height: d.gap * 2),

          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: drive.percentageUsed / 100,
                    backgroundColor: Colors.white10,
                    color: statusColor,
                    minHeight: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${drive.percentageUsed.toStringAsFixed(1)}%',
                style: HudTheme.bodyText,
              ),
            ],
          ),
          SizedBox(height: d.gap * 2),

          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 520;
              final used = Text(
                'USED: ${_formatGB(drive.usedBytes)} GB',
                style: HudTheme.bodyText.copyWith(color: statusColor),
              );
              final free = Text(
                'FREE: ${_formatGB(drive.freeBytes)} GB',
                style: HudTheme.bodyText,
              );
              final total = Text(
                'TOTAL: ${_formatGB(drive.totalBytes)} GB',
                style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
              );

              if (wide) {
                return Row(
                  children: [
                    Expanded(child: used),
                    Expanded(child: free),
                    Expanded(child: total),
                  ],
                );
              }

              return Wrap(
                spacing: d.gap * 3,
                runSpacing: d.gap,
                alignment: WrapAlignment.spaceBetween,
                children: [used, free, total],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetaTag(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
        ),
        Text(
          value,
          style: HudTheme.bodyText.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// WHAT_CHANGED access icon for the drive detail card. Shows an amber count badge
/// when the last scan of this drive produced changes; tapping opens the SCAN_DIFF screen.
/// The badge is hidden when there is no baseline, no cached scan, or zero changes.
class _WhatChangedButton extends ConsumerWidget {
  final DriveInfo drive;

  const _WhatChangedButton({required this.drive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final changeCount = ref.watch(diffChangeCountProvider(drive.name));

    return Tooltip(
      message: 'WHAT CHANGED',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ScanDiffScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.difference_outlined,
                color: HudTheme.accentCyan,
                size: 20,
              ),
              if (changeCount > 0)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: HudTheme.accentAmber,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      changeCount > 99 ? '99+' : '$changeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontFamily: HudTheme.fontCore,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportScanButton extends ConsumerWidget {
  final DriveInfo drive;

  const _ExportScanButton({required this.drive});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirState = ref.watch(directoryProvider);
    final fileTypesAsync = ref.watch(fileTypesProvider(drive.name));

    final hasCachedScan = (dirState.allNodes.isNotEmpty &&
            dirState.currentPath.toUpperCase().startsWith(drive.name.toUpperCase())) ||
        fileTypesAsync.maybeWhen(
          data: (data) => data.categories.isNotEmpty,
          orElse: () => false,
        );

    if (!hasCachedScan) {
      return Tooltip(
        message: 'RUN A SCAN FIRST',
        child: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextButton.icon(
            onPressed: null,
            icon: const Icon(
              Icons.arrow_downward,
              size: 14,
              color: HudTheme.textDim,
            ),
            label: Text(
              'EXPORT',
              style: HudTheme.labelMuted.copyWith(color: HudTheme.textDim),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: HudTheme.accentCyan,
          backgroundColor: HudTheme.accentCyan.withValues(alpha: 0.1),
          side: const BorderSide(color: HudTheme.accentCyan, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => ExportScanDialog(driveName: drive.name),
          );
        },
        icon: const Icon(
          Icons.arrow_downward,
          size: 14,
          color: HudTheme.accentCyan,
        ),
        label: Text(
          'EXPORT',
          style: HudTheme.labelMuted.copyWith(
            color: HudTheme.accentCyan,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}


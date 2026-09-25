import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/schedule_provider.dart';
import 'package:gs_analyzer_ui/services/telemetry_service.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/providers/disk_io_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/scan_diff_provider.dart';
import 'package:gs_analyzer_ui/models/disk_alert.dart';
import 'package:gs_analyzer_ui/providers/disk_alert_provider.dart';
import 'package:gs_analyzer_ui/models/ram_alert.dart';
import 'package:gs_analyzer_ui/providers/ram_alert_provider.dart';
import 'package:gs_analyzer_ui/services/notification_service.dart';

import 'cpu_provider.dart';
import 'nuke_provider.dart';

class TelemetryState {
  final String status;
  final int completed;
  final int total;
  final double percentComplete;
  final String target;
  final String? currentScanId;

  const TelemetryState({
    this.status = 'IDLE',
    this.completed = 0,
    this.total = 0,
    this.percentComplete = 0.0,
    this.target = '',
    this.currentScanId,
  });

  TelemetryState copyWith({
    String? status,
    int? completed,
    int? total,
    double? percentComplete,
    String? target,
    String? currentScanId,
  }) {
    return TelemetryState(
      status: status ?? this.status,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      percentComplete: percentComplete ?? this.percentComplete,
      target: target ?? this.target,
      currentScanId: currentScanId ?? this.currentScanId,
    );
  }
}

class TelemetryNotifier extends StateNotifier<TelemetryState> {
  TelemetryService? _telemetryService;
  final Ref ref;

  TelemetryService? get service => _telemetryService;

  TelemetryNotifier(this.ref) : super(const TelemetryState()) {
    _initRadio();
  }

  void _initRadio() {
    final settingsState = ref.read(settingsProvider);
    final adv = settingsState.savedSettings?.advanced;

    final backendPort = adv?.backendPort ?? 5200;
    final reconnectDelayMs = adv?.signalrReconnectDelaysMs ?? 3000;
    final maxRetries = adv?.maxSignalrRetries ?? 10;

    _telemetryService = TelemetryService(
      backendPort: backendPort,
      reconnectDelayMs: reconnectDelayMs,
      maxRetries: maxRetries,
      onProgressUpdate:
          (scanId, status, completed, total, percentComplete, target) {
            if (status == 'INITIALIZING' ||
                state.currentScanId == null ||
                state.currentScanId == scanId) {
              final isDone =
                  status == 'COMPLETED' ||
                  status == 'ABORTED' ||
                  status == 'FAILED';
              state = state.copyWith(
                status: status,
                completed: completed,
                total: total,
                percentComplete: percentComplete,
                target: target,
                currentScanId: isDone ? null : scanId,
              );
            }
          },
    );

    _telemetryService?.onRamUpdate = (data) {
      ref.read(ramProvider.notifier).updateProcesses(data);
    };

    _telemetryService?.onCpuUpdate = (data) {
      ref.read(cpuProvider.notifier).updateCpu(data);
    };

    _telemetryService?.onDriveUpdate = (data) {
      ref.read(drivesProvider.notifier).updateFromTelemetry(data);
      final activeNames = data
          .map((d) => (d is Map ? d['name'] : null)?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      ref.read(diskAlertsProvider.notifier).pruneDrives(activeNames);
    };

    _telemetryService?.onNetworkUpdate = (data) {
      ref.read(networkProvider.notifier).updateNetwork(data);
    };

    _telemetryService?.onDiskIoUpdate = (data) {
      ref.read(diskIoProvider.notifier).updateDiskIo(data);
    };

    _telemetryService?.onDirectoryChunk = (scanId, path, chunk) {
      ref
          .read(directoryProvider.notifier)
          .receiveStreamChunk(scanId, path, chunk);
    };

    _telemetryService?.onDirectoryStreamComplete = (scanId, path) {
      ref.read(directoryProvider.notifier).finalizeStream(scanId, path);
      final drive = ref.read(currentDriveProvider);
      if (drive != null) {
        final completed = path.replaceAll('\\', '/').replaceAll('/', '').toLowerCase();
        final driveRoot = drive.name.replaceAll('\\', '/').replaceAll('/', '').toLowerCase();
        if (completed == driveRoot) {
          ref.invalidate(scanDiffProvider(drive.name));
        }
      }
    };

    _telemetryService?.onNukeProgress = (percentage, target, completed) {
      ref.read(nukeProgressProvider.notifier).state = percentage;
      ref.read(nukeTargetProvider.notifier).state = target;
      ref.read(nukeCompletedProvider.notifier).state = completed;
    };

    _telemetryService?.onNukeAborted = () {
      ref.read(nukeProgressProvider.notifier).state = 0.0;
      ref.read(nukeTargetProvider.notifier).state = 'ABORTED';
    };

    _telemetryService?.onSectorChanged = (changedFolder) {
      final currentProgress = ref.read(nukeProgressProvider);
      if (currentProgress > 0.0 && currentProgress < 100.0) return;

      final currentPath = ref.read(directoryProvider).currentPath;
      final normalizedCurrent = currentPath
          .replaceAll('\\\\', '/')
          .toLowerCase();
      final normalizedChanged = changedFolder
          .replaceAll('\\\\', '/')
          .toLowerCase();

      if (normalizedCurrent == normalizedChanged) {
        appLogger.i('LIVE UPDATE: REFRESHING UI FOR $currentPath');
        ref.read(directoryProvider.notifier).scanDirectory(currentPath);
      }

      ref.read(drivesProvider.notifier).refresh();
    };

    _telemetryService?.onScheduleUpdate = (jsonList) {
      ref.read(scheduleProvider.notifier).updateFromSignalR(jsonList);
    };

    _telemetryService?.onAutoScanComplete = (data) {
      final root = data['root'] as String;

      // Refresh the WHAT_CHANGED badge + SCAN_DIFF screen for this root. The backend
      // has already computed and cached the diff for this scan (it also rides along in
      // data['diff']), so invalidating re-fetches the freshly cached result.
      ref.invalidate(scanDiffProvider(root));

      ref.read(directoryProvider.notifier).scanDirectory(root);

      snackbarKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'AUTO-SCAN COMPLETE',
            style: HudTheme.headerCyan.copyWith(color: Colors.white),
          ),
          backgroundColor: HudTheme.bgPanel,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    };

    _telemetryService?.onDiskAlert = (data) {
      final alert = DiskAlert.fromJson(data);
      ref.read(diskAlertsProvider.notifier).handleDiskAlert(alert);

      final enableDesktop = ref.read(settingsProvider).currentSettings?.alerts.enableDesktopNotifications ?? true;
      NotificationService().showDiskAlertNotification(
        alert,
        enableDesktopNotifications: enableDesktop,
      );
    };

    _telemetryService?.onDiskAlertCleared = (data) {
      final driveName = data['driveName'] as String?;
      if (driveName != null && driveName.isNotEmpty) {
        ref.read(diskAlertsProvider.notifier).handleDiskAlertCleared(driveName);
      }
    };

    _telemetryService?.onRamAlert = (data) {
      final alert = RamAlert.fromJson(data);
      ref.read(ramAlertProvider.notifier).handleRamAlert(alert);

      final enableDesktop = ref.read(settingsProvider).currentSettings?.alerts.enableDesktopNotifications ?? true;
      NotificationService().showRamAlertNotification(
        alert,
        enableDesktopNotifications: enableDesktop,
      );
    };

    _telemetryService?.onRamAlertCleared = (data) {
      ref.read(ramAlertProvider.notifier).handleRamAlertCleared();
    };

    _telemetryService?.startListening();
  }

  @override
  void dispose() {
    _telemetryService?.stopListening();
    super.dispose();
  }
}

final telemetryProvider =
    StateNotifierProvider<TelemetryNotifier, TelemetryState>((ref) {
      return TelemetryNotifier(ref);
    });

import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

import '../services/api_service.dart';

class RamState {
  final List<ProcessGroup> groupedProcesses;
  final bool isLoading;
  final double activeGb;
  final double cacheGb;
  final double swapGb;
  final double totalSwapGb;
  final double totalGb;
  final List<double> usageHistory;
  final int ramThresholdPercent;
  final String? errorMessage;

  const RamState({
    this.groupedProcesses = const [],
    this.isLoading = true,
    this.activeGb = 0.0,
    this.cacheGb = 0.0,
    this.swapGb = 0.0,
    this.totalSwapGb = 0.0,
    this.totalGb = 16.0, // fix: hard coded total ram size
    this.usageHistory = const [],
    this.ramThresholdPercent = 85,
    this.errorMessage,
  });

  double get usedPercentage => totalGb > 0 ? activeGb / totalGb : 0.0;
  String get displayedString =>
      '${activeGb.toStringAsFixed(2)} GB / ${totalGb.toStringAsFixed(2)} GB';
  bool get isCritical =>
      totalGb > 0 && (activeGb / totalGb) >= (ramThresholdPercent / 100.0);

  RamState copyWith({
    List<ProcessGroup>? groupedProcesses,
    bool? isLoading,
    double? activeGb,
    double? cacheGb,
    double? swapGb,
    double? totalSwapGb,
    double? totalGb,
    List<double>? usageHistory,
    int? ramThresholdPercent,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RamState(
      groupedProcesses: groupedProcesses ?? this.groupedProcesses,
      isLoading: isLoading ?? this.isLoading,
      activeGb: activeGb ?? this.activeGb,
      cacheGb: cacheGb ?? this.cacheGb,
      swapGb: swapGb ?? this.swapGb,
      totalSwapGb: totalSwapGb ?? this.totalSwapGb,
      totalGb: totalGb ?? this.totalGb,
      usageHistory: usageHistory ?? this.usageHistory,
      ramThresholdPercent: ramThresholdPercent ?? this.ramThresholdPercent,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class RamNotifier extends StateNotifier<RamState> {
  final ApiService _apiService;
  final Ref ref;

  RamNotifier(this.ref, [ApiService? apiService])
      : _apiService = apiService ?? ApiService(),
        super(const RamState()) {
    _apiService.startRamRadar();
    _listenToSettings();
  }

  void clearError() {
    snackbarKey.currentState?.hideCurrentSnackBar();
    state = state.copyWith(clearError: true);
  }

  void _listenToSettings() {
    ref.listen(settingsProvider, (previous, next) {
      final newThreshold = next.currentSettings?.alerts.ramThresholdPercent;
      if (newThreshold != null && newThreshold != state.ramThresholdPercent) {
        state = state.copyWith(ramThresholdPercent: newThreshold);
      }
    }, fireImmediately: true);
  }

  void updateProcesses(Map<String, dynamic> payload) {
    final global = payload['global'] ?? payload['Global'] ?? {};

    // appLogger.i('🦅 MATRIX RADAR - Global Memory Payload: $global');

    double parseGb(String lowerKey, String upperKey, double fallback) {
      final val = global[lowerKey] ?? global[upperKey] ?? fallback;
      return (val as num).toDouble();
    }

    final totalGb = parseGb('totalGb', 'TotalGb', 16.0);
    final totalMb = totalGb * 1024.0;

    final rawProcesses = payload['processes'] as List<dynamic>? ?? [];
    final parsed = rawProcesses
        .map((p) => ProcessTelemetry.fromJson(p, totalMb))
        .toList();

    final Map<String, List<ProcessTelemetry>> groupsMap = {};
    for (var p in parsed) {
      if (!groupsMap.containsKey(p.name)) {
        groupsMap[p.name] = [];
      }
      groupsMap[p.name]!.add(p);
    }

    final groupedList = groupsMap.entries
        .map((e) => ProcessGroup(name: e.key, processes: e.value))
        .toList();

    groupedList.sort((a, b) {
      return b.totalRamMb.compareTo(a.totalRamMb);
    });

    final parsedActiveGb = (global['activeGb'] ?? 0.0).toDouble();

    final currentPercentage = totalGb > 0 ? parsedActiveGb / totalGb : 0.0;
    final updatedHistory = List<double>.from(state.usageHistory)
      ..add(currentPercentage);

    if (updatedHistory.length > 20) {
      updatedHistory.removeAt(0);
    }

    state = state.copyWith(
      groupedProcesses: groupedList,
      isLoading: false,
      activeGb: parsedActiveGb,
      cacheGb: (global['cacheGb'] ?? global['CacheGb'] ?? 0.0).toDouble(),
      swapGb: (global['swapGb'] ?? global['SwapGb'] ?? 0.0).toDouble(),
      totalSwapGb:
          (global['totalSwapGb'] ?? global['TotalSwapGb'] ?? (totalGb * 2))
              .toDouble(),
      totalGb: totalGb,
      usageHistory: updatedHistory,
    );
  }

  Future<void> killProcess(int pid) async {
    state = state.copyWith(clearError: true);

    try {
      await _apiService.killRamProcesses([pid]);

      state = state.copyWith(
        groupedProcesses: state.groupedProcesses
            .map((group) {
              return ProcessGroup(
                name: group.name,
                processes: group.processes
                    .where((process) => process.pid != pid)
                    .toList(),
              );
            })
            .where((group) => group.processes.isNotEmpty)
            .toList(),
      );

      appLogger.i('EXECUTE ORDER 66 ON PID: $pid - SUCCESS');
    } catch (e) {
      final msg = _formatErrorMessage(
        e,
        fallback: 'Failed to terminate process (PID: $pid)',
      );
      state = state.copyWith(errorMessage: msg);
      appLogger.e('Failed to kill process $pid: $e');
      _showErrorSnackBar(msg);
    }
  }

  Future<void> killProcessGroup(String groupName) async {
    final targetGroup = state.groupedProcesses
        .where((g) => g.name == groupName)
        .firstOrNull;

    if (targetGroup == null) return;

    final pidsToKill = targetGroup.processes.map((p) => p.pid).toList();
    if (pidsToKill.isEmpty) return;

    state = state.copyWith(clearError: true);

    try {
      await _apiService.killRamProcesses(pidsToKill);

      state = state.copyWith(
        groupedProcesses: state.groupedProcesses
            .where((g) => g.name != groupName)
            .toList(),
      );

      appLogger.i('EXECUTE ORDER 66 ON GROUP: $groupName - SUCCESS');
    } catch (e) {
      final msg = _formatErrorMessage(
        e,
        fallback: 'Failed to terminate process group "$groupName"',
      );
      state = state.copyWith(errorMessage: msg);
      appLogger.e('Failed to kill process group "$groupName": $e');
      _showErrorSnackBar(msg);
    }
  }

  String _formatErrorMessage(dynamic error, {required String fallback}) {
    final str = error.toString();
    final clean = str.startsWith('Exception: ') ? str.substring(11) : str;
    final lower = clean.toLowerCase();

    if (lower.contains('access denied') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('status: 403') ||
        lower.contains('status: 401')) {
      return 'Access Denied: Run as Administrator to kill this process';
    }

    if (lower.contains('socketexception') ||
        lower.contains('refused') ||
        lower.contains('connection refused') ||
        lower.contains('network connection') ||
        lower.contains('failed host lookup') ||
        lower.contains('clientexception')) {
      return 'Backend offline: Unable to connect to Analyzer service (localhost:5200)';
    }

    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Connection timed out: Backend did not respond';
    }

    if (clean.trim().isNotEmpty) {
      if (clean.length > 120) {
        return fallback;
      }
      return clean.trim();
    }
    return fallback;
  }

  void _showErrorSnackBar(String message) {
    final messenger = snackbarKey.currentState;
    if (messenger == null) return;

    final hud = snackbarKey.currentContext?.hudTheme;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: hud?.accentRed ?? const Color(0xFFEF4444),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  fontWeight: FontWeight.bold,
                  color: hud?.accentRed ?? const Color(0xFFEF4444),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: hud?.panel ?? const Color(0xFF1E222A),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void debugSetGroupsForTest(List<ProcessGroup> groups) {
    assert(() {
      return true;
    }(), 'debug only');
    state = state.copyWith(groupedProcesses: groups);
  }
}

final ramProvider = StateNotifierProvider<RamNotifier, RamState>((ref) {
  return RamNotifier(ref);
});

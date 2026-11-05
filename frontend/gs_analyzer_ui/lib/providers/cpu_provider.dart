import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/cpu_snapshot.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class CpuState {
  final CpuSnapshot? snapshot;
  final int cpuThresholdPercent;
  final List<double> history;

  const CpuState({
    this.snapshot,
    this.cpuThresholdPercent = 95,
    this.history = const [],
  });

  bool get isCritical =>
      snapshot != null && snapshot!.averageLoad >= cpuThresholdPercent;

  CpuState copyWith({
    CpuSnapshot? snapshot,
    int? cpuThresholdPercent,
    List<double>? history,
  }) {
    return CpuState(
      snapshot: snapshot ?? this.snapshot,
      cpuThresholdPercent: cpuThresholdPercent ?? this.cpuThresholdPercent,
      history: history ?? this.history,
    );
  }
}

class CpuNotifier extends StateNotifier<CpuState> {
  final ApiService _apiService = ApiService();
  final Ref ref;

  CpuNotifier(this.ref) : super(const CpuState()) {
    _apiService.startCpuRadar();
    _listenToSettings();
  }

  void _listenToSettings() {
    ref.listen(settingsProvider, (previous, next) {
      final newThreshold = next.currentSettings?.alerts.cpuThresholdPercent;
      if (newThreshold != null && newThreshold != state.cpuThresholdPercent) {
        state = state.copyWith(cpuThresholdPercent: newThreshold);
      }
    }, fireImmediately: true);
  }

  void updateCpu(Map<String, dynamic> payload) {
    try {
      final snapshot = CpuSnapshot.fromJson(payload);
      final updatedHistory = List<double>.from(state.history)..add(snapshot.averageLoad);
      if (updatedHistory.length > 30) {
        updatedHistory.removeAt(0);
      }
      state = state.copyWith(
        snapshot: snapshot,
        history: updatedHistory,
      );
    } catch (e) {
      appLogger.i('CPU PAYLOAD CRASH: $e');
    }
  }
}

final cpuProvider = StateNotifierProvider<CpuNotifier, CpuState>((ref) {
  return CpuNotifier(ref);
});

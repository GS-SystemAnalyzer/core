import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/network_telemetry.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/logger.dart';

class NetworkState {
  final NetworkSnapshot? snapshot;
  final String? preferredInterfaceId;
  final List<FlSpot> rxRollingSpots;
  final List<FlSpot> txRollingSpots;
  final double rollingMaxY;

  const NetworkState({
    this.snapshot,
    this.preferredInterfaceId,
    this.rxRollingSpots = const [],
    this.txRollingSpots = const [],
    this.rollingMaxY = 131072.0, // Default floor at 128 KB/s (128 * 1024)
  });

  /// Derives the active primary interface snapshot.
  NetInterfaceSnapshot? get primaryInterface {
    if (snapshot == null || snapshot!.interfaces.isEmpty) return null;

    final primaryId = snapshot!.primaryInterfaceId;
    if (primaryId == null) return null;

    for (final nic in snapshot!.interfaces) {
      if (nic.id == primaryId) return nic;
    }
    return null;
  }

  NetworkState copyWith({
    NetworkSnapshot? snapshot,
    String? preferredInterfaceId,
    List<FlSpot>? rxRollingSpots,
    List<FlSpot>? txRollingSpots,
    double? rollingMaxY,
  }) {
    return NetworkState(
      snapshot: snapshot ?? this.snapshot,
      preferredInterfaceId: preferredInterfaceId ?? this.preferredInterfaceId,
      rxRollingSpots: rxRollingSpots ?? this.rxRollingSpots,
      txRollingSpots: txRollingSpots ?? this.txRollingSpots,
      rollingMaxY: rollingMaxY ?? this.rollingMaxY,
    );
  }
}

class NetworkNotifier extends StateNotifier<NetworkState> {
  final ApiService _apiService = ApiService();
  static const int maxRollingPoints = 60;
  static const double idleNoiseFloor = 131072.0; // 128 KB/s

  NetworkNotifier() : super(const NetworkState()) {
    _seedInitialSnapshot();
  }

  Future<void> _seedInitialSnapshot() async {
    try {
      final snap = await _apiService.fetchNetworkSnapshot();
      if (snap != null) {
        updateFromSnapshot(snap);
      }
    } catch (e) {
      appLogger.i('Failed to seed initial network snapshot: $e');
    }
  }

  void updateNetwork(Map<String, dynamic> payload) {
    try {
      final snapshot = NetworkSnapshot.fromJson(payload);
      updateFromSnapshot(snapshot);
    } catch (e) {
      appLogger.i('NETWORK PAYLOAD DESERIALIZATION CRASH: $e');
    }
  }

  void updateFromSnapshot(NetworkSnapshot snapshot) {
    final primaryId = snapshot.primaryInterfaceId;
    NetInterfaceSnapshot? primary;

    if (primaryId != null) {
      for (final nic in snapshot.interfaces) {
        if (nic.id == primaryId) {
          primary = nic;
          break;
        }
      }
    }

    final double rxRate = primary?.rxBytesPerSec ?? 0.0;
    final double txRate = primary?.txBytesPerSec ?? 0.0;

    // Shift rolling spots
    final newRxSpots = List<FlSpot>.from(state.rxRollingSpots);
    final newTxSpots = List<FlSpot>.from(state.txRollingSpots);

    final double nextX = newRxSpots.isEmpty ? 0 : (newRxSpots.last.x + 1);

    newRxSpots.add(FlSpot(nextX, rxRate));
    newTxSpots.add(FlSpot(nextX, txRate));

    while (newRxSpots.length > maxRollingPoints) {
      newRxSpots.removeAt(0);
    }
    while (newTxSpots.length > maxRollingPoints) {
      newTxSpots.removeAt(0);
    }

    // Recompute Y-axis ceiling: max of both series * 1.2, floored at 128 KB/s
    double peak = 0.0;
    for (final spot in newRxSpots) {
      if (spot.y > peak) peak = spot.y;
    }
    for (final spot in newTxSpots) {
      if (spot.y > peak) peak = spot.y;
    }

    final double calculatedMaxY = max(peak * 1.2, idleNoiseFloor);

    state = state.copyWith(
      snapshot: snapshot,
      rxRollingSpots: newRxSpots,
      txRollingSpots: newTxSpots,
      rollingMaxY: calculatedMaxY,
    );
  }

  Future<bool> setPreferredInterface(String? interfaceId) async {
    final success = await _apiService.setPreferredNetworkInterface(interfaceId);
    if (success) {
      state = state.copyWith(preferredInterfaceId: interfaceId);
      // Immediately refresh snapshot
      final updatedSnap = await _apiService.fetchNetworkSnapshot();
      if (updatedSnap != null) {
        updateFromSnapshot(updatedSnap);
      }
    }
    return success;
  }
}

final networkProvider = StateNotifierProvider<NetworkNotifier, NetworkState>((
  ref,
) {
  return NetworkNotifier();
});

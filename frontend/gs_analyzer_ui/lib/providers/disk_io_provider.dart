import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/logger.dart';

class DiskIoState {
  final DiskIoSnapshotCollection? snapshot;
  final String? selectedDiskId;
  final List<FlSpot> readRollingSpots;
  final List<FlSpot> writeRollingSpots;
  final double rollingMaxY;

  const DiskIoState({
    this.snapshot,
    this.selectedDiskId,
    this.readRollingSpots = const [],
    this.writeRollingSpots = const [],
    this.rollingMaxY = 1048576.0, // 1 MB/s floor
  });

  DiskIoSnapshot? get activeDisk {
    if (snapshot == null || snapshot!.disks.isEmpty) return null;

    if (selectedDiskId != null) {
      for (final disk in snapshot!.disks) {
        if (disk.id == selectedDiskId) return disk;
      }
    }

    return snapshot!.disks.first;
  }

  DiskIoState copyWith({
    DiskIoSnapshotCollection? snapshot,
    String? selectedDiskId,
    List<FlSpot>? readRollingSpots,
    List<FlSpot>? writeRollingSpots,
    double? rollingMaxY,
  }) {
    return DiskIoState(
      snapshot: snapshot ?? this.snapshot,
      selectedDiskId: selectedDiskId ?? this.selectedDiskId,
      readRollingSpots: readRollingSpots ?? this.readRollingSpots,
      writeRollingSpots: writeRollingSpots ?? this.writeRollingSpots,
      rollingMaxY: rollingMaxY ?? this.rollingMaxY,
    );
  }
}

class DiskIoNotifier extends StateNotifier<DiskIoState> {
  final ApiService _apiService = ApiService();
  static const int maxRollingPoints = 60;
  static const double floorMaxY = 1048576.0; // 1 MB/s

  DiskIoNotifier() : super(const DiskIoState()) {
    _seedInitialSnapshot();
  }

  Future<void> _seedInitialSnapshot() async {
    try {
      final snap = await _apiService.fetchDiskIoSnapshot();
      if (snap != null) {
        updateFromSnapshot(snap);
      }
    } catch (e) {
      appLogger.i('Failed to seed initial disk I/O snapshot: $e');
    }
  }

  void updateDiskIo(Map<String, dynamic> payload) {
    try {
      final snapshot = DiskIoSnapshotCollection.fromJson(payload);
      updateFromSnapshot(snapshot);
    } catch (e) {
      appLogger.i('DISK IO PAYLOAD DESERIALIZATION CRASH: $e');
    }
  }

  void selectDisk(String diskId) {
    state = state.copyWith(
      selectedDiskId: diskId,
      readRollingSpots: const [],
      writeRollingSpots: const [],
      rollingMaxY: floorMaxY,
    );
    if (state.snapshot != null) {
      updateFromSnapshot(state.snapshot!);
    }
  }

  void updateFromSnapshot(DiskIoSnapshotCollection snapshot) {
    String? targetId = state.selectedDiskId;
    if (targetId == null && snapshot.disks.isNotEmpty) {
      targetId = snapshot.disks.first.id;
    }

    DiskIoSnapshot? active;
    for (final d in snapshot.disks) {
      if (d.id == targetId) {
        active = d;
        break;
      }
    }
    active ??= snapshot.disks.firstOrNull;

    final double readRate = active?.readBytesPerSec ?? 0.0;
    final double writeRate = active?.writeBytesPerSec ?? 0.0;

    final newReadSpots = List<FlSpot>.from(state.readRollingSpots);
    final newWriteSpots = List<FlSpot>.from(state.writeRollingSpots);

    if (newReadSpots.length >= maxRollingPoints) {
      newReadSpots.removeAt(0);
      newWriteSpots.removeAt(0);
      for (int i = 0; i < newReadSpots.length; i++) {
        newReadSpots[i] = FlSpot(i.toDouble(), newReadSpots[i].y);
        newWriteSpots[i] = FlSpot(i.toDouble(), newWriteSpots[i].y);
      }
    }

    final double nextX = newReadSpots.length.toDouble();
    newReadSpots.add(FlSpot(nextX, readRate));
    newWriteSpots.add(FlSpot(nextX, writeRate));

    double highest = floorMaxY;
    for (final spot in newReadSpots) {
      if (spot.y > highest) highest = spot.y;
    }
    for (final spot in newWriteSpots) {
      if (spot.y > highest) highest = spot.y;
    }

    state = state.copyWith(
      snapshot: snapshot,
      selectedDiskId: targetId,
      readRollingSpots: newReadSpots,
      writeRollingSpots: newWriteSpots,
      rollingMaxY: highest * 1.15,
    );
  }
}

final diskIoProvider = StateNotifierProvider<DiskIoNotifier, DiskIoState>((ref) {
  return DiskIoNotifier();
});

/// Drive-scoped disk I/O provider matching currentDriveProvider letter
final currentDriveDiskIoProvider = Provider<DiskIoSnapshot?>((ref) {
  final state = ref.watch(diskIoProvider);
  if (state.snapshot == null || state.snapshot!.disks.isEmpty) return null;

  final currentDrive = ref.watch(currentDriveProvider);
  if (currentDrive != null) {
    final cleanLetter = currentDrive.name.replaceAll(RegExp(r'[\/\\]'), '').toUpperCase();
    for (final disk in state.snapshot!.disks) {
      for (final letter in disk.driveLetters) {
        final cleanMapped = letter.replaceAll(RegExp(r'[\/\\]'), '').toUpperCase();
        if (cleanMapped.startsWith(cleanLetter) || cleanLetter.startsWith(cleanMapped)) {
          return disk;
        }
      }
    }
  }

  return state.snapshot!.disks.first;
});

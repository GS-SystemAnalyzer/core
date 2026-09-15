class DiskIoSnapshot {
  final String id;
  final String model;
  final List<String> driveLetters;
  final double readBytesPerSec;
  final double writeBytesPerSec;
  final double activeTimePercent;
  final double avgQueueLength;
  final int sessionReadBytes;
  final int sessionWriteBytes;

  const DiskIoSnapshot({
    required this.id,
    required this.model,
    required this.driveLetters,
    required this.readBytesPerSec,
    required this.writeBytesPerSec,
    required this.activeTimePercent,
    required this.avgQueueLength,
    required this.sessionReadBytes,
    required this.sessionWriteBytes,
  });

  factory DiskIoSnapshot.fromJson(Map<String, dynamic> json) {
    return DiskIoSnapshot(
      id: json['id']?.toString() ?? '',
      model: json['model']?.toString() ?? 'Generic Physical Disk',
      driveLetters: (json['driveLetters'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      readBytesPerSec: (json['readBytesPerSec'] as num?)?.toDouble() ?? 0.0,
      writeBytesPerSec: (json['writeBytesPerSec'] as num?)?.toDouble() ?? 0.0,
      activeTimePercent:
          (json['activeTimePercent'] as num?)?.toDouble() ?? 0.0,
      avgQueueLength: (json['avgQueueLength'] as num?)?.toDouble() ?? 0.0,
      sessionReadBytes: (json['sessionReadBytes'] as num?)?.toInt() ?? 0,
      sessionWriteBytes: (json['sessionWriteBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'model': model,
        'driveLetters': driveLetters,
        'readBytesPerSec': readBytesPerSec,
        'writeBytesPerSec': writeBytesPerSec,
        'activeTimePercent': activeTimePercent,
        'avgQueueLength': avgQueueLength,
        'sessionReadBytes': sessionReadBytes,
        'sessionWriteBytes': sessionWriteBytes,
      };
}

class DiskIoSnapshotCollection {
  final DateTime timestamp;
  final List<DiskIoSnapshot> disks;

  const DiskIoSnapshotCollection({
    required this.timestamp,
    required this.disks,
  });

  factory DiskIoSnapshotCollection.fromJson(Map<String, dynamic> json) {
    DateTime ts;
    try {
      ts = json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : DateTime.now();
    } catch (_) {
      ts = DateTime.now();
    }

    final rawDisks = json['disks'] as List<dynamic>? ?? const [];
    final disks = rawDisks
        .whereType<Map<String, dynamic>>()
        .map((d) => DiskIoSnapshot.fromJson(d))
        .toList();

    return DiskIoSnapshotCollection(
      timestamp: ts,
      disks: disks,
    );
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'disks': disks.map((d) => d.toJson()).toList(),
      };
}

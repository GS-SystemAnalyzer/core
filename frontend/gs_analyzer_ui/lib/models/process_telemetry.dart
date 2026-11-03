enum ProcessMemoryMetric {
  privateWorkingSet,
  totalWorkingSet,
  commitSize;

  String get label => switch (this) {
    privateWorkingSet => 'PRIVATE WORKING SET',
    totalWorkingSet => 'TOTAL WORKING SET',
    commitSize => 'COMMIT SIZE',
  };

  String get shortLabel => switch (this) {
    privateWorkingSet => 'PRIVATE WS',
    totalWorkingSet => 'TOTAL WS',
    commitSize => 'COMMIT',
  };

  String get tooltip => switch (this) {
    privateWorkingSet => 'Resident physical memory private to this process; excludes shared pages.',
    totalWorkingSet => 'All resident physical memory mapped by this process, including shared pages.',
    commitSize => 'Private committed virtual memory, resident or paged out; not resident RAM or percentage of commit limit.',
  };
}

enum ProcessMemoryDisplayMode {
  value, percentage;

  String get label => this == value ? 'VALUE' : 'PERCENTAGE';
  String get tooltip => this == value
      ? 'Selected process memory in MiB (1 MiB = 1,048,576 bytes).'
      : 'Selected memory divided by measured physical RAM capacity. Commit is virtual memory; its ratio can exceed 100%.';
}

enum MemoryProvenance {
  measured, legacyEstimate, unknownSource, unavailable;

  String? get label => switch (this) {
    measured => null,
    legacyEstimate => 'LEGACY WS ESTIMATE',
    unknownSource => 'UNKNOWN SOURCE',
    unavailable => 'UNAVAILABLE',
  };
}

class ProcessMemoryValue {
  final int? bytes;
  final MemoryProvenance provenance;
  const ProcessMemoryValue(this.bytes, this.provenance);

  String get formattedMiB => bytes == null
      ? 'N/A' : '${(bytes! / 1048576).toStringAsFixed(1)} MIB';
}

class GroupMemoryValue extends ProcessMemoryValue {
  final int availableMembers;
  final int estimatedMembers;
  final int unknownSourceMembers;
  const GroupMemoryValue(super.bytes, super.provenance,
      this.availableMembers, this.estimatedMembers, this.unknownSourceMembers);

  double? percentOfCapacity(int? physicalTotalBytes) =>
      bytes != null && physicalTotalBytes != null && physicalTotalBytes > 0
          ? bytes! / physicalTotalBytes * 100
          : null;

  String formattedPercentOfCapacity(int? physicalTotalBytes) {
    final percentage = percentOfCapacity(physicalTotalBytes);
    return percentage == null ? 'N/A' : '${percentage.toStringAsFixed(1)}%';
  }
}

const _omittedMemoryCounter = Object();

int? _memoryBytes(Object? value) {
  if (value is! num || !value.isFinite || value < 0 || value != value.roundToDouble()) return null;
  return value.toInt();
}

double? _legacyMiB(Object? value) => value is num && value.isFinite && value >= 0 ? value.toDouble() : null;

class ProcessTelemetry {
  final int pid;
  final String name;
  final double ramMb;
  final double percentMem;
  final String status;
  final double cpuPercent;
  final String user;
  final int? workingSetBytes;
  final int? privateWorkingSetBytes;
  final int? commitBytes;
  final bool _privateOmitted;
  final bool _commitOmitted;
  final bool _hasLegacyRam;
  final String? memorySemantics;

  ProcessTelemetry({
    required this.pid,
    required this.name,
    required this.ramMb,
    required this.percentMem,
    required this.status,
    required this.cpuPercent,
    required this.user,
    int? workingSetBytes,
    Object? privateWorkingSetBytes = _omittedMemoryCounter,
    Object? commitBytes = _omittedMemoryCounter,
    bool hasLegacyRam = true,
    this.memorySemantics,
  }) : workingSetBytes = _memoryBytes(workingSetBytes),
       privateWorkingSetBytes = _memoryBytes(privateWorkingSetBytes),
       commitBytes = _memoryBytes(commitBytes),
       _privateOmitted = identical(privateWorkingSetBytes, _omittedMemoryCounter),
       _commitOmitted = identical(commitBytes, _omittedMemoryCounter),
       _hasLegacyRam = hasLegacyRam && _legacyMiB(ramMb) != null;

  ProcessMemoryValue memoryFor(ProcessMemoryMetric metric) {
    if (metric == ProcessMemoryMetric.totalWorkingSet && workingSetBytes != null) {
      return ProcessMemoryValue(workingSetBytes, MemoryProvenance.measured);
    }
    if (metric == ProcessMemoryMetric.privateWorkingSet && !_privateOmitted) {
      return _modernMemory(privateWorkingSetBytes);
    }
    if (metric == ProcessMemoryMetric.commitSize && !_commitOmitted) {
      return _modernMemory(commitBytes);
    }
    final legacy = workingSetBytes ?? (_hasLegacyRam ? (ramMb * 1048576).round() : null);
    return ProcessMemoryValue(legacy,
        legacy == null ? MemoryProvenance.unavailable : MemoryProvenance.legacyEstimate);
  }

  ProcessMemoryValue _modernMemory(int? bytes) => ProcessMemoryValue(bytes,
      bytes == null ? MemoryProvenance.unavailable
          : memorySemantics == 'windows-private-ws' ? MemoryProvenance.measured : MemoryProvenance.unknownSource);

  factory ProcessTelemetry.fromJson(
    Map<String, dynamic> json,
    double totalSystemRamMb,
    [String? memorySemantics]
  ) {
    final workingSet = _memoryBytes(json['workingSetBytes']);
    final legacy = _legacyMiB(json['ramMb']);
    final mb = legacy ?? (workingSet != null ? workingSet / 1048576 : 0.0);
    return ProcessTelemetry(
      pid: json['processId'] ?? 0,
      name: json['name'] ?? 'UNKNOWN',
      ramMb: mb,
      percentMem: totalSystemRamMb > 0 ? (mb / totalSystemRamMb) * 100 : 0.0,
      status: json['status'] ?? 'UNKNOWN',
      cpuPercent: (json['cpuPercent'] ?? 0.0).toDouble(),
      user: json['user'] ?? json['username'] ?? 'UNKNOWN',
      workingSetBytes: workingSet,
      privateWorkingSetBytes: json.containsKey('privateWorkingSetBytes') ? json['privateWorkingSetBytes'] : _omittedMemoryCounter,
      commitBytes: json.containsKey('commitBytes') ? json['commitBytes'] : _omittedMemoryCounter,
      hasLegacyRam: legacy != null,
      memorySemantics: memorySemantics,
    );
  }
}

class ProcessGroup {
  final String name;
  final List<ProcessTelemetry> processes;

  ProcessGroup({required this.name, required this.processes});

  GroupMemoryValue memoryFor(ProcessMemoryMetric metric) {
    var bytes = 0;
    var available = 0;
    var estimates = 0;
    var unknown = 0;
    for (final process in processes) {
      final value = process.memoryFor(metric);
      if (value.bytes != null) {
        bytes += value.bytes!;
        available++;
      }
      if (value.provenance == MemoryProvenance.legacyEstimate) estimates++;
      if (value.provenance == MemoryProvenance.unknownSource) unknown++;
    }
    final missing = available != processes.length;
    return GroupMemoryValue(missing ? null : bytes,
        missing ? MemoryProvenance.unavailable
            : estimates > 0 ? MemoryProvenance.legacyEstimate
            : unknown > 0 ? MemoryProvenance.unknownSource : MemoryProvenance.measured,
        available, estimates, unknown);
  }

  double get totalRamMb => processes.fold(0, (sum, p) => sum + p.ramMb);
  double get totalPercentMem =>
      processes.fold(0, (sum, p) => sum + p.percentMem);
  double get totalCpuPercent =>
      processes.fold(0, (sum, p) => sum + p.cpuPercent);
  int get count => processes.length;
  int get primaryPid => processes.isNotEmpty ? processes.first.pid : 0;
  String get primaryUser =>
      processes.isNotEmpty ? processes.first.user : 'UNKNOWN';

  String get dominantStatus {
    if (processes.any((p) => p.status == 'RUNNING')) return 'RUNNING';
    if (processes.any((p) => p.status == 'SLEEPING')) return 'SLEEPING';
    return 'STOPPED';
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';

ProcessTelemetry _proc({
  int pid = 1,
  String name = 'test',
  double ramMb = 100.0,
  double percentMem = 1.0,
  double cpuPercent = 5.0,
  String status = 'RUNNING',
  String user = 'SYSTEM',
}) => ProcessTelemetry(
  pid: pid,
  name: name,
  ramMb: ramMb,
  percentMem: percentMem,
  cpuPercent: cpuPercent,
  status: status,
  user: user,
);

void main() {
  group('ProcessGroup computed properties', () {
    test('each metric has an independent complete sum without changing identity', () {
      final group = ProcessGroup(name: 'sample', processes: [
        ProcessTelemetry.fromJson({'processId': 42, 'workingSetBytes': 1000, 'privateWorkingSetBytes': 100, 'commitBytes': 2000}, 100, 'windows-private-ws'),
        ProcessTelemetry.fromJson({'processId': 43, 'workingSetBytes': 3000, 'privateWorkingSetBytes': 200, 'commitBytes': 5000}, 100, 'windows-private-ws'),
      ]);
      expect(group.memoryFor(ProcessMemoryMetric.privateWorkingSet).bytes, 300);
      expect(group.memoryFor(ProcessMemoryMetric.totalWorkingSet).bytes, 4000);
      expect(group.memoryFor(ProcessMemoryMetric.commitSize).bytes, 7000);
      expect(group.primaryPid, 42);
    });

    test('one unavailable member makes the complete total unavailable', () {
      final group = ProcessGroup(name: 'sample', processes: [
        ProcessTelemetry.fromJson({'privateWorkingSetBytes': 100}, 100, 'windows-private-ws'),
        ProcessTelemetry.fromJson({'privateWorkingSetBytes': null}, 100, 'windows-private-ws'),
      ]);
      final value = group.memoryFor(ProcessMemoryMetric.privateWorkingSet);
      expect(value.bytes, isNull);
      expect(value.availableMembers, 1);
      expect(value.percentOfCapacity(1000), isNull);
    });

    test('mixed legacy sums disclose estimates and commit ratios are not clamped', () {
      final group = ProcessGroup(name: 'sample', processes: [
        ProcessTelemetry.fromJson({'workingSetBytes': 1000}, 100),
        ProcessTelemetry.fromJson({'commitBytes': 2000}, 100, 'windows-private-ws'),
      ]);
      final value = group.memoryFor(ProcessMemoryMetric.commitSize);
      expect(value.bytes, 3000);
      expect(value.estimatedMembers, 1);
      expect(value.provenance, MemoryProvenance.legacyEstimate);
      expect(value.percentOfCapacity(1000), 300);
      expect(value.percentOfCapacity(null), isNull);
    });

    test('totalRamMb sums all processes', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [
          _proc(ramMb: 200.0),
          _proc(ramMb: 300.0),
          _proc(ramMb: 100.0),
        ],
      );
      expect(g.totalRamMb, closeTo(600.0, 0.001));
    });

    test('totalCpuPercent sums all processes', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [
          _proc(cpuPercent: 10.0),
          _proc(cpuPercent: 5.5),
          _proc(cpuPercent: 2.0),
        ],
      );
      expect(g.totalCpuPercent, closeTo(17.5, 0.001));
    });

    test('totalPercentMem sums percentMem correctly', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [_proc(percentMem: 3.0), _proc(percentMem: 7.0)],
      );
      expect(g.totalPercentMem, closeTo(10.0, 0.001));
    });

    test('count returns number of processes', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [_proc(), _proc(), _proc()],
      );
      expect(g.count, 3);
    });

    test('primaryPid returns first process pid', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [_proc(pid: 42), _proc(pid: 99)],
      );
      expect(g.primaryPid, 42);
    });

    test('primaryPid is 0 when processes is empty', () {
      final g = ProcessGroup(name: 'empty', processes: []);
      expect(g.primaryPid, 0);
    });

    test('primaryUser returns first process user', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [
          _proc(user: 'G00dS0ul'),
          _proc(user: 'SYSTEM'),
        ],
      );
      expect(g.primaryUser, 'G00dS0ul');
    });

    test('primaryUser is UNKNOWN when processes is empty', () {
      final g = ProcessGroup(name: 'empty', processes: []);
      expect(g.primaryUser, 'UNKNOWN');
    });

    test('dominantStatus is RUNNING when any process is RUNNING', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [
          _proc(status: 'SLEEPING'),
          _proc(status: 'RUNNING'),
        ],
      );
      expect(g.dominantStatus, 'RUNNING');
    });

    test('dominantStatus is SLEEPING when no RUNNING but some SLEEPING', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [
          _proc(status: 'SLEEPING'),
          _proc(status: 'STOPPED'),
        ],
      );
      expect(g.dominantStatus, 'SLEEPING');
    });

    test('dominantStatus is STOPPED when all processes are STOPPED', () {
      final g = ProcessGroup(
        name: 'test',
        processes: [
          _proc(status: 'STOPPED'),
          _proc(status: 'STOPPED'),
        ],
      );
      expect(g.dominantStatus, 'STOPPED');
    });

    test('totalRamMb is zero for empty group', () {
      final g = ProcessGroup(name: 'empty', processes: []);
      expect(g.totalRamMb, 0.0);
    });

    test('single process group returns its own values', () {
      final g = ProcessGroup(
        name: 'solo',
        processes: [
          _proc(
            pid: 7,
            ramMb: 128.0,
            cpuPercent: 3.0,
            user: 'admin',
            status: 'SLEEPING',
          ),
        ],
      );
      expect(g.count, 1);
      expect(g.primaryPid, 7);
      expect(g.totalRamMb, 128.0);
      expect(g.totalCpuPercent, 3.0);
      expect(g.primaryUser, 'admin');
      expect(g.dominantStatus, 'SLEEPING');
    });
  });
}

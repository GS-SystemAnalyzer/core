import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';

void main() {
  group('ProcessTelemetry.fromJson', () {
    test('distinct byte counters prefer exact working-set bytes and preserve measured zero', () {
      final process = ProcessTelemetry.fromJson({
        'processId': 42, 'name': 'sample', 'ramMb': 999,
        'workingSetBytes': 1048576, 'privateWorkingSetBytes': 0, 'commitBytes': 3145728,
      }, 100, 'windows-private-ws');
      expect(process.memoryFor(ProcessMemoryMetric.totalWorkingSet).bytes, 1048576);
      expect(process.memoryFor(ProcessMemoryMetric.privateWorkingSet).bytes, 0);
      expect(process.memoryFor(ProcessMemoryMetric.privateWorkingSet).provenance, MemoryProvenance.measured);
      expect(process.memoryFor(ProcessMemoryMetric.commitSize).bytes, 3145728);
      expect(process.ramMb, 999);
    });

    test('omitted counters use labelled legacy evidence but explicit null is unavailable', () {
      final omitted = ProcessTelemetry.fromJson({'workingSetBytes': 123}, 100);
      final unavailable = ProcessTelemetry.fromJson({'workingSetBytes': 123, 'privateWorkingSetBytes': null}, 100);
      expect(omitted.memoryFor(ProcessMemoryMetric.privateWorkingSet).bytes, 123);
      expect(omitted.memoryFor(ProcessMemoryMetric.privateWorkingSet).provenance, MemoryProvenance.legacyEstimate);
      expect(unavailable.memoryFor(ProcessMemoryMetric.privateWorkingSet).bytes, isNull);
      expect(ProcessTelemetry.fromJson({}, 100).memoryFor(ProcessMemoryMetric.privateWorkingSet).bytes, isNull);
    });

    test('invalid modern counters never become plausible zero or aliases', () {
      for (final value in [-1, 1.5, double.nan, '100']) {
        final process = ProcessTelemetry.fromJson({'ramMb': 10, 'commitBytes': value}, 100, 'windows-private-ws');
        expect(process.memoryFor(ProcessMemoryMetric.commitSize).bytes, isNull);
      }
    });

    test('modern values without declared source retain unknown provenance', () {
      final process = ProcessTelemetry.fromJson({'privateWorkingSetBytes': 123}, 100);
      expect(process.memoryFor(ProcessMemoryMetric.privateWorkingSet).bytes, 123);
      expect(process.memoryFor(ProcessMemoryMetric.privateWorkingSet).provenance, MemoryProvenance.unknownSource);
    });

    test('parses all fields correctly', () {
      final json = {
        'processId': 1234,
        'name': 'devenv',
        'ramMb': 512.5,
        'cpuPercent': 18.3,
        'status': 'RUNNING',
        'user': 'G00dS0ul',
      };

      final p = ProcessTelemetry.fromJson(json, 16384.0);

      expect(p.pid, 1234);
      expect(p.name, 'devenv');
      expect(p.ramMb, 512.5);
      expect(p.cpuPercent, 18.3);
      expect(p.status, 'RUNNING');
      expect(p.user, 'G00dS0ul');
    });

    test('percentMem calculates from ramMb and totalSystemRamMb', () {
      final json = {
        'processId': 1,
        'name': 'x',
        'ramMb': 1638.4,
        'cpuPercent': 0.0,
        'status': 'RUNNING',
        'user': 'SYSTEM',
      };
      final p = ProcessTelemetry.fromJson(json, 16384.0);
      // 1638.4 / 16384.0 * 100 = 10.0
      expect(p.percentMem, closeTo(10.0, 0.01));
    });

    test('percentMem is zero when totalSystemRamMb is zero', () {
      final json = {
        'processId': 1,
        'name': 'x',
        'ramMb': 500.0,
        'cpuPercent': 0.0,
        'status': 'RUNNING',
        'user': 'SYSTEM',
      };
      final p = ProcessTelemetry.fromJson(json, 0.0);
      expect(p.percentMem, 0.0);
    });

    test('missing fields fall back to defaults', () {
      final p = ProcessTelemetry.fromJson({}, 16384.0);
      expect(p.pid, 0);
      expect(p.name, 'UNKNOWN');
      expect(p.ramMb, 0.0);
      expect(p.cpuPercent, 0.0);
      expect(p.status, 'UNKNOWN'); // was 'RUNNING' — fixed
      expect(p.user, 'UNKNOWN'); // was 'SYSTEM'  — fixed
    });

    test('null json values use defaults', () {
      final json = {
        'processId': null,
        'name': null,
        'ramMb': null,
        'cpuPercent': null,
        'status': null,
        'user': null,
      };
      final p = ProcessTelemetry.fromJson(json, 16384.0);
      expect(p.pid, 0);
      expect(p.name, 'UNKNOWN');
      expect(p.status, 'UNKNOWN'); // was 'RUNNING' — fixed
      expect(p.user, 'UNKNOWN'); // was 'SYSTEM'  — fixed
    });

    test('integer ramMb is coerced to double', () {
      final json = {
        'processId': 1,
        'name': 'x',
        'ramMb': 256,
        'cpuPercent': 0,
        'status': 'RUNNING',
        'user': 'SYSTEM',
      };
      final p = ProcessTelemetry.fromJson(json, 16384.0);
      expect(p.ramMb, 256.0);
    });
  });
}

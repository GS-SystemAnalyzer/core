import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/services/telemetry_service.dart';

void main() {
  group('TelemetryService - _handleDriveUpdate', () {
    late TelemetryService service;

    setUp(() {
      service = TelemetryService(
        onProgressUpdate: (scanId, status, completed, total, percent, target) {},
      );
    });

    test('ignores null arguments without throwing', () {
      bool called = false;
      service.onDriveUpdate = (_) => called = true;

      service.handleDriveUpdate(null);
      expect(called, isFalse);
    });

    test('ignores empty arguments list without throwing', () {
      bool called = false;
      service.onDriveUpdate = (_) => called = true;

      service.handleDriveUpdate([]);
      expect(called, isFalse);
    });

    test('unwraps map payload with "drives" key (backend format)', () {
      List<dynamic>? received;
      service.onDriveUpdate = (drives) => received = drives;

      final sampleDrives = [
        {'name': r'C:\', 'label': 'OS', 'totalBytes': 1000},
        {'name': r'D:\', 'label': 'Data', 'totalBytes': 2000},
      ];

      service.handleDriveUpdate([
        {'drives': sampleDrives}
      ]);

      expect(received, isNotNull);
      expect(received, equals(sampleDrives));
    });

    test('unwraps map payload with PascalCase "Drives" key', () {
      List<dynamic>? received;
      service.onDriveUpdate = (drives) => received = drives;

      final sampleDrives = [
        {'name': r'E:\', 'label': 'USB', 'totalBytes': 500},
      ];

      service.handleDriveUpdate([
        {'Drives': sampleDrives}
      ]);

      expect(received, isNotNull);
      expect(received, equals(sampleDrives));
    });

    test('accepts direct List payload (backward compatibility)', () {
      List<dynamic>? received;
      service.onDriveUpdate = (drives) => received = drives;

      final sampleDrives = [
        {'name': r'C:\', 'label': 'OS', 'totalBytes': 1000},
      ];

      service.handleDriveUpdate([sampleDrives]);

      expect(received, isNotNull);
      expect(received, equals(sampleDrives));
    });

    test('ignores unexpected payload types gracefully without error', () {
      bool called = false;
      service.onDriveUpdate = (_) => called = true;

      service.handleDriveUpdate(['unexpected string']);
      service.handleDriveUpdate([12345]);
      service.handleDriveUpdate([{'unrelatedKey': 'value'}]);

      expect(called, isFalse);
    });

    test('handles update safely when onDriveUpdate callback is null', () {
      service.onDriveUpdate = null;

      expect(
        () => service.handleDriveUpdate([
          {
            'drives': [
              {'name': r'C:\', 'label': 'OS'}
            ]
          }
        ]),
        returnsNormally,
      );
    });
  });
}

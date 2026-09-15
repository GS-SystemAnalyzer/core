import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';

void main() {
  group('DiskIoSnapshot serialization', () {
    test('fromJson and toJson round-trips correctly', () {
      final json = {
        'id': '0',
        'model': 'Samsung SSD 980 PRO 1TB',
        'driveLetters': ['C:', 'D:'],
        'readBytesPerSec': 12582912.0,
        'writeBytesPerSec': 4194304.0,
        'activeTimePercent': 34.2,
        'avgQueueLength': 0.8,
        'sessionReadBytes': 8589934592,
        'sessionWriteBytes': 2147483648,
      };

      final snapshot = DiskIoSnapshot.fromJson(json);

      expect(snapshot.id, '0');
      expect(snapshot.model, 'Samsung SSD 980 PRO 1TB');
      expect(snapshot.driveLetters, ['C:', 'D:']);
      expect(snapshot.readBytesPerSec, 12582912.0);
      expect(snapshot.writeBytesPerSec, 4194304.0);
      expect(snapshot.activeTimePercent, 34.2);
      expect(snapshot.avgQueueLength, 0.8);
      expect(snapshot.sessionReadBytes, 8589934592);
      expect(snapshot.sessionWriteBytes, 2147483648);

      final outJson = snapshot.toJson();
      expect(outJson['id'], '0');
      expect(outJson['driveLetters'], ['C:', 'D:']);
      expect(outJson['readBytesPerSec'], 12582912.0);
      expect(outJson['writeBytesPerSec'], 4194304.0);
      expect(outJson['activeTimePercent'], 34.2);
      expect(outJson['avgQueueLength'], 0.8);
    });

    test('fromJson handles null and missing values gracefully', () {
      final snapshot = DiskIoSnapshot.fromJson({});

      expect(snapshot.id, '');
      expect(snapshot.model, 'Generic Physical Disk');
      expect(snapshot.driveLetters, isEmpty);
      expect(snapshot.readBytesPerSec, 0.0);
      expect(snapshot.writeBytesPerSec, 0.0);
      expect(snapshot.activeTimePercent, 0.0);
      expect(snapshot.avgQueueLength, 0.0);
      expect(snapshot.sessionReadBytes, 0);
      expect(snapshot.sessionWriteBytes, 0);
    });
  });

  group('DiskIoSnapshotCollection serialization', () {
    test('fromJson parses disks array and timestamp correctly', () {
      final json = {
        'timestamp': '2026-08-07T13:07:00.000Z',
        'disks': [
          {
            'id': '0',
            'model': 'Disk 0',
            'driveLetters': ['C:'],
            'readBytesPerSec': 1000.0,
            'writeBytesPerSec': 500.0,
            'activeTimePercent': 10.0,
            'avgQueueLength': 0.2,
            'sessionReadBytes': 1000,
            'sessionWriteBytes': 500,
          }
        ],
      };

      final collection = DiskIoSnapshotCollection.fromJson(json);

      expect(collection.disks.length, 1);
      expect(collection.disks[0].id, '0');
      expect(collection.disks[0].driveLetters, ['C:']);
      expect(collection.timestamp, DateTime.parse('2026-08-07T13:07:00.000Z'));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';
import 'package:gs_analyzer_ui/providers/disk_io_provider.dart';
import 'package:gs_analyzer_ui/screen/disk_io_screen.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';

class MockDiskIoNotifier extends DiskIoNotifier {
  final DiskIoSnapshotCollection? initialCollection;

  MockDiskIoNotifier(this.initialCollection) {
    if (initialCollection != null) {
      updateFromSnapshot(initialCollection!);
    }
  }
}

void main() {
  testWidgets('DiskIoScreen renders loading state when snapshot is null', (tester) async {
    final mockNotifier = MockDiskIoNotifier(null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diskIoProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DiskIoScreen(),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('DISK I/O THROUGHPUT'), findsOneWidget);
    expect(find.text('LIVE VIEW'), findsOneWidget);
    expect(find.text('HISTORY'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('DiskIoScreen renders disk tabs and multi-disk overview in LIVE VIEW', (tester) async {
    final sampleSnapshot = DiskIoSnapshotCollection(
      timestamp: DateTime.now(),
      disks: [
        DiskIoSnapshot(
          id: '0',
          model: 'Samsung 980 PRO',
          driveLetters: ['C:'],
          readBytesPerSec: 1048576,
          writeBytesPerSec: 2097152,
          avgQueueLength: 0.8,
          activeTimePercent: 12.0,
          sessionReadBytes: 10485760,
          sessionWriteBytes: 20971520,
        ),
        DiskIoSnapshot(
          id: '1',
          model: 'WD Black SN850X',
          driveLetters: ['D:', 'E:'],
          readBytesPerSec: 5242880,
          writeBytesPerSec: 10485760,
          avgQueueLength: 2.5,
          activeTimePercent: 35.0,
          sessionReadBytes: 52428800,
          sessionWriteBytes: 104857600,
        ),
      ],
    );

    final mockNotifier = MockDiskIoNotifier(sampleSnapshot);
    mockNotifier.updateFromSnapshot(sampleSnapshot);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diskIoProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DiskIoScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('DISK I/O THROUGHPUT'), findsOneWidget);
    expect(find.text('DISK 0 [C:]'), findsOneWidget);
    expect(find.text('DISK 1 [D:, E:]'), findsOneWidget);
    expect(find.text('Samsung 980 PRO'), findsWidgets);
    expect(find.text('ALL PHYSICAL DISKS'), findsOneWidget);

    // Tap on DISK 1 tab
    await tester.tap(find.text('DISK 1 [D:, E:]'));
    await tester.pumpAndSettle();

    expect(mockNotifier.state.selectedDiskId, '1');
  });

  testWidgets('DiskIoScreen toggles between LIVE VIEW and HISTORY', (tester) async {
    final sampleSnapshot = DiskIoSnapshotCollection(
      timestamp: DateTime.now(),
      disks: [
        DiskIoSnapshot(
          id: '0',
          model: 'Test NVMe',
          driveLetters: ['C:'],
          readBytesPerSec: 100,
          writeBytesPerSec: 200,
          avgQueueLength: 0.1,
          activeTimePercent: 1.0,
          sessionReadBytes: 1000,
          sessionWriteBytes: 2000,
        ),
      ],
    );

    final mockNotifier = MockDiskIoNotifier(sampleSnapshot);
    mockNotifier.updateFromSnapshot(sampleSnapshot);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diskIoProvider.overrideWith((ref) => mockNotifier),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DiskIoScreen(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap HISTORY button
    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();

    expect(find.text('READ THROUGHPUT'), findsOneWidget);
    expect(find.text('WRITE THROUGHPUT'), findsOneWidget);
    expect(find.byType(TelemetryHistoryChart), findsOneWidget);

    // Switch metric to WRITE THROUGHPUT
    await tester.tap(find.text('WRITE THROUGHPUT'));
    await tester.pumpAndSettle();

    // Switch back to LIVE VIEW
    await tester.tap(find.text('LIVE VIEW'));
    await tester.pumpAndSettle();

    expect(find.text('DISK 0 [C:]'), findsOneWidget);
  });
}

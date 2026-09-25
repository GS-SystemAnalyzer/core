import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/widgets/disk_io_card.dart';

void main() {
  testWidgets('DiskIoCard renders loading indicator when disk snapshot is null', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskIoCard(overrideDisk: null),
          ),
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('DiskIoCard renders disk details, rates, clamped active %, and session bytes', (tester) async {
    final disk = DiskIoSnapshot(
      id: '0',
      model: 'Samsung 980 PRO 1TB',
      driveLetters: ['C:'],
      readBytesPerSec: 157286400, // 150 MB/s
      writeBytesPerSec: 52428800,  // 50 MB/s
      avgQueueLength: 1.45,
      activeTimePercent: 125.4,    // exceeds 100%, should be clamped to 100%
      sessionReadBytes: 1073741824, // 1 GB
      sessionWriteBytes: 536870912, // 512 MB
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskIoCard(overrideDisk: disk),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('DISK_0'), findsOneWidget);
    expect(find.text('[C:]'), findsOneWidget);
    expect(find.text('Samsung 980 PRO 1TB'), findsOneWidget);
    expect(find.text('150.00 MB/s'), findsOneWidget);
    expect(find.text('50.00 MB/s'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget); // Clamped display
    expect(find.text('1.45'), findsOneWidget);
    expect(find.text('SESSION READ: 1.00 GB'), findsOneWidget);
    expect(find.text('SESSION WRITE: 512.00 MB'), findsOneWidget);
  });

  testWidgets('DiskIoCard renders UNMAPPED when drive letters are empty', (tester) async {
    final disk = DiskIoSnapshot(
      id: '1',
      model: 'Crucial P3 2TB',
      driveLetters: [],
      readBytesPerSec: 0,
      writeBytesPerSec: 0,
      avgQueueLength: 0.1,
      activeTimePercent: 2.0,
      sessionReadBytes: 0,
      sessionWriteBytes: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskIoCard(overrideDisk: disk),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('DISK_1'), findsOneWidget);
    expect(find.text('UNMAPPED'), findsOneWidget);
  });

  testWidgets('DiskIoCard applies queue length color bands (<2 green, 2-5 amber, >5 red)', (tester) async {
    // 1. Green (< 2)
    final greenDisk = DiskIoSnapshot(
      id: '0',
      model: 'Disk 0',
      driveLetters: ['C:'],
      readBytesPerSec: 100,
      writeBytesPerSec: 100,
      avgQueueLength: 1.2,
      activeTimePercent: 10.0,
      sessionReadBytes: 100,
      sessionWriteBytes: 100,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskIoCard(overrideDisk: greenDisk),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final greenText = tester.widget<Text>(find.text('1.20'));
    expect(greenText.style?.color, HudTheme.accentGreen);

    // 2. Amber (2 - 5)
    final amberDisk = DiskIoSnapshot(
      id: '0',
      model: 'Disk 0',
      driveLetters: ['C:'],
      readBytesPerSec: 100,
      writeBytesPerSec: 100,
      avgQueueLength: 3.5,
      activeTimePercent: 50.0,
      sessionReadBytes: 100,
      sessionWriteBytes: 100,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskIoCard(overrideDisk: amberDisk),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final amberText = tester.widget<Text>(find.text('3.50'));
    expect(amberText.style?.color, HudTheme.accentAmber);

    // 3. Red (> 5)
    final redDisk = DiskIoSnapshot(
      id: '0',
      model: 'Disk 0',
      driveLetters: ['C:'],
      readBytesPerSec: 100,
      writeBytesPerSec: 100,
      avgQueueLength: 7.8,
      activeTimePercent: 99.0,
      sessionReadBytes: 100,
      sessionWriteBytes: 100,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskIoCard(overrideDisk: redDisk),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final redText = tester.widget<Text>(find.text('7.80'));
    expect(redText.style?.color, HudTheme.accentRed);
  });
}

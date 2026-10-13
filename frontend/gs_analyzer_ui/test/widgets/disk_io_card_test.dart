import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
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
    expect(greenText.style?.color, HudColor.darkAccentGreen);

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
    expect(amberText.style?.color, HudColor.darkAccentAmber);

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
    expect(redText.style?.color, HudColor.darkAccentRed);
  });

  group('DiskIoCard Theme Adaptation Tests', () {
    final sampleDisk = DiskIoSnapshot(
      id: '0',
      model: 'Samsung 980 PRO 1TB',
      driveLetters: ['C:'],
      readBytesPerSec: 100,
      writeBytesPerSec: 100,
      avgQueueLength: 1.5,
      activeTimePercent: 20.0,
      sessionReadBytes: 1024,
      sessionWriteBytes: 1024,
    );

    testWidgets('DiskIoCard adapts container background, borders, and text colors between themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: Scaffold(
              body: DiskIoCard(overrideDisk: sampleDisk),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightContainer = tester.widget<Container>(find.byType(Container).first);
      final lightBox = lightContainer.decoration as BoxDecoration;
      expect(lightBox.color, equals(HudColor.lightBgBase));
      expect(
        (lightBox.border as Border).top.color,
        equals(HudColor.lightTextMain.withValues(alpha: 0.1)),
      );

      final lightQueueText = tester.widget<Text>(find.text('1.50'));
      expect(lightQueueText.style?.color, equals(HudColor.lightAccentGreen));

      final lightLettersText = tester.widget<Text>(find.text('[C:]'));
      expect(lightLettersText.style?.color, equals(HudColor.lightAccentCyan));

      final lightModelText = tester.widget<Text>(find.text('Samsung 980 PRO 1TB'));
      expect(lightModelText.style?.color, equals(HudColor.lightTextDim));

      final lightSessionReadText = tester.widget<Text>(find.text('SESSION READ: 1.0 KB'));
      expect(lightSessionReadText.style?.color, equals(HudColor.lightTextDim));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: DiskIoCard(overrideDisk: sampleDisk),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkContainer = tester.widget<Container>(find.byType(Container).first);
      final darkBox = darkContainer.decoration as BoxDecoration;
      expect(darkBox.color, equals(HudColor.darkBgBase));
      expect(
        (darkBox.border as Border).top.color,
        equals(HudColor.darkTextMain.withValues(alpha: 0.1)),
      );

      final darkQueueText = tester.widget<Text>(find.text('1.50'));
      expect(darkQueueText.style?.color, equals(HudColor.darkAccentGreen));

      final darkLettersText = tester.widget<Text>(find.text('[C:]'));
      expect(darkLettersText.style?.color, equals(HudColor.darkAccentCyan));

      final darkModelText = tester.widget<Text>(find.text('Samsung 980 PRO 1TB'));
      expect(darkModelText.style?.color, equals(HudColor.darkTextDim));

      final darkSessionReadText = tester.widget<Text>(find.text('SESSION READ: 1.0 KB'));
      expect(darkSessionReadText.style?.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('DiskIoCard loading indicator adapts color between themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: DiskIoCard(overrideDisk: null),
            ),
          ),
        ),
      );
      await tester.pump();

      final lightIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(lightIndicator.color, equals(HudColor.lightAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: DiskIoCard(overrideDisk: null),
            ),
          ),
        ),
      );
      await tester.pump();

      final darkIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(darkIndicator.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/disk_alert.dart';
import 'package:gs_analyzer_ui/providers/disk_alert_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/disk_alert_banner.dart';

void main() {
  testWidgets('DiskAlertBannerList renders nothing when no alerts active',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DiskAlertBannerList(),
          ),
        ),
      ),
    );

    expect(find.byType(DiskAlertBannerCard), findsNothing);
  });

  testWidgets('DiskAlertBannerList renders stacked banners ordered by usedPercent descending',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Add 92% warning and 98.5% critical alerts
    container.read(diskAlertsProvider.notifier).handleDiskAlert(DiskAlert(
          driveName: 'C:\\',
          label: 'Windows (C:)',
          driveType: 'Fixed',
          usedPercent: 92.0,
          freeBytes: 8000000000,
          freeFormatted: '8.0 GB',
          thresholdPercent: 90.0,
          severity: 'warning',
        ));

    container.read(diskAlertsProvider.notifier).handleDiskAlert(DiskAlert(
          driveName: 'D:\\',
          label: 'Data (D:)',
          driveType: 'Fixed',
          usedPercent: 98.5,
          freeBytes: 1500000000,
          freeFormatted: '1.5 GB',
          thresholdPercent: 90.0,
          severity: 'critical',
        ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: DiskAlertBannerList(),
          ),
        ),
      ),
    );

    expect(find.byType(DiskAlertBannerCard), findsNWidgets(2));
    expect(find.text('CRITICAL DISK SPACE'), findsOneWidget);
    expect(find.text('LOW DISK SPACE WARNING'), findsOneWidget);

    // Verify ordering: D:\ (98.5%) should appear above C:\ (92.0%)
    final dPos = tester.getTopLeft(find.byKey(const Key('cleanup_btn_D:\\')));
    final cPos = tester.getTopLeft(find.byKey(const Key('cleanup_btn_C:\\')));
    expect(dPos.dy, lessThan(cPos.dy));

    // Tap CLEAN UP on C:\
    await tester.tap(find.byKey(const Key('cleanup_btn_C:\\')));
    await tester.pumpAndSettle();

    expect(container.read(selectedDriveNameProvider), 'C:\\');
    expect(container.read(storageModeProvider), StorageMode.tempFileCleaner);
    expect(container.read(storageViewProvider), StorageView.analyzer);
  });

  group('DiskAlertBannerCard Theme Adaptation Tests', () {
    testWidgets('DiskAlertBannerCard adapts critical and warning colors between Light and Dark themes',
        (tester) async {
      final criticalAlert = DiskAlert(
        driveName: 'C:\\',
        label: 'Windows (C:)',
        driveType: 'Fixed',
        usedPercent: 98.5,
        freeBytes: 1500000000,
        freeFormatted: '1.5 GB',
        thresholdPercent: 90.0,
        severity: 'critical',
      );

      final warningAlert = DiskAlert(
        driveName: 'D:\\',
        label: 'Data (D:)',
        driveType: 'Fixed',
        usedPercent: 92.0,
        freeBytes: 8000000000,
        freeFormatted: '8.0 GB',
        thresholdPercent: 90.0,
        severity: 'warning',
      );

      const testDensity = HudDensity(
        gap: 8.0,
        panelPad: 12.0,
        rowHeight: 32.0,
        titleSize: 12.0,
        valueSize: 32.0,
        isMax: false,
      );

      // 1. Light Theme
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: Scaffold(
              body: Column(
                children: [
                  DiskAlertBannerCard(alert: criticalAlert, d: testDensity),
                  DiskAlertBannerCard(alert: warningAlert, d: testDensity),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightCritCard = tester.widget<Container>(
        find.descendant(
          of: find.widgetWithText(DiskAlertBannerCard, 'CRITICAL DISK SPACE'),
          matching: find.byType(Container),
        ).first,
      );
      final lightCritDec = lightCritCard.decoration as BoxDecoration;
      expect(lightCritDec.color, equals(HudColor.lightBgPanel));
      expect((lightCritDec.border as Border).top.color, equals(HudColor.lightAccentRed));

      final lightCritIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(lightCritIcon.color, equals(HudColor.lightAccentRed));

      final lightCritTitle = tester.widget<Text>(find.text('CRITICAL DISK SPACE'));
      expect(lightCritTitle.style?.color, equals(HudColor.lightAccentRed));

      final lightCritBtn = tester.widget<ElevatedButton>(find.byKey(const Key('cleanup_btn_C:\\')));
      expect(
        (lightCritBtn.style?.side?.resolve({}) as BorderSide).color,
        equals(HudColor.lightAccentRed),
      );

      final lightWarnCard = tester.widget<Container>(
        find.descendant(
          of: find.widgetWithText(DiskAlertBannerCard, 'LOW DISK SPACE WARNING'),
          matching: find.byType(Container),
        ).first,
      );
      final lightWarnDec = lightWarnCard.decoration as BoxDecoration;
      expect(lightWarnDec.color, equals(HudColor.lightBgPanel));
      expect((lightWarnDec.border as Border).top.color, equals(HudColor.lightAccentAmber));

      final lightWarnIcon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
      expect(lightWarnIcon.color, equals(HudColor.lightAccentAmber));

      final lightWarnTitle = tester.widget<Text>(find.text('LOW DISK SPACE WARNING'));
      expect(lightWarnTitle.style?.color, equals(HudColor.lightAccentAmber));

      final lightWarnBtn = tester.widget<ElevatedButton>(find.byKey(const Key('cleanup_btn_D:\\')));
      expect(
        (lightWarnBtn.style?.side?.resolve({}) as BorderSide).color,
        equals(HudColor.lightAccentAmber),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Theme
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: Column(
                children: [
                  DiskAlertBannerCard(alert: criticalAlert, d: testDensity),
                  DiskAlertBannerCard(alert: warningAlert, d: testDensity),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkCritCard = tester.widget<Container>(
        find.descendant(
          of: find.widgetWithText(DiskAlertBannerCard, 'CRITICAL DISK SPACE'),
          matching: find.byType(Container),
        ).first,
      );
      final darkCritDec = darkCritCard.decoration as BoxDecoration;
      expect(darkCritDec.color, equals(HudColor.darkBgPanel));
      expect((darkCritDec.border as Border).top.color, equals(HudColor.darkAccentRed));

      final darkCritIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(darkCritIcon.color, equals(HudColor.darkAccentRed));

      final darkCritTitle = tester.widget<Text>(find.text('CRITICAL DISK SPACE'));
      expect(darkCritTitle.style?.color, equals(HudColor.darkAccentRed));

      final darkCritBtn = tester.widget<ElevatedButton>(find.byKey(const Key('cleanup_btn_C:\\')));
      expect(
        (darkCritBtn.style?.side?.resolve({}) as BorderSide).color,
        equals(HudColor.darkAccentRed),
      );

      final darkWarnCard = tester.widget<Container>(
        find.descendant(
          of: find.widgetWithText(DiskAlertBannerCard, 'LOW DISK SPACE WARNING'),
          matching: find.byType(Container),
        ).first,
      );
      final darkWarnDec = darkWarnCard.decoration as BoxDecoration;
      expect(darkWarnDec.color, equals(HudColor.darkBgPanel));
      expect((darkWarnDec.border as Border).top.color, equals(HudColor.darkAccentAmber));

      final darkWarnIcon = tester.widget<Icon>(find.byIcon(Icons.warning_amber_rounded));
      expect(darkWarnIcon.color, equals(HudColor.darkAccentAmber));

      final darkWarnTitle = tester.widget<Text>(find.text('LOW DISK SPACE WARNING'));
      expect(darkWarnTitle.style?.color, equals(HudColor.darkAccentAmber));

      final darkWarnBtn = tester.widget<ElevatedButton>(find.byKey(const Key('cleanup_btn_D:\\')));
      expect(
        (darkWarnBtn.style?.side?.resolve({}) as BorderSide).color,
        equals(HudColor.darkAccentAmber),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

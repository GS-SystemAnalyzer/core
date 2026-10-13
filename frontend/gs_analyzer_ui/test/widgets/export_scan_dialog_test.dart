import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/scan_export_options.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/export_scan_dialog.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  setUpAll(() {
    registerFallbackValue(ScanExportFormat.json);
  });

  testWidgets('ExportScanDialog renders header, formats, and handles selection', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ExportScanDialog(driveName: 'C:\\'),
          ),
        ),
      ),
    );

    // Header checks
    expect(find.text('EXPORT SCAN REPORT'), findsOneWidget);
    expect(find.text('C:\\'), findsOneWidget);

    // Formats rendered
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);

    // Checkbox rendered
    expect(find.text('REDACT USER PATHS'), findsOneWidget);

    // Tap CSV format
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();

    // Tap HTML format
    await tester.tap(find.text('HTML'));
    await tester.pumpAndSettle();

    // Toggle Redact Paths
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);
    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    // Checkbox is now true
    final checkboxWidget = tester.widget<Checkbox>(checkboxFinder);
    expect(checkboxWidget.value, true);

    // Buttons rendered
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('EXPORT'), findsOneWidget);
  });

  group('ExportScanDialog Theme Adaptation Tests', () {
    testWidgets('ExportScanDialog adapts colors and borders between themes', (tester) async {
      // 1. Light Theme
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: ExportScanDialog(driveName: 'C:\\'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightDialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(lightDialog.backgroundColor, equals(HudColor.lightBgPanel));
      final lightShape = lightDialog.shape as RoundedRectangleBorder;
      expect(
        lightShape.side.color,
        equals(HudColor.lightTextMain.withValues(alpha: 0.10)),
      );

      final lightHeaderIcon = tester.widget<Icon>(find.byIcon(Icons.download_rounded));
      expect(lightHeaderIcon.color, equals(HudColor.lightAccentCyan));

      final lightHeaderText = tester.widget<Text>(find.text('EXPORT SCAN REPORT'));
      expect(lightHeaderText.style?.color, equals(HudColor.lightAccentCyan));

      final lightDriveText = tester.widget<Text>(find.text('C:\\'));
      expect(lightDriveText.style?.color, equals(HudColor.lightAccentCyan));

      final lightCheckbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(lightCheckbox.activeColor, equals(HudColor.lightAccentCyan));

      final lightCancelBtn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'CANCEL'));
      final lightCancelText = tester.widget<Text>(
        find.descendant(of: find.byWidget(lightCancelBtn), matching: find.text('CANCEL')),
      );
      expect(lightCancelText.style?.color, equals(HudColor.lightTextDim));

      final lightExportBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'EXPORT'));
      expect(
        (lightExportBtn.style?.side?.resolve({}) as BorderSide).color,
        equals(HudColor.lightAccentCyan),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Theme
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: ExportScanDialog(driveName: 'C:\\'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkDialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(darkDialog.backgroundColor, equals(HudColor.darkBgPanel));
      final darkShape = darkDialog.shape as RoundedRectangleBorder;
      expect(
        darkShape.side.color,
        equals(HudColor.darkTextMain.withValues(alpha: 0.10)),
      );

      final darkHeaderIcon = tester.widget<Icon>(find.byIcon(Icons.download_rounded));
      expect(darkHeaderIcon.color, equals(HudColor.darkAccentCyan));

      final darkHeaderText = tester.widget<Text>(find.text('EXPORT SCAN REPORT'));
      expect(darkHeaderText.style?.color, equals(HudColor.darkAccentCyan));

      final darkDriveText = tester.widget<Text>(find.text('C:\\'));
      expect(darkDriveText.style?.color, equals(HudColor.darkAccentCyan));

      final darkCheckbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(darkCheckbox.activeColor, equals(HudColor.darkAccentCyan));

      final darkCancelBtn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'CANCEL'));
      final darkCancelText = tester.widget<Text>(
        find.descendant(of: find.byWidget(darkCancelBtn), matching: find.text('CANCEL')),
      );
      expect(darkCancelText.style?.color, equals(HudColor.darkTextDim));

      final darkExportBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'EXPORT'));
      expect(
        (darkExportBtn.style?.side?.resolve({}) as BorderSide).color,
        equals(HudColor.darkAccentCyan),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('ExportScanDialog Error Handling Tests', () {
    testWidgets('displays error message in accentRed when export fails while dialog is mounted', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = MockApiService();
      when(() => mockApi.exportScan(
        root: any(named: 'root'),
        format: any(named: 'format'),
        redactPaths: any(named: 'redactPaths'),
      )).thenThrow(Exception('Simulated export failure'));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: ExportScanDialog(
                driveName: 'C:\\',
                apiService: mockApi,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final exportFinder = find.widgetWithText(OutlinedButton, 'EXPORT');
      await tester.ensureVisible(exportFinder);
      await tester.tap(exportFinder);
      await tester.pumpAndSettle();

      expect(find.text('Exception: Simulated export failure'), findsOneWidget);
      final errorText = tester.widget<Text>(find.text('Exception: Simulated export failure'));
      expect(errorText.style?.color, equals(HudColor.darkAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('displays no-scan view when DiffNoScanException occurs', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = MockApiService();
      when(() => mockApi.exportScan(
        root: any(named: 'root'),
        format: any(named: 'format'),
        redactPaths: any(named: 'redactPaths'),
      )).thenThrow(const DiffNoScanException());

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: ExportScanDialog(
                driveName: 'C:\\',
                apiService: mockApi,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final exportFinder = find.widgetWithText(OutlinedButton, 'EXPORT');
      await tester.ensureVisible(exportFinder);
      await tester.tap(exportFinder);
      await tester.pumpAndSettle();

      expect(find.text('NO SCAN DATA — RUN A SCAN FIRST'), findsOneWidget);
      expect(find.text('SCAN NOW'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('safely displays SnackBar with hud.panel and hud.accentRed when export fails after dialog unmount', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = MockApiService();
      final completer = Completer<Uint8List>();
      when(() => mockApi.exportScan(
        root: any(named: 'root'),
        format: any(named: 'format'),
        redactPaths: any(named: 'redactPaths'),
      )).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            scaffoldMessengerKey: snackbarKey,
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (_) => ExportScanDialog(
                        driveName: 'C:\\',
                        apiService: mockApi,
                      ),
                    );
                  },
                  child: const Text('OPEN DIALOG'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('OPEN DIALOG'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportScanDialog), findsOneWidget);

      // Trigger export
      final exportFinder = find.widgetWithText(OutlinedButton, 'EXPORT');
      await tester.ensureVisible(exportFinder);
      await tester.tap(exportFinder);
      await tester.pump(); // Start export future

      // Close/unmount the dialog while export is in progress
      Navigator.of(tester.element(find.byType(ExportScanDialog))).pop();
      await tester.pumpAndSettle();

      expect(find.byType(ExportScanDialog), findsNothing);

      // Now complete the future with an error
      completer.completeError(Exception('Unmounted error'));
      await tester.pumpAndSettle();

      // SnackBar should be displayed safely without throwing unmounted context errors or syntax crashes
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('EXPORT FAILED: Exception: Unmounted error'), findsOneWidget);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, equals(HudColor.darkBgPanel));
      final errorText = tester.widget<Text>(find.text('EXPORT FAILED: Exception: Unmounted error'));
      expect(errorText.style?.color, equals(HudColor.darkAccentRed));

      // Dismiss snackbar and clear widget tree to prevent leak tracker false positives
      snackbarKey.currentState?.removeCurrentSnackBar();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

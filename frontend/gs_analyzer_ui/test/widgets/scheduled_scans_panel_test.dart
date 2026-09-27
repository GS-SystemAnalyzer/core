import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/models/drive_info.dart';
import 'package:gs_analyzer_ui/models/scheduled_scan_model.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/schedule_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/scheduled_scans_panel.dart';

class MockSettingsNotifier extends StateNotifier<SettingsState> implements SettingsNotifier {
  MockSettingsNotifier(SettingsState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockScheduleNotifier extends ScheduleNotifier {
  final List<ScheduledScan> initialList;
  MockScheduleNotifier([this.initialList = const []]);

  @override
  Future<List<ScheduledScan>> build() async => initialList;

  @override
  Future<void> deleteSchedule(String id) async {}

  @override
  Future<void> toggleEnabled(String id, bool enabled) async {}
}

class MockDrivesNotifier extends DrivesNotifier {
  final List<DriveInfo> drives;
  MockDrivesNotifier(this.drives);

  @override
  List<DriveInfo> build() => drives;
}

void main() {
  final disabledSettings = AppSettings.fromjson({
    'monitoring': {'enableScheduledScans': false},
  });

  final enabledSettings = AppSettings.fromjson({
    'monitoring': {'enableScheduledScans': true},
  });

  final sampleScans = [
    ScheduledScan(
      id: 'scan-1',
      path: 'C:\\',
      type: 'Directory',
      kind: 'Interval',
      intervalMinutes: 30,
      enabled: true,
      lastRun: DateTime(2026, 1, 1, 10, 0),
      nextRun: DateTime(2026, 1, 1, 10, 30),
    ),
    ScheduledScan(
      id: 'scan-2',
      path: 'D:\\',
      type: 'LargeFiles',
      kind: 'Cron',
      cron: '0 0 * * *',
      enabled: false,
    ),
  ];

  final List<DriveInfo> sampleDrives = [
    DriveInfo.fromJson({
      'name': 'C:\\',
      'label': 'Local Disk',
      'type': 'fixed',
      'format': 'NTFS',
      'totalBytes': 500000000000,
      'freeBytes': 250000000000,
      'usedBytes': 250000000000,
    }),
  ];

  group('ScheduledScansPanel Theme Adaptation Tests', () {
    testWidgets('Renders disabled state with themed panel and textDim in light and dark mode', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: disabledSettings),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: ScheduledScansPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SCHEDULED SCANS'), findsOneWidget);
      expect(find.text('SCHEDULED SCANS DISABLED — ENABLE IN SETTINGS'), findsOneWidget);

      final outerContainerFinder = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(4.0)));
      expect(outerContainerFinder, findsOneWidget);

      final lightDecoration = (tester.widget<Container>(outerContainerFinder).decoration as BoxDecoration);
      expect(lightDecoration.color, equals(HudColor.lightBgPanel));
      expect((lightDecoration.border as Border).top.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      final lightDisabledNotice = tester.widget<Text>(find.text('SCHEDULED SCANS DISABLED — ENABLE IN SETTINGS'));
      expect(lightDisabledNotice.style?.color, equals(HudColor.lightTextDim));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: disabledSettings),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: ScheduledScansPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkDecoration = (tester.widget<Container>(outerContainerFinder).decoration as BoxDecoration);
      expect(darkDecoration.color, equals(HudColor.darkBgPanel));
      expect((darkDecoration.border as Border).top.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      final darkDisabledNotice = tester.widget<Text>(find.text('SCHEDULED SCANS DISABLED — ENABLE IN SETTINGS'));
      expect(darkDisabledNotice.style?.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Renders enabled list, badges, and action buttons adapting to light and dark theme', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: enabledSettings),
            )),
            scheduleProvider.overrideWith(() => MockScheduleNotifier(sampleScans)),
            drivesProvider.overrideWith(() => MockDrivesNotifier(sampleDrives)),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(child: ScheduledScansPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADD SCHEDULE'), findsOneWidget);
      final lightAddBtn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'ADD SCHEDULE'));
      expect(lightAddBtn.style?.foregroundColor?.resolve({}), equals(HudColor.lightAccentCyan));

      // Check path color for enabled scan (accentCyan) and disabled scan (textDim)
      final lightEnabledScanPath = tester.widget<Text>(find.text('C:\\'));
      expect(lightEnabledScanPath.style?.color, equals(HudColor.lightAccentCyan));

      final lightDisabledScanPath = tester.widget<Text>(find.text('D:\\'));
      expect(lightDisabledScanPath.style?.color, equals(HudColor.lightTextDim));

      // Check schedule text
      expect(find.text('EVERY 30 MIN'), findsOneWidget);
      expect(find.text('CRON 0 0 * * *'), findsOneWidget);

      // Check edit & delete icon buttons color
      final lightEditBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.edit_outlined).first,
      );
      expect(lightEditBtn.color, equals(HudColor.lightAccentCyan));

      final lightDeleteBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline).first,
      );
      expect(lightDeleteBtn.color, equals(HudColor.lightAccentRed.withValues(alpha: 0.8)));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: enabledSettings),
            )),
            scheduleProvider.overrideWith(() => MockScheduleNotifier(sampleScans)),
            drivesProvider.overrideWith(() => MockDrivesNotifier(sampleDrives)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(child: ScheduledScansPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkAddBtn = tester.widget<TextButton>(find.widgetWithText(TextButton, 'ADD SCHEDULE'));
      expect(darkAddBtn.style?.foregroundColor?.resolve({}), equals(HudColor.darkAccentCyan));

      final darkEnabledScanPath = tester.widget<Text>(find.text('C:\\'));
      expect(darkEnabledScanPath.style?.color, equals(HudColor.darkAccentCyan));

      final darkDisabledScanPath = tester.widget<Text>(find.text('D:\\'));
      expect(darkDisabledScanPath.style?.color, equals(HudColor.darkTextDim));

      final darkEditBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.edit_outlined).first,
      );
      expect(darkEditBtn.color, equals(HudColor.darkAccentCyan));

      final darkDeleteBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline).first,
      );
      expect(darkDeleteBtn.color, equals(HudColor.darkAccentRed.withValues(alpha: 0.8)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Delete confirmation dialog uses hud.panel and hud.accentRed in light and dark mode', (tester) async {
      // 1. Light Mode Delete Dialog
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: enabledSettings),
            )),
            scheduleProvider.overrideWith(() => MockScheduleNotifier(sampleScans)),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(child: ScheduledScansPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('DELETE SCHEDULE'), findsOneWidget);
      final lightDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(lightDialog.backgroundColor, equals(HudColor.lightBgPanel));

      final lightDeleteText = tester.widget<Text>(find.text('DELETE'));
      expect(lightDeleteText.style?.color, equals(HudColor.lightAccentRed));

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      // 2. Dark Mode Delete Dialog
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: enabledSettings),
            )),
            scheduleProvider.overrideWith(() => MockScheduleNotifier(sampleScans)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(child: ScheduledScansPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline).first);
      await tester.pumpAndSettle();

      final darkDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(darkDialog.backgroundColor, equals(HudColor.darkBgPanel));

      final darkDeleteText = tester.widget<Text>(find.text('DELETE'));
      expect(darkDeleteText.style?.color, equals(HudColor.darkAccentRed));

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Add schedule dialog uses hud.panel and hud.accentCyan save button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, currentSettings: enabledSettings),
            )),
            scheduleProvider.overrideWith(() => MockScheduleNotifier(sampleScans)),
            drivesProvider.overrideWith(() => MockDrivesNotifier(sampleDrives)),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(child: ScheduledScansPanel()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD SCHEDULE'));
      await tester.pumpAndSettle();

      final addDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(addDialog.backgroundColor, equals(HudColor.lightBgPanel));

      final saveBtn = tester.widget<Text>(find.text('SAVE'));
      expect(saveBtn.style?.color, equals(HudColor.lightAccentCyan));

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

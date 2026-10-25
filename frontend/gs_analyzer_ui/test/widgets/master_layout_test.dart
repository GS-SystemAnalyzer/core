import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/models/drive_info.dart';
import 'package:gs_analyzer_ui/providers/automation_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/screen/analyzer_dashboard.dart';
import 'package:gs_analyzer_ui/screen/master_layout.dart';
import 'package:gs_analyzer_ui/screen/storage_screen.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/coming_soon.dart';
import 'package:gs_analyzer_ui/widgets/global_sidebar_widget.dart';

class MockSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  MockSettingsNotifier([SettingsState state = const SettingsState(isLoading: false)])
      : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockDirectoryNotifier extends StateNotifier<DirectoryState>
    implements DirectoryNotifier {
  MockDirectoryNotifier([
    DirectoryState state = const DirectoryState(isLoading: false, currentPath: 'C:/'),
  ]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTelemetryNotifier extends StateNotifier<TelemetryState>
    implements TelemetryNotifier {
  MockTelemetryNotifier([TelemetryState state = const TelemetryState()])
      : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEmptyRulesNotifier extends AutomationRulesNotifier {
  @override
  Future<List<AutomationRule>> build() async => [];
}

class FakeDrivesNotifier extends DrivesNotifier {
  final List<DriveInfo> _drives;
  FakeDrivesNotifier([this._drives = const []]);

  @override
  List<DriveInfo> build() => _drives;

  @override
  Future<void> refresh() async {}
}

final dummyDrive = DriveInfo(
  name: 'C:\\',
  label: 'System Disk',
  type: 'Fixed',
  format: 'NTFS',
  totalBytes: 512000000000,
  freeBytes: 256000000000,
  usedBytes: 256000000000,
  percentageFree: 50.0,
  percentageUsed: 50.0,
);

void main() {
  group('StorageRouter Tests', () {
    testWidgets('renders StorageScreen directly without ComingSoon wrapper when view is drivePicker',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          storageViewProvider.overrideWith((ref) => StorageView.drivePicker),
          drivesProvider.overrideWith(() => FakeDrivesNotifier([dummyDrive])),
          currentDriveProvider.overrideWithValue(null),
          directoryProvider.overrideWith((ref) => MockDirectoryNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const StorageRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // StorageScreen should be rendered directly
      expect(find.byType(StorageScreen), findsOneWidget);
      expect(find.text('STORAGE MATRICES'), findsOneWidget);
      expect(find.byType(AnalyzerDashboard), findsNothing);

      // ComingSoon wrapper should NOT be present
      expect(find.byType(ComingSoon), findsNothing);
      expect(find.text('COMING SOON'), findsNothing);
      expect(find.text('THIS MODULE IS NOT AVAILABLE YET'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('renders AnalyzerDashboard directly without ComingSoon wrapper when view is analyzer',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          storageViewProvider.overrideWith((ref) => StorageView.analyzer),
          drivesProvider.overrideWith(() => FakeDrivesNotifier([dummyDrive])),
          currentDriveProvider.overrideWithValue(null),
          directoryProvider.overrideWith((ref) => MockDirectoryNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const StorageRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // AnalyzerDashboard should be rendered directly
      expect(find.byType(AnalyzerDashboard), findsOneWidget);
      expect(find.byType(StorageScreen), findsNothing);

      // ComingSoon wrapper should NOT be present
      expect(find.byType(ComingSoon), findsNothing);
      expect(find.text('COMING SOON'), findsNothing);
      expect(find.text('THIS MODULE IS NOT AVAILABLE YET'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('dynamically toggles between StorageScreen and AnalyzerDashboard when storageViewProvider changes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          storageViewProvider.overrideWith((ref) => StorageView.drivePicker),
          drivesProvider.overrideWith(() => FakeDrivesNotifier([dummyDrive])),
          currentDriveProvider.overrideWithValue(null),
          directoryProvider.overrideWith((ref) => MockDirectoryNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const StorageRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially on drivePicker: StorageScreen is visible
      expect(find.byType(StorageScreen), findsOneWidget);
      expect(find.byType(AnalyzerDashboard), findsNothing);

      // Switch to analyzer
      container.read(storageViewProvider.notifier).state = StorageView.analyzer;
      await tester.pumpAndSettle();

      // Now AnalyzerDashboard is visible
      expect(find.byType(AnalyzerDashboard), findsOneWidget);
      expect(find.byType(StorageScreen), findsNothing);
      expect(find.byType(ComingSoon), findsNothing);

      // Switch back to drivePicker
      container.read(storageViewProvider.notifier).state = StorageView.drivePicker;
      await tester.pumpAndSettle();

      expect(find.byType(StorageScreen), findsOneWidget);
      expect(find.byType(AnalyzerDashboard), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('tapping back button in AnalyzerDashboard returns to StorageScreen via storageViewProvider',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          storageViewProvider.overrideWith((ref) => StorageView.analyzer),
          drivesProvider.overrideWith(() => FakeDrivesNotifier([dummyDrive])),
          currentDriveProvider.overrideWithValue(null),
          directoryProvider.overrideWith((ref) => MockDirectoryNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const StorageRouter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AnalyzerDashboard), findsOneWidget);
      expect(container.read(storageViewProvider), equals(StorageView.analyzer));

      // Tap back button
      final backButton = find.byTooltip('Back to Drives');
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // View should have reset to drivePicker and display StorageScreen
      expect(container.read(storageViewProvider), equals(StorageView.drivePicker));
      expect(find.byType(StorageScreen), findsOneWidget);
      expect(find.byType(AnalyzerDashboard), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('MasterLayout Storage Route Integration Tests', () {
    testWidgets('MasterLayout renders StorageRouter without ComingSoon when route is AppRoute.storage',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          navigationProvider.overrideWith((ref) => AppRoute.storage),
          storageViewProvider.overrideWith((ref) => StorageView.drivePicker),
          drivesProvider.overrideWith(() => FakeDrivesNotifier([dummyDrive])),
          currentDriveProvider.overrideWithValue(null),
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
          telemetryProvider.overrideWith((ref) => MockTelemetryNotifier()),
          directoryProvider.overrideWith((ref) => MockDirectoryNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const MasterLayout(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sidebar and StorageRouter are rendered
      expect(find.byType(GlobalSidebarWidget), findsOneWidget);
      expect(find.byType(StorageRouter), findsOneWidget);
      expect(find.byType(StorageScreen), findsOneWidget);

      // ComingSoon wrapper should NOT exist anywhere in MasterLayout
      expect(find.byType(ComingSoon), findsNothing);
      expect(find.text('COMING SOON'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('MasterLayout resets storageViewProvider to drivePicker when navigating into AppRoute.storage',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          navigationProvider.overrideWith((ref) => AppRoute.automation),
          storageViewProvider.overrideWith((ref) => StorageView.analyzer),
          drivesProvider.overrideWith(() => FakeDrivesNotifier([dummyDrive])),
          currentDriveProvider.overrideWithValue(null),
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
          telemetryProvider.overrideWith((ref) => MockTelemetryNotifier()),
          directoryProvider.overrideWith((ref) => MockDirectoryNotifier()),
          automationRulesProvider.overrideWith(() => MockEmptyRulesNotifier()),
          automationAuditProvider.overrideWith((ref) async => <AutomationAuditEntry>[]),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const MasterLayout(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Precondition: storageViewProvider was set to analyzer, route is automation
      expect(container.read(storageViewProvider), equals(StorageView.analyzer));
      expect(container.read(navigationProvider), equals(AppRoute.automation));

      // Navigate to AppRoute.storage
      container.read(navigationProvider.notifier).state = AppRoute.storage;
      await tester.pumpAndSettle();

      // MasterLayout route listener should reset storageViewProvider to drivePicker
      expect(container.read(storageViewProvider), equals(StorageView.drivePicker));
      expect(find.byType(StorageRouter), findsOneWidget);
      expect(find.byType(StorageScreen), findsOneWidget);
      expect(find.byType(AnalyzerDashboard), findsNothing);
      expect(find.byType(ComingSoon), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/providers/automation_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/screen/analyzer_dashboard.dart';
import 'package:gs_analyzer_ui/screen/automation_screen.dart';
import 'package:gs_analyzer_ui/screen/network_module_screen.dart';
import 'package:gs_analyzer_ui/screen/telemetry_history_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/screen/process_explorer_screen.dart';
import 'package:gs_analyzer_ui/widgets/side_bar_widget.dart';
import 'package:mocktail/mocktail.dart';

class MockDirectoryNotifier extends StateNotifier<DirectoryState> implements DirectoryNotifier {
  MockDirectoryNotifier([DirectoryState state = const DirectoryState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockEmptyRulesNotifier extends AutomationRulesNotifier {
  @override
  Future<List<AutomationRule>> build() async => [];
}

class MockNetworkNotifier extends StateNotifier<NetworkState> implements NetworkNotifier {
  MockNetworkNotifier([NetworkState state = const NetworkState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockRamNotifier extends StateNotifier<RamState> implements RamNotifier {
  MockRamNotifier([RamState state = const RamState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCpuNotifier extends StateNotifier<CpuState> implements CpuNotifier {
  MockCpuNotifier([CpuState state = const CpuState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockApiService extends Mock implements ApiService {}

void main() {
  group('Screen Theme Adaptation Tests', () {
    testWidgets('AutomationScreen adapts scaffold base and panel decorations between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            automationRulesProvider.overrideWith(() => MockEmptyRulesNotifier()),
            automationAuditProvider.overrideWith((ref) async => <AutomationAuditEntry>[]),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const AutomationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightMaterial = tester.widget<Material>(find.byType(Material).first);
      expect(lightMaterial.color, equals(HudColor.lightBgBase));

      final lightHeaderText = tester.widget<Text>(find.text('AUTOMATION PROTOCOL'));
      expect(lightHeaderText.style?.color, equals(HudColor.lightAccentCyan));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            automationRulesProvider.overrideWith(() => MockEmptyRulesNotifier()),
            automationAuditProvider.overrideWith((ref) async => <AutomationAuditEntry>[]),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const AutomationScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkMaterial = tester.widget<Material>(find.byType(Material).first);
      expect(darkMaterial.color, equals(HudColor.darkBgBase));

      final darkHeaderText = tester.widget<Text>(find.text('AUTOMATION PROTOCOL'));
      expect(darkHeaderText.style?.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('NetworkModuleScreen adapts header typography and view toggle buttons between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkProvider.overrideWith((ref) => MockNetworkNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: NetworkModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightHeaderText = tester.widget<Text>(find.text('NETWORK MODULE'));
      expect(lightHeaderText.style?.color, equals(HudColor.lightAccentCyan));

      final liveViewFinder = find.ancestor(
        of: find.text('LIVE VIEW'),
        matching: find.byType(Container),
      ).first;
      final lightLiveDec = tester.widget<Container>(liveViewFinder).decoration as BoxDecoration;
      expect((lightLiveDec.border as Border).top.color, equals(HudColor.lightAccentCyan));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkProvider.overrideWith((ref) => MockNetworkNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: NetworkModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkHeaderText = tester.widget<Text>(find.text('NETWORK MODULE'));
      expect(darkHeaderText.style?.color, equals(HudColor.darkAccentCyan));

      final darkLiveDec = tester.widget<Container>(liveViewFinder).decoration as BoxDecoration;
      expect((darkLiveDec.border as Border).top.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('SideBarTreeWidget adapts container base and header panel colors between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            treeExpandedProvider.overrideWith((ref) => true),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: Scaffold(
              body: SideBarTreeWidget(onNuke: (_, __) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightAnimatedContainer = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final lightDec = lightAnimatedContainer.decoration as BoxDecoration;
      expect(lightDec.color, equals(HudColor.lightBgBase));

      final headerContainerFinder = find.ancestor(
        of: find.text('DATA TREE'),
        matching: find.byType(Container),
      ).first;
      final lightHeaderDec = tester.widget<Container>(headerContainerFinder).decoration as BoxDecoration;
      expect(lightHeaderDec.color, equals(HudColor.lightBgPanel));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            treeExpandedProvider.overrideWith((ref) => true),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: SideBarTreeWidget(onNuke: (_, __) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkAnimatedContainer = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      final darkDec = darkAnimatedContainer.decoration as BoxDecoration;
      expect(darkDec.color, equals(HudColor.darkBgBase));

      final darkHeaderDec = tester.widget<Container>(headerContainerFinder).decoration as BoxDecoration;
      expect(darkHeaderDec.color, equals(HudColor.darkBgPanel));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('TelemetryHistoryScreen adapts scaffold base and header text between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockApi = MockApiService();
      when(() => mockApi.fetchTelemetryHistory(any(), any()))
          .thenAnswer((_) async => null);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(mockApi),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const TelemetryHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, equals(HudColor.lightBgBase));

      final lightHeader = tester.widget<Text>(find.text('TELEMETRY HISTORY'));
      expect(lightHeader.style?.color, equals(HudColor.lightAccentCyan));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiServiceProvider.overrideWithValue(mockApi),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const TelemetryHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, equals(HudColor.darkBgBase));

      final darkHeader = tester.widget<Text>(find.text('TELEMETRY HISTORY'));
      expect(darkHeader.style?.color, equals(HudColor.darkAccentCyan));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('AnalyzerDashboard adapts scaffold base, panel decorations, and standby UI between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith((ref) => MockDirectoryNotifier(
              const DirectoryState(isLoading: false, currentPath: 'C:/'),
            )),
            currentDriveProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const AnalyzerDashboard(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(lightScaffold.backgroundColor, equals(HudColor.lightBgBase));

      final lightAppBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(lightAppBar.backgroundColor, equals(HudColor.lightBgPanel));

      final lightStandbyHeader = tester.widget<Text>(find.text('SYSTEM STANDBY'));
      expect(lightStandbyHeader.style?.color, equals(HudColor.lightAccentCyan));

      final lightStandbySub = tester.widget<Text>(find.text('Awaiting target matrix assignment for Directory Indexing.'));
      expect(lightStandbySub.style?.color, equals(HudColor.lightTextDim));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith((ref) => MockDirectoryNotifier(
              const DirectoryState(isLoading: false, currentPath: 'C:/'),
            )),
            currentDriveProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const AnalyzerDashboard(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(darkScaffold.backgroundColor, equals(HudColor.darkBgBase));

      final darkAppBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(darkAppBar.backgroundColor, equals(HudColor.darkBgPanel));

      final darkStandbyHeader = tester.widget<Text>(find.text('SYSTEM STANDBY'));
      expect(darkStandbyHeader.style?.color, equals(HudColor.darkAccentCyan));

      final darkStandbySub = tester.widget<Text>(find.text('Awaiting target matrix assignment for Directory Indexing.'));
      expect(darkStandbySub.style?.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('ProcessExplorerScreen adapts toolbar borders, chips, table header, and row borders between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleGroup = ProcessGroup(
        name: 'svchost.exe',
        processes: [
          ProcessTelemetry(
            pid: 1234,
            name: 'svchost.exe',
            ramMb: 128.0,
            percentMem: 1.0,
            cpuPercent: 2.0,
            status: 'RUNNING',
            user: 'SYSTEM',
          ),
        ],
      );

      final ramState = RamState(
        isLoading: false,
        activeGb: 4.0,
        totalGb: 16.0,
        groupedProcesses: [sampleGroup],
      );

      const testDensity = HudDensity(
        gap: 8.0,
        panelPad: 12.0,
        rowHeight: 32.0,
        titleSize: 12.0,
        valueSize: 32.0,
        isMax: false,
      );

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ramProvider.overrideWith((ref) => MockRamNotifier(ramState)),
            cpuProvider.overrideWith((ref) => MockCpuNotifier(const CpuState())),
            hudDensityProvider.overrideWithValue(testDensity),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: ProcessExplorerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightLoadBarContainer = tester.widget<Container>(
        find.ancestor(of: find.text('PROCS: 1'), matching: find.byType(Container)).first,
      );
      final lightLoadBarBorder = (lightLoadBarContainer.decoration as BoxDecoration).border as Border;
      expect(lightLoadBarBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      final lightToolbarContainer = tester.widget<Container>(
        find.ancestor(of: find.byType(TextField), matching: find.byType(Container)).first,
      );
      final lightToolbarBorder = (lightToolbarContainer.decoration as BoxDecoration).border as Border;
      expect(lightToolbarBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      final lightChipContainer = tester.widget<Container>(
        find.ancestor(of: find.text('SORT: % CPU'), matching: find.byType(Container)).first,
      );
      final lightChipDec = lightChipContainer.decoration as BoxDecoration;
      expect(lightChipDec.color, equals(HudColor.lightTextMain.withValues(alpha: 0.04)));

      final lightHeaderContainer = tester.widget<Container>(
        find.ancestor(of: find.text('COMMAND'), matching: find.byType(Container)).first,
      );
      final lightHeaderBorder = (lightHeaderContainer.decoration as BoxDecoration).border as Border;
      expect(lightHeaderBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ramProvider.overrideWith((ref) => MockRamNotifier(ramState)),
            cpuProvider.overrideWith((ref) => MockCpuNotifier(const CpuState())),
            hudDensityProvider.overrideWithValue(testDensity),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: ProcessExplorerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkLoadBarContainer = tester.widget<Container>(
        find.ancestor(of: find.text('PROCS: 1'), matching: find.byType(Container)).first,
      );
      final darkLoadBarBorder = (darkLoadBarContainer.decoration as BoxDecoration).border as Border;
      expect(darkLoadBarBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      final darkToolbarContainer = tester.widget<Container>(
        find.ancestor(of: find.byType(TextField), matching: find.byType(Container)).first,
      );
      final darkToolbarBorder = (darkToolbarContainer.decoration as BoxDecoration).border as Border;
      expect(darkToolbarBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      final darkChipContainer = tester.widget<Container>(
        find.ancestor(of: find.text('SORT: % CPU'), matching: find.byType(Container)).first,
      );
      final darkChipDec = darkChipContainer.decoration as BoxDecoration;
      expect(darkChipDec.color, equals(HudColor.darkTextMain.withValues(alpha: 0.04)));

      final darkHeaderContainer = tester.widget<Container>(
        find.ancestor(of: find.text('COMMAND'), matching: find.byType(Container)).first,
      );
      final darkHeaderBorder = (darkHeaderContainer.decoration as BoxDecoration).border as Border;
      expect(darkHeaderBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

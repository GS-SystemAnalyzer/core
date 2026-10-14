import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/cpu_snapshot.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/screen/process_explorer_screen.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final sampleProcess = ProcessTelemetry(
    pid: 4040,
    name: 'chrome.exe',
    ramMb: 512.0,
    percentMem: 3.2,
    cpuPercent: 5.5,
    status: 'RUNNING',
    user: 'SYSTEM',
  );

  final sampleGroup = ProcessGroup(
    name: 'chrome.exe',
    processes: [sampleProcess],
  );

  final sampleCpuSnapshot = CpuSnapshot(
    averageLoad: 42.5,
    delta: 1.2,
    currentFrequencyGhz: 3.6,
    totalProcesses: 1,
    totalThreads: 8,
    totalHandles: 120,
    l1Cache: '512 KB',
    l2Cache: '2 MB',
    l3Cache: '16 MB',
    coreGroups: {},
  );

  final sampleRamState = RamState(
    isLoading: false,
    activeGb: 8.0,
    totalGb: 16.0,
    groupedProcesses: [sampleGroup],
  );

  final sampleCpuState = CpuState(snapshot: sampleCpuSnapshot);

  const testDensity = HudDensity(
    gap: 8.0,
    panelPad: 12.0,
    rowHeight: 32.0,
    titleSize: 12.0,
    valueSize: 32.0,
    isMax: false,
  );

  group('ProcessExplorerScreen Theme & Widget Tests', () {
    testWidgets('renders loading state when ram is loading and no processes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ramProvider.overrideWith((ref) => MockRamNotifier(const RamState(isLoading: true, groupedProcesses: []))),
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
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts system load bar, toolbar, headers, rows, drawer and footer between Light and Dark themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ramProvider.overrideWith((ref) => MockRamNotifier(sampleRamState)),
            cpuProvider.overrideWith((ref) => MockCpuNotifier(sampleCpuState)),
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

      // Check load bar border
      final lightLoadBarContainer = tester.widget<Container>(
        find.ancestor(of: find.text('PROCS: 1'), matching: find.byType(Container)).first,
      );
      final lightLoadBarBorder = (lightLoadBarContainer.decoration as BoxDecoration).border as Border;
      expect(lightLoadBarBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Check load bar progress indicator background
      final lightIndicators = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(lightIndicators.first.backgroundColor, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Check toolbar border
      final lightToolbarContainer = tester.widget<Container>(
        find.ancestor(of: find.byType(TextFormField), matching: find.byType(Container)).first,
      );
      final lightToolbarBorder = (lightToolbarContainer.decoration as BoxDecoration).border as Border;
      expect(lightToolbarBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Check toolbar TextFormField fill and border
      final lightTextField = tester.widget<TextField>(find.byType(TextField));
      expect(lightTextField.decoration?.fillColor, equals(HudColor.lightTextMain.withValues(alpha: 0.04)));
      final lightTextOutlineBorder = lightTextField.decoration?.border as OutlineInputBorder;
      expect(lightTextOutlineBorder.borderSide.color, equals(HudColor.lightTextMain.withValues(alpha: 0.12)));

      // Check toolbar chip decoration
      final lightChipContainer = tester.widget<Container>(
        find.ancestor(of: find.text('SORT: % CPU'), matching: find.byType(Container)).first,
      );
      final lightChipDec = lightChipContainer.decoration as BoxDecoration;
      expect(lightChipDec.color, equals(HudColor.lightTextMain.withValues(alpha: 0.04)));
      expect((lightChipDec.border as Border).top.color, equals(HudColor.lightTextMain.withValues(alpha: 0.12)));

      // Check table header border
      final lightHeaderContainer = tester.widget<Container>(
        find.ancestor(of: find.text('COMMAND'), matching: find.byType(Container)).first,
      );
      final lightHeaderBorder = (lightHeaderContainer.decoration as BoxDecoration).border as Border;
      expect(lightHeaderBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Check process row hover color and border
      final lightRowInkWell = tester.widget<InkWell>(
        find.ancestor(of: find.text('chrome.exe'), matching: find.byType(InkWell)).first,
      );
      expect(lightRowInkWell.hoverColor, equals(HudColor.lightTextMain.withValues(alpha: 0.03)));

      final lightRowContainer = tester.widget<Container>(
        find.descendant(of: find.byWidget(lightRowInkWell), matching: find.byType(Container)).first,
      );
      final lightRowBorder = (lightRowContainer.decoration as BoxDecoration).border as Border;
      expect(lightRowBorder.bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Check footer border
      final lightFooterContainer = tester.widget<Container>(
        find.ancestor(of: find.text('Showing 1 of 1 processes'), matching: find.byType(Container)).first,
      );
      final lightFooterBorder = (lightFooterContainer.decoration as BoxDecoration).border as Border;
      expect(lightFooterBorder.top.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Tap on row to open DetailDrawer in Light Mode
      await tester.tap(find.text('chrome.exe'));
      await tester.pumpAndSettle();

      final lightDrawer = tester.widget<AnimatedContainer>(
        find.ancestor(of: find.text('WORKING SET'), matching: find.byType(AnimatedContainer)).first,
      );
      final lightDrawerDec = lightDrawer.decoration as BoxDecoration;
      expect((lightDrawerDec.border as Border).bottom.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      // Clean up before Dark Mode
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ramProvider.overrideWith((ref) => MockRamNotifier(sampleRamState)),
            cpuProvider.overrideWith((ref) => MockCpuNotifier(sampleCpuState)),
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

      // Check load bar border
      final darkLoadBarContainer = tester.widget<Container>(
        find.ancestor(of: find.text('PROCS: 1'), matching: find.byType(Container)).first,
      );
      final darkLoadBarBorder = (darkLoadBarContainer.decoration as BoxDecoration).border as Border;
      expect(darkLoadBarBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      // Check load bar progress indicator background
      final darkIndicators = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).toList();
      expect(darkIndicators.first.backgroundColor, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      // Check toolbar border
      final darkToolbarContainer = tester.widget<Container>(
        find.ancestor(of: find.byType(TextFormField), matching: find.byType(Container)).first,
      );
      final darkToolbarBorder = (darkToolbarContainer.decoration as BoxDecoration).border as Border;
      expect(darkToolbarBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      // Check toolbar TextFormField fill and border
      final darkTextField = tester.widget<TextField>(find.byType(TextField));
      expect(darkTextField.decoration?.fillColor, equals(HudColor.darkTextMain.withValues(alpha: 0.04)));
      final darkTextOutlineBorder = darkTextField.decoration?.border as OutlineInputBorder;
      expect(darkTextOutlineBorder.borderSide.color, equals(HudColor.darkTextMain.withValues(alpha: 0.12)));

      // Check toolbar chip decoration
      final darkChipContainer = tester.widget<Container>(
        find.ancestor(of: find.text('SORT: % CPU'), matching: find.byType(Container)).first,
      );
      final darkChipDec = darkChipContainer.decoration as BoxDecoration;
      expect(darkChipDec.color, equals(HudColor.darkTextMain.withValues(alpha: 0.04)));
      expect((darkChipDec.border as Border).top.color, equals(HudColor.darkTextMain.withValues(alpha: 0.12)));

      // Check table header border
      final darkHeaderContainer = tester.widget<Container>(
        find.ancestor(of: find.text('COMMAND'), matching: find.byType(Container)).first,
      );
      final darkHeaderBorder = (darkHeaderContainer.decoration as BoxDecoration).border as Border;
      expect(darkHeaderBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      // Check process row hover color and border
      final darkRowInkWell = tester.widget<InkWell>(
        find.ancestor(of: find.text('chrome.exe'), matching: find.byType(InkWell)).first,
      );
      expect(darkRowInkWell.hoverColor, equals(HudColor.darkTextMain.withValues(alpha: 0.03)));

      final darkRowContainer = tester.widget<Container>(
        find.descendant(of: find.byWidget(darkRowInkWell), matching: find.byType(Container)).first,
      );
      final darkRowBorder = (darkRowContainer.decoration as BoxDecoration).border as Border;
      expect(darkRowBorder.bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      // Check footer border
      final darkFooterContainer = tester.widget<Container>(
        find.ancestor(of: find.text('Showing 1 of 1 processes'), matching: find.byType(Container)).first,
      );
      final darkFooterBorder = (darkFooterContainer.decoration as BoxDecoration).border as Border;
      expect(darkFooterBorder.top.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      // Tap on row to open DetailDrawer in Dark Mode
      await tester.tap(find.text('chrome.exe'));
      await tester.pumpAndSettle();

      final darkDrawer = tester.widget<AnimatedContainer>(
        find.ancestor(of: find.text('WORKING SET'), matching: find.byType(AnimatedContainer)).first,
      );
      final darkDrawerDec = darkDrawer.decoration as BoxDecoration;
      expect((darkDrawerDec.border as Border).bottom.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

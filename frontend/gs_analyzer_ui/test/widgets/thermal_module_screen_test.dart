import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/thermal_telemetry.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/thermal_provider.dart';
import 'package:gs_analyzer_ui/screen/thermal_module_screen.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

class MockThermalNotifier extends StateNotifier<ThermalState> implements ThermalNotifier {
  MockThermalNotifier(ThermalState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCpuNotifier extends StateNotifier<CpuState> implements CpuNotifier {
  MockCpuNotifier([CpuState state = const CpuState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final normalTelemetry = ThermalTelemetry(
    cpuPackageCelsius: 55.0,
    coreCelsius: [52.0, 54.0, 50.0, 53.0],
    motherBoardCelsius: 40.0,
    chipsetCelsius: 45.0,
    cpuFanRpm: 1200,
  );

  final criticalTelemetry = ThermalTelemetry(
    cpuPackageCelsius: 92.0,
    coreCelsius: [90.0, 92.0, 89.0, 91.0],
    isThermalThrottling: true,
  );

  group('ThermalModuleScreen Theme Adaptation Tests', () {
    testWidgets('Header and toggle buttons adapt to light and dark theme', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thermalProvider.overrideWith((ref) => MockThermalNotifier(
              ThermalState(telemetry: normalTelemetry),
            )),
            cpuProvider.overrideWith((ref) => MockCpuNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: ThermalModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THERMAL RADAR MODULE'), findsOneWidget);

      // Verify active toggle (LIVE VIEW) in light mode
      final liveToggleFinder = find.ancestor(
        of: find.text('LIVE VIEW'),
        matching: find.byType(Container),
      ).first;
      final lightLiveDec = tester.widget<Container>(liveToggleFinder).decoration as BoxDecoration;
      expect(lightLiveDec.color, equals(HudColor.lightAccentCyan.withValues(alpha: 0.1)));
      expect((lightLiveDec.border as Border).top.color, equals(HudColor.lightAccentCyan));

      final lightLiveText = tester.widget<Text>(find.text('LIVE VIEW'));
      expect(lightLiveText.style?.color, equals(HudColor.lightAccentCyan));

      // Verify inactive toggle (HISTORY) in light mode
      final historyToggleFinder = find.ancestor(
        of: find.text('HISTORY'),
        matching: find.byType(Container),
      ).first;
      final lightHistDec = tester.widget<Container>(historyToggleFinder).decoration as BoxDecoration;
      expect(lightHistDec.color, equals(Colors.transparent));
      expect((lightHistDec.border as Border).top.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      final lightHistText = tester.widget<Text>(find.text('HISTORY'));
      expect(lightHistText.style?.color, equals(HudColor.lightTextDim));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thermalProvider.overrideWith((ref) => MockThermalNotifier(
              ThermalState(telemetry: normalTelemetry),
            )),
            cpuProvider.overrideWith((ref) => MockCpuNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: ThermalModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkLiveDec = tester.widget<Container>(liveToggleFinder).decoration as BoxDecoration;
      expect(darkLiveDec.color, equals(HudColor.darkAccentCyan.withValues(alpha: 0.1)));
      expect((darkLiveDec.border as Border).top.color, equals(HudColor.darkAccentCyan));

      final darkLiveText = tester.widget<Text>(find.text('LIVE VIEW'));
      expect(darkLiveText.style?.color, equals(HudColor.darkAccentCyan));

      final darkHistDec = tester.widget<Container>(historyToggleFinder).decoration as BoxDecoration;
      expect(darkHistDec.color, equals(Colors.transparent));
      expect((darkHistDec.border as Border).top.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      final darkHistText = tester.widget<Text>(find.text('HISTORY'));
      expect(darkHistText.style?.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Critical overheat alert badge adapts to hud.accentRed in light and dark mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode Overheat Alert
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thermalProvider.overrideWith((ref) => MockThermalNotifier(
              ThermalState(telemetry: criticalTelemetry, thermalThresholdCelsius: 85),
            )),
            cpuProvider.overrideWith((ref) => MockCpuNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: ThermalModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('OVERHEAT ALERT'), findsOneWidget);
      final lightAlertText = tester.widget<Text>(find.text('OVERHEAT ALERT'));
      expect(lightAlertText.style?.color, equals(HudColor.lightAccentRed));

      final alertBannerFinder = find.ancestor(
        of: find.text('OVERHEAT ALERT'),
        matching: find.byType(Container),
      ).first;
      final lightAlertContainer = tester.widget<Container>(alertBannerFinder);
      expect(lightAlertContainer.color, equals(HudColor.lightAccentRed.withValues(alpha: 0.2)));

      // 2. Dark Mode Overheat Alert
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thermalProvider.overrideWith((ref) => MockThermalNotifier(
              ThermalState(telemetry: criticalTelemetry, thermalThresholdCelsius: 85),
            )),
            cpuProvider.overrideWith((ref) => MockCpuNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: ThermalModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkAlertText = tester.widget<Text>(find.text('OVERHEAT ALERT'));
      expect(darkAlertText.style?.color, equals(HudColor.darkAccentRed));

      final darkAlertContainer = tester.widget<Container>(alertBannerFinder);
      expect(darkAlertContainer.color, equals(HudColor.darkAccentRed.withValues(alpha: 0.2)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Thermal sections use hudPanelDecoration adapting between themes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Light Mode Section Panels
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thermalProvider.overrideWith((ref) => MockThermalNotifier(
              ThermalState(telemetry: normalTelemetry),
            )),
            cpuProvider.overrideWith((ref) => MockCpuNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: ThermalModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightSectionPanelFinder = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).color == HudColor.lightBgPanel));
      expect(lightSectionPanelFinder, findsWidgets);

      // Dark Mode Section Panels
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            thermalProvider.overrideWith((ref) => MockThermalNotifier(
              ThermalState(telemetry: normalTelemetry),
            )),
            cpuProvider.overrideWith((ref) => MockCpuNotifier()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: ThermalModuleScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkSectionPanelFinder = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          ((w.decoration as BoxDecoration).color == HudColor.darkBgPanel));
      expect(darkSectionPanelFinder, findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

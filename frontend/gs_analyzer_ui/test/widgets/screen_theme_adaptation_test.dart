import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/providers/automation_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/screen/automation_screen.dart';
import 'package:gs_analyzer_ui/screen/network_module_screen.dart';
import 'package:gs_analyzer_ui/screen/telemetry_history_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/side_bar_widget.dart';
import 'package:mocktail/mocktail.dart';

class MockEmptyRulesNotifier extends AutomationRulesNotifier {
  @override
  Future<List<AutomationRule>> build() async => [];
}

class MockNetworkNotifier extends StateNotifier<NetworkState> implements NetworkNotifier {
  MockNetworkNotifier([NetworkState state = const NetworkState()]) : super(state);

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
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/global_sidebar_widget.dart';

class MockSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  MockSettingsNotifier([SettingsState state = const SettingsState(isLoading: false)])
      : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('GlobalSidebarWidget Tests', () {
    testWidgets('Expanded sidebar renders STORAGE item without lock icon', (tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: GlobalSidebarWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially collapsed: STORAGE label is not visible
      expect(find.text('STORAGE'), findsNothing);

      // Expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Now STORAGE label is visible
      expect(find.text('STORAGE'), findsOneWidget);

      // Crucially, Icons.lock is NOT rendered (removed lock icon for storage)
      expect(find.byIcon(Icons.lock), findsNothing);

      // STORAGE icon is present
      expect(find.byIcon(Icons.storage_outlined), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping STORAGE text in expanded sidebar navigates to AppRoute.storage', (tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: GlobalSidebarWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), equals(AppRoute.dashboard));

      // Expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap on STORAGE label
      await tester.tap(find.text('STORAGE'));
      await tester.pumpAndSettle();

      // Navigation should now be on AppRoute.storage
      expect(container.read(navigationProvider), equals(AppRoute.storage));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Tapping storage icon in collapsed sidebar navigates to AppRoute.storage', (tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: GlobalSidebarWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), equals(AppRoute.dashboard));

      // Tap storage icon directly
      await tester.tap(find.byIcon(Icons.storage_outlined));
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), equals(AppRoute.storage));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Active indicator reflects AppRoute.storage selection', (tester) async {
      final container = ProviderContainer(
        overrides: [
          navigationProvider.overrideWith((ref) => AppRoute.storage),
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: GlobalSidebarWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the storage icon and its parent row
      final storageIconFinder = find.byIcon(Icons.storage_outlined);
      expect(storageIconFinder, findsOneWidget);

      final iconWidget = tester.widget<Icon>(storageIconFinder);
      expect(iconWidget.color, equals(HudColor.darkAccentCyan));

      // Verify no lock icon exists
      expect(find.byIcon(Icons.lock), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

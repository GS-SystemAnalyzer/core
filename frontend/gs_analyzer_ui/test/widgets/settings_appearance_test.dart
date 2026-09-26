import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/screen/settings_screen.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

class MockSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  MockSettingsNotifier(SettingsState state) : super(state);

  int updateUICount = 0;

  @override
  void updateUI() {
    updateUICount++;
    state = state.copyWith(
      currentSettings: state.currentSettings?.clone(),
      validationErrors: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SettingsScreen Appearance Section Tests', () {
    testWidgets('Tapping light mode toggle updates theme and triggers updateUI', (tester) async {
      final initialSettings = AppSettings.fromjson({
        'appearance': {
          'theme': 'cyber_dark',
          'accentColor': 'cyan',
          'compactMode': true,
          'showAnimations': true,
        },
      });

      final notifier = MockSettingsNotifier(
        SettingsState(
          isLoading: false,
          savedSettings: initialSettings,
          currentSettings: initialSettings.clone(),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(Colors.cyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down to the APPEARANCE section
      final appearanceFinder = find.text('APPEARANCE');
      await tester.scrollUntilVisible(appearanceFinder, 300);
      await tester.pumpAndSettle();

      // Find the LIGHT MODE label and scroll until visible
      final lightModeLabel = find.text('LIGHT MODE');
      await tester.scrollUntilVisible(lightModeLabel, 100);
      await tester.pumpAndSettle();

      // Tap on LIGHT MODE
      await tester.tap(lightModeLabel);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.theme, equals('cyber_light'));
      expect(notifier.updateUICount, greaterThan(0));
      expect(notifier.state.hasUnsavedChanges, isTrue);

      // Tap on SYSTEM MODE
      final systemModeLabel = find.text('SYSTEM MODE');
      await tester.scrollUntilVisible(systemModeLabel, 50);
      await tester.pumpAndSettle();
      await tester.tap(systemModeLabel);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.theme, equals('system'));

      // Tap on DARK MODE
      final darkModeLabel = find.text('DARK MODE');
      await tester.scrollUntilVisible(darkModeLabel, 50);
      await tester.pumpAndSettle();
      await tester.tap(darkModeLabel);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.theme, equals('cyber_dark'));
    });

    testWidgets('Tapping color swatches updates accentColor', (tester) async {
      final initialSettings = AppSettings.fromjson({
        'appearance': {
          'theme': 'cyber_dark',
          'accentColor': 'cyan',
        },
      });

      final notifier = MockSettingsNotifier(
        SettingsState(
          isLoading: false,
          savedSettings: initialSettings,
          currentSettings: initialSettings.clone(),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(Colors.cyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to ACCENT COLOR label and drag a bit more to bring swatches fully into view
      final accentLabel = find.text('ACCENT COLOR');
      await tester.scrollUntilVisible(accentLabel, 300);
      await tester.drag(find.byType(ListView), const Offset(0, -150));
      await tester.pumpAndSettle();

      // Find green and amber swatch GestureDetector widgets
      final greenSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == Colors.greenAccent);
      expect(greenSwatch, findsOneWidget);

      await tester.tap(greenSwatch);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.accentColor, equals('green'));

      final amberSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == Colors.amber);
      expect(amberSwatch, findsOneWidget);

      await tester.tap(amberSwatch);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.accentColor, equals('amber'));
    });
  });
}

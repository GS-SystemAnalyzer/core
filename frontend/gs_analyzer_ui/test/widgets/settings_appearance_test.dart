import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/screen/settings_screen.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
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
  Future<bool> resetToDefaults() async {
    return true;
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
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.darkAccentGreen);
      expect(greenSwatch, findsOneWidget);

      await tester.tap(greenSwatch);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.accentColor, equals('green'));

      final amberSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.darkAccentAmber);
      expect(amberSwatch, findsOneWidget);

      await tester.tap(amberSwatch);
      await tester.pumpAndSettle();

      expect(notifier.state.currentSettings?.appearance.accentColor, equals('amber'));
    });

    testWidgets('Appearance color swatches adapt between light and dark themes', (tester) async {
      final settings = AppSettings.fromjson({
        'appearance': {
          'theme': 'cyber_dark',
          'accentColor': 'cyan',
        },
      });

      // 1. Render in Light Theme
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, savedSettings: settings, currentSettings: settings.clone()),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final accentLabel = find.text('ACCENT COLOR');
      await tester.scrollUntilVisible(accentLabel, 300);
      await tester.drag(find.byType(ListView), const Offset(0, -150));
      await tester.pumpAndSettle();

      // Swatches in Light Theme should use light accent tokens
      final lightCyanSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.lightAccentCyan);
      expect(lightCyanSwatch, findsOneWidget);

      final lightGreenSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.lightAccentGreen);
      expect(lightGreenSwatch, findsOneWidget);

      final lightAmberSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.lightAccentAmber);
      expect(lightAmberSwatch, findsOneWidget);

      // 2. Render in Dark Theme
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, savedSettings: settings, currentSettings: settings.clone()),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkCyanSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.darkAccentCyan);
      expect(darkCyanSwatch, findsOneWidget);

      final darkGreenSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.darkAccentGreen);
      expect(darkGreenSwatch, findsOneWidget);

      final darkAmberSwatch = find.byWidgetPredicate((w) =>
          w is GestureDetector &&
          w.child is Container &&
          ((w.child as Container).decoration as BoxDecoration?)?.color == HudColor.darkAccentAmber);
      expect(darkAmberSwatch, findsOneWidget);
    });

    testWidgets('Error state renders error icon with hud.accentRed in light and dark mode', (tester) async {
      // Light Mode Error Icon
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              const SettingsState(isLoading: false, currentSettings: null),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightErrorIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(lightErrorIcon.color, equals(HudColor.lightAccentRed));

      // Dark Mode Error Icon
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              const SettingsState(isLoading: false, currentSettings: null),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkErrorIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(darkErrorIcon.color, equals(HudColor.darkAccentRed));
    });

    testWidgets('Reset button and confirmation dialog adapt to hud.accentRed in light and dark mode', (tester) async {
      final settings = AppSettings.fromjson({
        'appearance': {'theme': 'cyber_light', 'accentColor': 'cyan'},
      });

      // 1. Verify in Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, savedSettings: settings, currentSettings: settings.clone()),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final resetBtnFinder = find.widgetWithText(OutlinedButton, 'RESET TO DEFAULTS');
      await tester.scrollUntilVisible(resetBtnFinder, 300);
      await tester.pumpAndSettle();

      final lightResetBtn = tester.widget<OutlinedButton>(resetBtnFinder);
      expect(lightResetBtn.style?.side?.resolve({})?.color, equals(HudColor.lightAccentRed));
      expect(lightResetBtn.style?.foregroundColor?.resolve({}), equals(HudColor.lightAccentRed));

      // Tap Reset button to open confirm dialog in Light Mode
      await tester.tap(resetBtnFinder);
      await tester.pumpAndSettle();

      expect(find.text('CONFIRM OVERWRITE '), findsOneWidget);
      final lightConfirmBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRM OVERWRITE '));
      expect(lightConfirmBtn.style?.backgroundColor?.resolve({}), equals(HudColor.lightAccentRed));

      // Dismiss dialog
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      // 2. Verify in Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => MockSettingsNotifier(
              SettingsState(isLoading: false, savedSettings: settings, currentSettings: settings.clone()),
            )),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(resetBtnFinder, 300);
      await tester.pumpAndSettle();

      final darkResetBtn = tester.widget<OutlinedButton>(resetBtnFinder);
      expect(darkResetBtn.style?.side?.resolve({})?.color, equals(HudColor.darkAccentRed));
      expect(darkResetBtn.style?.foregroundColor?.resolve({}), equals(HudColor.darkAccentRed));

      // Tap Reset button to open confirm dialog in Dark Mode
      await tester.tap(resetBtnFinder);
      await tester.pumpAndSettle();

      final darkConfirmBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CONFIRM OVERWRITE '));
      expect(darkConfirmBtn.style?.backgroundColor?.resolve({}), equals(HudColor.darkAccentRed));

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

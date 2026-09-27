import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class TestSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  TestSettingsNotifier(SettingsState state) : super(state);

  @override
  void updateUI() {
    state = state.copyWith(
      currentSettings: state.currentSettings?.clone(),
      validationErrors: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestThemeApp extends ConsumerWidget {
  const TestThemeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(
      settingsProvider.select((s) => s.currentSettings?.appearance.theme),
    );
    final accentKey = ref.watch(
      settingsProvider.select((s) => s.currentSettings?.appearance.accentColor),
    );

    final lightAccent = HudColor.resolveAccent(accentKey, Brightness.light);
    final darkAccent = HudColor.resolveAccent(accentKey, Brightness.dark);
    final themeMode = HudTheme.resolveThemeMode(theme);

    return MaterialApp(
      theme: HudTheme.lightTheme(lightAccent),
      darkTheme: HudTheme.darkTheme(darkAccent),
      themeMode: themeMode,
      home: Scaffold(
        body: Builder(
          builder: (ctx) {
            final hud = ctx.HudTheme;
            return Container(
              color: hud.base,
              child: Text(
                'THEME_MODE_${themeMode.name.toUpperCase()}',
                style: TextStyle(color: hud.accentColor),
              ),
            );
          },
        ),
      ),
    );
  }
}

void main() {
  group('ThemeMode Real-Time Rebuild Tests', () {
    testWidgets('App updates themeMode immediately when appearance.theme changes', (tester) async {
      final initialSettings = AppSettings.fromjson({
        'appearance': {
          'theme': 'cyber_dark',
          'accentColor': 'cyan',
        },
      });

      final notifier = TestSettingsNotifier(
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
          child: const TestThemeApp(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial State should be dark
      MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(find.text('THEME_MODE_DARK'), findsOneWidget);

      // 2. Mutate to cyber_light and call updateUI (simulating what SettingsScreen does)
      notifier.state.currentSettings!.appearance.theme = 'cyber_light';
      notifier.updateUI();
      await tester.pumpAndSettle();

      // 3. MaterialApp should immediately update to ThemeMode.light without hot reload
      app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);
      expect(find.text('THEME_MODE_LIGHT'), findsOneWidget);

      // 4. Mutate to system and call updateUI
      notifier.state.currentSettings!.appearance.theme = 'system';
      notifier.updateUI();
      await tester.pumpAndSettle();

      // 5. MaterialApp should immediately update to ThemeMode.system
      app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.system);
      expect(find.text('THEME_MODE_SYSTEM'), findsOneWidget);
    });

    testWidgets('App updates accent colors immediately when appearance.accentColor changes', (tester) async {
      final initialSettings = AppSettings.fromjson({
        'appearance': {
          'theme': 'cyber_dark',
          'accentColor': 'cyan',
        },
      });

      final notifier = TestSettingsNotifier(
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
          child: const TestThemeApp(),
        ),
      );
      await tester.pumpAndSettle();

      MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.darkTheme?.colorScheme.primary, equals(HudColor.darkAccentCyan));

      // Switch to green accent
      notifier.state.currentSettings!.appearance.accentColor = 'green';
      notifier.updateUI();
      await tester.pumpAndSettle();

      app = tester.widget(find.byType(MaterialApp));
      expect(app.darkTheme?.colorScheme.primary, equals(HudColor.darkAccentGreen));
      expect(app.theme?.colorScheme.primary, equals(HudColor.lightAccentGreen));

      // Switch to amber accent
      notifier.state.currentSettings!.appearance.accentColor = 'amber';
      notifier.updateUI();
      await tester.pumpAndSettle();

      app = tester.widget(find.byType(MaterialApp));
      expect(app.darkTheme?.colorScheme.primary, equals(HudColor.darkAccentAmber));
      expect(app.theme?.colorScheme.primary, equals(HudColor.lightAccentAmber));
    });
  });
}

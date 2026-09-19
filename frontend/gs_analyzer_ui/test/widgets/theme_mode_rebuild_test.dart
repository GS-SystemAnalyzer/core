import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hud_colors.dart';
import 'package:gs_analyzer_ui/core/theme/hud_theme.dart';

class TestSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  TestSettingsNotifier(SettingsState state) : super(state);

  @override
  void updateUI() {
    state = state.copyWith(
      currentSettings: state.currentSettings,
      validationErrors: [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestApp extends ConsumerWidget {
  const TestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(
      settingsProvider.select((s) => s.currentSettings?.appearance.theme),
    );
    final accentKey = ref.watch(
      settingsProvider.select((s) => s.currentSettings?.appearance.accentColor),
    );

    final lightAccent = HudColors.resolveAccent(accentKey, Brightness.light);
    final darkAccent = HudColors.resolveAccent(accentKey, Brightness.dark);
    final themeMode = HudTheme.resolveThemeMode(theme);

    return MaterialApp(
      theme: HudTheme.lightTheme(lightAccent),
      darkTheme: HudTheme.darkTheme(darkAccent),
      themeMode: themeMode,
      home: const SizedBox(),
    );
  }
}

void main() {
  testWidgets('TestApp updates themeMode immediately when theme changes',
      (tester) async {
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
        currentSettings: initialSettings,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => notifier),
        ],
        child: const TestApp(),
      ),
    );
    await tester.pump();

    // Verify initial themeMode is dark
    MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    // Now mutate theme and call updateUI (simulating what SettingsScreen does)
    notifier.state.currentSettings!.appearance.theme = 'cyber_light';
    notifier.updateUI();
    await tester.pump();

    // Check if MaterialApp received the updated themeMode immediately
    app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);

    // Switch to system mode
    notifier.state.currentSettings!.appearance.theme = 'system';
    notifier.updateUI();
    await tester.pump();

    app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
  });
}

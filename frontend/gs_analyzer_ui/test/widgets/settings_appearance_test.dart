import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/models/cache_stats.dart';
import 'package:gs_analyzer_ui/providers/cache_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/screen/settings_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

class TestSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  TestSettingsNotifier(SettingsState state) : super(state);

  @override
  void updateUI() {
    state = state.copyWith(currentSettings: state.currentSettings);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
    when(() => mockApi.getCacheStats()).thenAnswer(
      (_) async => CacheStats(
        activeEntries: 100,
        rootCount: 1,
        approximateMemoryBytes: 1024,
        hitRate: 0.9,
      ),
    );
  });

  bool getSwitchValueForLabel(WidgetTester tester, String label) {
    final rowFinder = find.ancestor(
      of: find.text(label),
      matching: find.byType(Row),
    );
    final switchFinder = find.descendant(
      of: rowFinder,
      matching: find.byType(Switch),
    );
    final switchWidget = tester.widget<Switch>(switchFinder);
    return switchWidget.value;
  }

  testWidgets(
      'Appearance section switches modes mutually exclusively between Dark, Light, and System',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final initialSettings = AppSettings.fromjson({
      'appearance': {
        'theme': 'cyber_dark',
        'accentColor': 'cyan',
        'compactMode': true,
        'showAnimations': true,
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
          cacheStatsApiProvider.overrideWithValue(mockApi),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initially Dark Mode is ON, Light Mode is OFF, System Mode is OFF
    expect(getSwitchValueForLabel(tester, 'DARK MODE'), isTrue);
    expect(getSwitchValueForLabel(tester, 'LIGHT MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'SYSTEM MODE'), isFalse);

    // 2. Tap LIGHT MODE toggle
    await tester.tap(find.text('LIGHT MODE'));
    await tester.pumpAndSettle();

    // Light Mode should now be ON, Dark Mode OFF, System Mode OFF
    expect(getSwitchValueForLabel(tester, 'DARK MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'LIGHT MODE'), isTrue);
    expect(getSwitchValueForLabel(tester, 'SYSTEM MODE'), isFalse);
    expect(notifier.state.currentSettings?.appearance.theme, 'cyber_light');

    // 3. Tap SYSTEM MODE toggle
    await tester.tap(find.text('SYSTEM MODE'));
    await tester.pumpAndSettle();

    // System Mode should now be ON, Dark Mode OFF, Light Mode OFF
    expect(getSwitchValueForLabel(tester, 'DARK MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'LIGHT MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'SYSTEM MODE'), isTrue);
    expect(notifier.state.currentSettings?.appearance.theme, 'system');

    // 4. Tap SYSTEM MODE again (tapping already active mode)
    await tester.tap(find.text('SYSTEM MODE'));
    await tester.pumpAndSettle();

    // System Mode must remain active, ensuring modes never turn all-off
    expect(getSwitchValueForLabel(tester, 'DARK MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'LIGHT MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'SYSTEM MODE'), isTrue);
    expect(notifier.state.currentSettings?.appearance.theme, 'system');

    // 5. Tap DARK MODE toggle to switch back
    await tester.tap(find.text('DARK MODE'));
    await tester.pumpAndSettle();

    expect(getSwitchValueForLabel(tester, 'DARK MODE'), isTrue);
    expect(getSwitchValueForLabel(tester, 'LIGHT MODE'), isFalse);
    expect(getSwitchValueForLabel(tester, 'SYSTEM MODE'), isFalse);
    expect(notifier.state.currentSettings?.appearance.theme, 'cyber_dark');
  });
}

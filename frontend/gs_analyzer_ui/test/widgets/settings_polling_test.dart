import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/cache_stats_provider.dart';
import 'package:gs_analyzer_ui/screen/settings_screen.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

class PollingSettings extends StateNotifier<SettingsState> implements SettingsNotifier {
  PollingSettings(int period, bool confirmed) : super(SettingsState(isLoading: false,
      savedSettings: AppSettings.fromjson({'monitoring': {'ramPollIntervalMs': period}}),
      currentSettings: AppSettings.fromjson({'monitoring': {'ramPollIntervalMs': period}}),
      serviceConfirmed: confirmed));
  @override
  void updateUI() => state = state.copyWith(currentSettings: state.currentSettings!.clone());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<PollingSettings> host(WidgetTester tester, int period, bool confirmed) async {
    final notifier = PollingSettings(period, confirmed);
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => notifier),
      cacheStatsProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(container.dispose);
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
        child: MaterialApp(theme: HudTheme.darkTheme(HudColor.darkAccentAmber), home: const SettingsScreen())));
    await tester.pump();
    return notifier;
  }

  testWidgets('RAM slider bounds divisions and display match actual model', (tester) async {
    final notifier = await host(tester, 1000, true);
    await tester.ensureVisible(find.text('RAM POLL'));
    final row = find.ancestor(of: find.text('RAM POLL'), matching: find.byType(Row)).first;
    final slider = tester.widget<Slider>(find.descendant(of: row, matching: find.byType(Slider)));
    expect(slider.min, 200);
    expect(slider.max, 5000);
    expect(slider.divisions, 4800);
    expect(slider.value, 1000);
    expect(slider.activeColor, HudColor.darkAccentAmber);
    expect(find.text('1000 MS'), findsOneWidget);
    expect(find.text('RAM POLL CONFIRMED'), findsOneWidget);
    slider.onChanged!(5000);
    await tester.pump();
    expect(notifier.state.currentSettings!.monitoring.ramPollIntervalMs, 5000);
    expect(find.text('5000 MS'), findsOneWidget);
    expect(find.text('RAM POLL UNSAVED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported actual value stays visible and requires explicit draft change', (tester) async {
    final notifier = await host(tester, 6000, false);
    await tester.ensureVisible(find.text('USE 1000 MS'));
    expect(find.text('RAM POLL: 6000 MS — UNSUPPORTED'), findsOneWidget);
    expect(find.text('RAM POLL UNCONFIRMED'), findsOneWidget);
    await tester.tap(find.text('USE 1000 MS'));
    await tester.pump();
    expect(notifier.state.currentSettings!.monitoring.ramPollIntervalMs, 1000);
    expect(notifier.state.savedSettings!.monitoring.ramPollIntervalMs, 6000);
    expect(find.text('1000 MS'), findsOneWidget);
    expect(find.text('RAM POLL UNSAVED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

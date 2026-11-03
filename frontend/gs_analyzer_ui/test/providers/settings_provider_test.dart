import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockSettingsApi extends Mock implements ApiService {}

Map<String, dynamic> settingsJson(int ram, {int cpu = 5000}) =>
    AppSettings.fromjson({'monitoring': {'ramPollIntervalMs': ram, 'cpuPollIntervalMs': cpu},
      'advanced': {'backendPort': 8080}}).toJson();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockSettingsApi api;
  setUpAll(() => registerFallbackValue(<String, dynamic>{}));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = MockSettingsApi();
    when(() => api.getSettings()).thenAnswer((_) async => null);
  });

  ProviderContainer createContainer() => ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) => SettingsNotifier(api)),
  ]);

  test('legacy cache migration changes RAM only and remains provisional', () async {
    SharedPreferences.setMockInitialValues({'gs_settings_cache': jsonEncode(settingsJson(6000))});
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.initialized;
    final state = container.read(settingsProvider);
    expect(state.currentSettings!.monitoring.ramPollIntervalMs, 1000);
    expect(state.currentSettings!.monitoring.cpuPollIntervalMs, 5000);
    expect(state.currentSettings!.advanced.backendPort, 8080);
    expect(state.ramCadenceConfirmed, isFalse);
    verifyNever(() => api.saveSettings(any()));
  });

  test('accepted remote cadence is confirmed and cached', () async {
    when(() => api.getSettings()).thenAnswer((_) async => settingsJson(1500));
    final container = createContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).initialized;
    expect(container.read(settingsProvider).ramCadenceConfirmed, isTrue);
    expect(container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs, 1500);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('gs_settings_cache')!)['monitoring']['ramPollIntervalMs'], 1500);
  });

  test('supported 2000ms remote cadence remains confirmed without an automatic POST', () async {
    when(() => api.getSettings()).thenAnswer((_) async => settingsJson(2000));
    final container = createContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).initialized;
    expect(container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs, 2000);
    expect(container.read(settingsProvider).ramCadenceConfirmed, isTrue);
    expect(container.read(settingsProvider).persistenceError, isNull);
    verifyNever(() => api.saveSettings(any()));
  });

  test('invalid edited RAM draft is rejected before POST', () async {
    when(() => api.getSettings()).thenAnswer((_) async => settingsJson(1500));
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.initialized;
    for (final period in [199, 5001]) {
      container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs = period;
      notifier.updateUI();
      expect(await notifier.saveChanges(), isFalse);
      expect(container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs, period);
    }
    verifyNever(() => api.saveSettings(any()));
  });

  test('acknowledged save owns its snapshot and preserves a newer in-flight draft', () async {
    when(() => api.getSettings()).thenAnswer((_) async => settingsJson(1500));
    final release = Completer<Map<String, dynamic>?>();
    when(() => api.saveSettings(any())).thenAnswer((_) => release.future);
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await notifier.initialized;
    container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs = 1750;
    notifier.updateUI();
    final pending = notifier.saveChanges();
    container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs = 2000;
    notifier.updateUI();
    release.complete({'success': true, 'data': settingsJson(1750)});
    expect(await pending, isTrue);
    final state = container.read(settingsProvider);
    expect(state.savedSettings!.monitoring.ramPollIntervalMs, 1750);
    expect(state.currentSettings!.monitoring.ramPollIntervalMs, 2000);
    expect(state.hasUnsavedChanges, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('gs_settings_cache')!)['monitoring']['ramPollIntervalMs'], 1750);
  });

  test('remote GET preserves edits made after provisional cache load', () async {
    SharedPreferences.setMockInitialValues({'gs_settings_cache': jsonEncode(settingsJson(1700))});
    final requested = Completer<void>();
    final response = Completer<Map<String, dynamic>?>();
    when(() => api.getSettings()).thenAnswer((_) {
      requested.complete();
      return response.future;
    });
    final container = createContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    await requested.future;
    container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs = 1900;
    notifier.updateUI();
    response.complete(settingsJson(1500));
    await notifier.initialized;
    expect(container.read(settingsProvider).savedSettings!.monitoring.ramPollIntervalMs, 1500);
    expect(container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs, 1900);
    expect(container.read(settingsProvider).hasUnsavedChanges, isTrue);
  });

  test('supported cached cadence is preserved while confirmation is pending', () async {
    SharedPreferences.setMockInitialValues({'gs_settings_cache': jsonEncode(settingsJson(2000))});
    final container = createContainer();
    addTearDown(container.dispose);
    await container.read(settingsProvider.notifier).initialized;
    expect(container.read(settingsProvider).currentSettings!.monitoring.ramPollIntervalMs, 2000);
    expect(container.read(settingsProvider).ramCadenceConfirmed, isFalse);
    verifyNever(() => api.saveSettings(any()));
  });
}

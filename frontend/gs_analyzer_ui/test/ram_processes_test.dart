import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mock_factory.dart';

class _RamApi extends Mock implements ApiService {}

class _RamSettings extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  _RamSettings() : super(const SettingsState(isLoading: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  ProviderContainer createContainer([Duration Function()? elapsedNow]) {
    final api = _RamApi();
    when(() => api.startRamRadar()).thenAnswer((_) async {});
    final container = ProviderContainer(
      overrides: [
        ramProvider.overrideWith((ref) => RamNotifier(ref, api, elapsedNow)),
        settingsProvider.overrideWith((ref) => _RamSettings()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('RAM Telemetry Engine Test', () {
    test(
      'Test 1: Math & Formating (Translate raw bytes to readable strings',
      () {
        final container = createContainer();
        final ramNotifier = container.read(ramProvider.notifier);

        final rawTelemetry = MockFactory.generateRamTelemetry(
          activeGb: 8.0,
          totalGb: 16.0,
        );

        ramNotifier.updateProcesses(rawTelemetry);

        final state = ramNotifier.state;

        expect(state.activeGb, 8.0, reason: 'Percentage math is incorrect!');

        expect(
          state.displayedString,
          '8.00 GB / 16.00 GB',
          reason:
              'CRITICAL: The UI string formatter failed to convert bytes to GB!',
        );
      },
    );

    test('Test 2: The Overload Shield (Triggers warning state at 90% usage)', () {
      final container = createContainer();
      final notifier = container.read(ramProvider.notifier);

      final criticalTelemetry = MockFactory.generateRamTelemetry(
        activeGb: 15.2,
        totalGb: 16.0,
      );

      notifier.updateProcesses(criticalTelemetry);

      expect(
        notifier.state.isCritical,
        true,
        reason:
            'CRITICAL FAILURE: The engine did not warn the UI of a RAM overload!',
      );
    });

    for (final seconds in [2, 5]) {
      test(
        'Test 3: History retains latest 20 observed points at ${seconds}s intervals',
        () {
          var elapsed = Duration.zero;
          final container = createContainer(() => elapsed);
          final notifier = container.read(ramProvider.notifier);
          final observedValues = <double>[];

          for (var i = 0; i < 25; i++) {
            elapsed = Duration(seconds: i * seconds);
            final activeGb = i * 0.1;
            notifier.updateProcesses(
              MockFactory.generateRamTelemetry(
                activeGb: activeGb,
                totalGb: 16.0,
              ),
            );
            observedValues.add(activeGb / 16.0);
          }

          expect(
            notifier.state.usageHistory.length,
            20,
            reason: 'History must remain capped at 20 recorded observations',
          );
          expect(notifier.state.usageHistory, observedValues.skip(5).toList());
        },
      );
    }

    test(
      'History suppresses sub-two-second frames and records at the boundary',
      () {
        var elapsed = Duration.zero;
        final container = createContainer(() => elapsed);
        final notifier = container.read(ramProvider.notifier);

        void observe(double activeGb) {
          notifier.updateProcesses(
            MockFactory.generateRamTelemetry(activeGb: activeGb, totalGb: 16.0),
          );
        }

        observe(1.0);
        for (var i = 1; i <= 25; i++) {
          elapsed = Duration(milliseconds: i * 50);
          observe(1.0 + i * 0.01);
        }
        expect(notifier.state.activeGb, 1.25);
        expect(notifier.state.usageHistory, [1.0 / 16.0]);

        elapsed = const Duration(milliseconds: 1999);
        observe(2.0);
        expect(notifier.state.activeGb, 2.0);
        expect(notifier.state.usageHistory, [1.0 / 16.0]);

        elapsed = const Duration(seconds: 2);
        observe(3.0);
        expect(notifier.state.activeGb, 3.0);
        expect(notifier.state.usageHistory, [1.0 / 16.0, 3.0 / 16.0]);
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/window_provider.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';

class MockSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  MockSettingsNotifier(SettingsState state) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HudDensityProvider Tests', () {
    test('maximized + savedCompact=true -> Standard density', () {
      final container = ProviderContainer(
        overrides: [
          windowMaximizedProvider.overrideWith((ref) => true),
          settingsProvider.overrideWith(
            (ref) => MockSettingsNotifier(
              SettingsState(
                currentSettings: AppSettings.fromjson({
                  'appearance': {'compactMode': true},
                }),
              ),
            ),
          ),
        ],
      );

      final d = container.read(hudDensityProvider);

      // Standard: maximized ignores compact setting
      expect(d.isMax, isTrue);
      expect(d.gap, 16.0);
      expect(d.panelPad, 24.0);
    });

    test('not maximized + savedCompact=true -> Compact density', () {
      final container = ProviderContainer(
        overrides: [
          windowMaximizedProvider.overrideWith((ref) => false),
          settingsProvider.overrideWith(
            (ref) => MockSettingsNotifier(
              SettingsState(
                currentSettings: AppSettings.fromjson({
                  'appearance': {'compactMode': true},
                }),
              ),
            ),
          ),
        ],
      );

      final d = container.read(hudDensityProvider);

      // Compact
      expect(d.isMax, isFalse);
      expect(d.gap, 8.0);
      expect(d.panelPad, 12.0);
    });

    test('not maximized + savedCompact=false -> Standard density', () {
      final container = ProviderContainer(
        overrides: [
          windowMaximizedProvider.overrideWith((ref) => false),
          settingsProvider.overrideWith(
            (ref) => MockSettingsNotifier(
              SettingsState(
                currentSettings: AppSettings.fromjson({
                  'appearance': {'compactMode': false},
                }),
              ),
            ),
          ),
        ],
      );

      final d = container.read(hudDensityProvider);

      // Standard
      expect(d.isMax, isFalse);
      expect(d.gap, 16.0);
      expect(d.panelPad, 24.0);
    });
  });
}

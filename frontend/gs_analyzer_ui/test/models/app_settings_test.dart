import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';

void main() {
  group('AppearanceSettings serialization', () {
    test('compactMode defaults to true when parsing empty json', () {
      final settings = AppearanceSettings.fromJson({});
      expect(
        settings.compactMode,
        isTrue,
        reason:
            'Compact Mode must default to true to match native Task Manager feel',
      );
    });

    test('fromJson and toJson round-trips correctly', () {
      final jsonPayload = {
        'theme': 'light',
        'accentColor': 'green',
        'compactMode': false,
        'showAnimations': true,
      };

      final settings = AppearanceSettings.fromJson(jsonPayload);

      expect(settings.theme, 'light');
      expect(settings.accentColor, 'green');
      expect(settings.compactMode, isFalse);
      expect(settings.showAnimations, isTrue);

      final outJson = settings.toJson();

      expect(outJson['theme'], 'light');
      expect(outJson['accentColor'], 'green');
      expect(outJson['compactMode'], false);
      expect(outJson['showAnimations'], true);
    });
  });

  group('CacheSettings serialization', () {
    test('defaults match specifications', () {
      final cache = CacheSettings.fromJson({});
      expect(cache.scanCacheTtlMinutes, 15);
      expect(cache.maxCacheScans, 5);
      expect(cache.maxCachedNodes, 50000);
    });

    test('fromJson and toJson round-trips correctly', () {
      final json = {
        'scanCacheTtlMinutes': 60,
        'maxCacheScans': 10,
        'maxCachedNodes': 120000,
      };
      final cache = CacheSettings.fromJson(json);
      expect(cache.scanCacheTtlMinutes, 60);
      expect(cache.maxCacheScans, 10);
      expect(cache.maxCachedNodes, 120000);

      final out = cache.toJson();
      expect(out['scanCacheTtlMinutes'], 60);
      expect(out['maxCacheScans'], 10);
      expect(out['maxCachedNodes'], 120000);
    });
  });

  group('MonitoringSettings serialization', () {
    test('diskIoPollIntervalMs defaults to 1000', () {
      final mon = MonitoringSettings.fromJson({});
      expect(mon.diskIoPollIntervalMs, 1000);
    });

    test('fromJson and toJson round-trips correctly', () {
      final json = {
        'cpuPollIntervalMs': 1500,
        'ramPollIntervalMs': 2500,
        'thermalPollIntervalMs': 3000,
        'networkPollIntervalMs': 1200,
        'diskIoPollIntervalMs': 800,
        'scheduledScanIntervalMinutes': 30,
        'enableScheduledScans': true,
        'preferredNetworkInterfaceId': 'eth0',
      };
      final mon = MonitoringSettings.fromJson(json);
      expect(mon.diskIoPollIntervalMs, 800);
      expect(mon.networkPollIntervalMs, 1200);

      final out = mon.toJson();
      expect(out['diskIoPollIntervalMs'], 800);
      expect(out['networkPollIntervalMs'], 1200);
    });
  });
}

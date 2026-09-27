import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/models/cache_stats.dart';
import 'package:gs_analyzer_ui/providers/cache_stats_provider.dart';
import 'package:gs_analyzer_ui/screen/settings_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class MockApiService extends Mock implements ApiService {}

class MockSettingsNotifier extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  MockSettingsNotifier(SettingsState state) : super(state);

  bool clearCacheCalled = false;

  @override
  Future<bool> clearCache() async {
    clearCacheCalled = true;
    return true;
  }

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
  });

  group('CacheStats Provider & UI Tests', () {
    test('cacheStatsProvider returns CacheStats from API', () async {
      when(() => mockApi.getCacheStats()).thenAnswer(
        (_) async => CacheStats(
          activeEntries: 12481,
          rootCount: 2,
          approximateMemoryBytes: 88080384,
          hitRate: 0.91,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          cacheStatsApiProvider.overrideWithValue(mockApi),
        ],
      );

      final stats = await container.read(cacheStatsProvider.future);
      expect(stats, isNotNull);
      expect(stats!.activeEntries, 12481);
      expect(stats.formattedMemory, '84 MB');
      expect(stats.formattedHitRate, '91%');
    });

    testWidgets('SettingsScreen displays sliders, clear button and dim stats line',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      when(() => mockApi.getCacheStats()).thenAnswer(
        (_) async => CacheStats(
          activeEntries: 12481,
          rootCount: 2,
          approximateMemoryBytes: 88080384,
          hitRate: 0.91,
        ),
      );

      final settings = AppSettings.fromjson({
        'cache': {
          'scanCacheTtlMinutes': 15,
          'maxCacheScans': 5,
          'maxCachedNodes': 50000,
        },
      });

      final notifier = MockSettingsNotifier(
        SettingsState(
          isLoading: false,
          savedSettings: settings,
          currentSettings: settings,
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

      // Verify labels exist
      expect(find.text('SCAN CACHE TTL'), findsOneWidget);
      expect(find.text('MAX CACHED SCANS'), findsOneWidget);
      expect(find.text('MAX CACHED NODES'), findsOneWidget);
      expect(find.text('CLEAR CACHE NOW'), findsOneWidget);

      // Verify dim stats line is rendered
      expect(
        find.text('CACHED: 12,481 NODES · 84 MB · HIT RATE 91%'),
        findsOneWidget,
      );

      // Tap CLEAR CACHE NOW
      await tester.tap(find.text('CLEAR CACHE NOW'));
      await tester.pumpAndSettle();

      expect(notifier.clearCacheCalled, isTrue);
      expect(
        find.text('Cache cleared. Run a new Directory Scan to repopulate.'),
        findsOneWidget,
      );
    });
  });
}

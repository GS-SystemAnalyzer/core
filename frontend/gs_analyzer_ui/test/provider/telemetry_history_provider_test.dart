import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/telemetry_history_model.dart';
import 'package:gs_analyzer_ui/providers/telemetry_history_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  group('TelemetryHistoryProvider', () {
    late ProviderContainer container;
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
      container = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(mockApiService)],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is loading with default 5 minutes', () {
      when(() => mockApiService.fetchTelemetryHistory('cpu', 5)).thenAnswer((
        _,
      ) async {
        await Future.delayed(const Duration(seconds: 1));
        return null;
      });

      container.listen(telemetryHistoryProvider('cpu'), (_, __) {});
      final state = container.read(telemetryHistoryProvider('cpu'));

      expect(state.isLoading, true);
      expect(state.minutes, 5);
      expect(state.response, null);
    });

    test('fetchData success updates state correctly', () async {
      final mockResponse = TelemetryHistoryResponse(
        metric: 'cpu',
        minutes: 5,
        unit: '%',
        points: [],
        stats: TelemetryStats(min: 0, max: 0, avg: 0, current: 0),
      );

      when(
        () => mockApiService.fetchTelemetryHistory('cpu', 5),
      ).thenAnswer((_) async => mockResponse);

      container.listen(telemetryHistoryProvider('cpu'), (_, __) {});
      await Future.delayed(Duration.zero);

      final state = container.read(telemetryHistoryProvider('cpu'));
      expect(state.isLoading, false);
      expect(state.response, mockResponse);
      verify(() => mockApiService.fetchTelemetryHistory('cpu', 5)).called(1);
    });

    test('setTimeRange updates minutes and triggers refetch', () async {
      final mockResponse = TelemetryHistoryResponse(
        metric: 'cpu',
        minutes: 30,
        unit: '%',
        points: [],
        stats: TelemetryStats(min: 0, max: 0, avg: 0, current: 0),
      );

      when(
        () => mockApiService.fetchTelemetryHistory('cpu', 30),
      ).thenAnswer((_) async => mockResponse);

      container.listen(telemetryHistoryProvider('cpu'), (_, __) {});
      final notifier = container.read(telemetryHistoryProvider('cpu').notifier);

      notifier.setMinutes(30);

      await Future.delayed(Duration.zero);

      final state = container.read(telemetryHistoryProvider('cpu'));
      expect(state.minutes, 30);
      expect(state.isLoading, false);
      expect(state.response, mockResponse);
      verify(() => mockApiService.fetchTelemetryHistory('cpu', 30)).called(1);
    });
  });
}

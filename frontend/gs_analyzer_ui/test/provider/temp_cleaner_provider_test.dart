import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

// Since ApiService is constructed internally in TempCleanerNotifier,
// and the app's current test pattern doesn't mock internal ApiService instantiations easily
// without DI, we can't easily mock ApiService here without changing the provider's implementation.
// However, looking at the project, the providers don't use DI for ApiService.
// I will adjust the test to just test the state manipulations and not the actual fetch.

void main() {
  group('TempCleanerNotifier state manipulations', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state has no preview and isLoading false', () {
      final state = container.read(tempCleanerProvider);
      expect(state.isLoading, isFalse);
      expect(state.preview, isNull);
      expect(state.selectedPaths, isEmpty);
      expect(state.cleanResult, isNull);
      expect(state.errorMessage, isNull);
    });

    test('togglePath adds and removes a path', () {
      final notifier = container.read(tempCleanerProvider.notifier);

      notifier.togglePath('C:\\temp');
      expect(
        container.read(tempCleanerProvider).selectedPaths,
        contains('C:\\temp'),
      );

      notifier.togglePath('C:\\temp');
      expect(
        container.read(tempCleanerProvider).selectedPaths,
        isNot(contains('C:\\temp')),
      );
    });

    test('reset clears all state', () {
      final notifier = container.read(tempCleanerProvider.notifier);

      notifier.togglePath('C:\\temp');
      expect(container.read(tempCleanerProvider).selectedPaths, isNotEmpty);

      notifier.reset();

      final state = container.read(tempCleanerProvider);
      expect(state.isLoading, isFalse);
      expect(state.preview, isNull);
      expect(state.selectedPaths, isEmpty);
      expect(state.cleanResult, isNull);
      expect(state.errorMessage, isNull);
    });

    test('cleanSelected immediately updates preview and resets selection to remaining', () async {
      int getCount = 0;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.endsWith('/api/tempfiles/preview')) {
          getCount++;
          if (getCount == 1) {
            // Initial preview before clean: 1.3 GB
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'totalBytes': 1300000000,
                  'totalFormatted': '1.3 GB',
                  'locations': [
                    {
                      'path': 'C:\\temp',
                      'label': 'User temp',
                      'category': 'Temp',
                      'sizeBytes': 1300000000,
                      'sizeFormatted': '1.3 GB',
                      'fileCount': 100,
                    }
                  ],
                },
              }),
              200,
            );
          } else {
            // Post-clean preview: 0 B remaining
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'totalBytes': 0,
                  'totalFormatted': '0 B',
                  'locations': [],
                },
              }),
              200,
            );
          }
        } else if (req.method == 'POST' && req.url.path.endsWith('/api/tempfiles/clean')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'deletedFiles': 100,
                'freedBytes': 1300000000,
                'freedFormatted': '1.3 GB',
                'skippedFiles': 0,
              },
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final mockApi = ApiService(client);
      final notifier = TempCleanerNotifier(container.read(tempCleanerProvider.notifier).ref, mockApi);

      // 1. Initial preview
      await notifier.fetchPreview();
      expect(notifier.state.preview?.totalFormatted, '1.3 GB');
      expect(notifier.state.selectedPaths, contains('C:\\temp'));

      // 2. Execute clean
      await notifier.cleanSelected();

      // 3. Assert preview was automatically refreshed to post-clean result
      expect(notifier.state.cleanResult?.freedFormatted, '1.3 GB');
      expect(notifier.state.preview?.totalFormatted, '0 B');
      expect(notifier.state.selectedPaths, isEmpty);
    });
  });
}

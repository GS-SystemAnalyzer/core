import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';

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
  });
}

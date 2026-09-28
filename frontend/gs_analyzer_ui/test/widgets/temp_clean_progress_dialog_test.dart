import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/widgets/temp_clean_progress_dialog.dart';

void main() {
  testWidgets('TempCleanProgressDialog renders initial state and updates with progress', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        tempCleanProgressProvider.overrideWith((ref) => 0.0),
        tempCleanTargetProvider.overrideWith((ref) => 'User temp'),
        tempCleanCompletedProvider.overrideWith((ref) => 0),
        tempCleanTotalProvider.overrideWith((ref) => 21),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: TempCleanProgressDialog(),
          ),
        ),
      ),
    );

    // Initial assertions
    expect(find.text('PURGING TEMP SECTORS...'), findsOneWidget);
    expect(find.text('Target: User temp'), findsOneWidget);
    expect(find.text('Completed: 0 of 21'), findsOneWidget);
    expect(find.text('0.0%'), findsOneWidget);

    // Progress updates to 5 of 21 (23.8%)
    container.read(tempCleanCompletedProvider.notifier).state = 5;
    container.read(tempCleanProgressProvider.notifier).state = 23.8;
    container.read(tempCleanTargetProvider.notifier).state = 'Crash Dumps';
    await tester.pump();

    expect(find.text('Target: Crash Dumps'), findsOneWidget);
    expect(find.text('Completed: 5 of 21'), findsOneWidget);
    expect(find.text('23.8%'), findsOneWidget);
  });
}

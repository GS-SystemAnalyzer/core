import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/file_type_model.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/widgets/file_type_analyzer_panel.dart';

const _root = r'C:\';

FileTypeResult _mockResult() {
  return const FileTypeResult(
    root: _root,
    totalScannedFormatted: '27.2 GB',
    categories: [
      FileTypeCategory(
        name: 'other',
        totalBytes: 2147483648,
        sizeFormatted: '2.0 GB',
        fileCount: 21091,
        percentOfDisk: 7.4,
        extensions: [],
      ),
    ],
  );
}

void main() {
  testWidgets('FileTypeAnalyzerPanel renders refresh button and handles tap', (tester) async {
    final container = ProviderContainer(
      overrides: [
        fileTypesProvider(_root).overrideWith((ref) async => _mockResult()),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FileTypeAnalyzerPanel(driveName: _root),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify refresh button icon exists
    final refreshFinder = find.byIcon(Icons.refresh_rounded);
    expect(refreshFinder, findsOneWidget);

    // Initial refresh trigger count is 0
    expect(container.read(fileTypesRefreshTriggerProvider(_root)), 0);

    // Tap refresh button
    await tester.tap(refreshFinder);
    await tester.pump();

    // Verify refresh trigger count was incremented
    expect(container.read(fileTypesRefreshTriggerProvider(_root)), 1);
  });
}

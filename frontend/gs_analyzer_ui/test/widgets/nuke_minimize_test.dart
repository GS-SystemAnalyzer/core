import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/providers/minimized_ops_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/widgets/nuke_progress_dialog.dart';
import 'package:gs_analyzer_ui/widgets/nuke_preview_dialog.dart';

Widget _host(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const NukeProgressDialog(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('progress dialog minimise button sets the flag and pops', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(isNukeActiveProvider.notifier).state = true;

    await tester.pumpWidget(_host(container));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(NukeProgressDialog), findsOneWidget);
    expect(container.read(nukeMinimizedProvider), isFalse);

    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();

    // Minimised flag set; the modal route is gone (carried by the pill).
    expect(container.read(nukeMinimizedProvider), isTrue);
    expect(find.byType(NukeProgressDialog), findsNothing);
  });

  testWidgets('progress dialog self-closes when the nuke finishes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(isNukeActiveProvider.notifier).state = true;

    await tester.pumpWidget(_host(container));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(NukeProgressDialog), findsOneWidget);

    // Operation completes -> active flips false -> dialog pops itself.
    container.read(isNukeActiveProvider.notifier).state = false;
    await tester.pumpAndSettle();

    expect(find.byType(NukeProgressDialog), findsNothing);
  });

  testWidgets(
    'confirmation modal is non-dismissible by tapping outside (barrierDismissible:false)',
    (tester) async {
      // Mirrors the production call site nuke_protocol.dart:40.
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'totalBytes': 1000,
              'totalFormatted': '1 KB',
              'totalFiles': 2,
              'totalDirectories': 1,
              'planToken': 'plan-abc',
              'stagedPaths': ['C:\\temp\\x'],
              'errors': [],
            },
          }),
          200,
        );
      });
      final apiService = ApiService(client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => NukePreviewDialog(
                    targetPaths: const ['C:\\temp\\x'],
                    apiService: apiService,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(NukePreviewDialog), findsOneWidget);

      // Tap the barrier (top-left corner, well outside the dialog).
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Still present — outside taps must not dismiss a destructive confirm.
      expect(find.byType(NukePreviewDialog), findsOneWidget);
    },
  );
}

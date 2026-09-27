import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/providers/extension_breakdown_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/widgets/extension_breakdown_screen.dart';

const _root = r'C:\TestDrive';

ExtensionBreakdownItem _item(
  String ext,
  String category, {
  int fileCount = 1,
  int totalBytes = 1024,
}) {
  return ExtensionBreakdownItem(
    ext: ext,
    category: category,
    fileCount: fileCount,
    totalBytes: totalBytes,
    sizeFormatted: '1.0 KB',
    percentOfDisk: 50.0,
    averageFileSizeBytes: 1024,
    averageSizeFormatted: '1.0 KB',
    largestFilePath: '$_root\\big$ext',
    largestFileBytes: 1024,
    largestSizeFormatted: '1.0 KB',
  );
}

Widget _wrap(dynamic overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      home: ExtensionBreakdownScreen(scanRoot: _root, driveName: 'C:'),
    ),
  );
}

void main() {
  testWidgets('shows a spinner while the breakdown is loading', (tester) async {
    await tester.pumpWidget(
      _wrap([
        // A future that never completes keeps the provider in the loading state.
        extensionBreakdownProvider(
          _root,
        ).overrideWith((ref) => Completer<ExtensionBreakdownResult>().future),
      ]),
    );

    await tester
        .pump(); // single frame — do NOT pumpAndSettle (spinner animates forever)

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('RUN A SCAN FIRST'), findsNothing);
  });

  testWidgets('shows the no-scan view when the API reports no cached scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        extensionBreakdownProvider(_root).overrideWith(
          (ref) =>
              Future<ExtensionBreakdownResult>.error(FileTypeNoScanException()),
        ),
      ]),
    );

    await tester.pumpAndSettle();

    expect(find.text('RUN A SCAN FIRST'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders extension rows when data is available', (tester) async {
    final result = ExtensionBreakdownResult(
      root: _root,
      extensions: [
        _item('.mp4', 'media', fileCount: 2, totalBytes: 8000),
        _item('.txt', 'documents', fileCount: 3, totalBytes: 1500),
      ],
    );

    await tester.pumpWidget(
      _wrap([extensionBreakdownProvider(_root).overrideWith((ref) => result)]),
    );

    await tester.pumpAndSettle();

    expect(find.text('.mp4'), findsOneWidget);
    expect(find.text('.txt'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('RUN A SCAN FIRST'), findsNothing);
  });

  testWidgets('builds without rows when the breakdown is empty', (
    tester,
  ) async {
    final empty = ExtensionBreakdownResult(root: _root, extensions: const []);

    await tester.pumpWidget(
      _wrap([extensionBreakdownProvider(_root).overrideWith((ref) => empty)]),
    );

    await tester.pumpAndSettle();

    // No data rows, but the screen still renders its header.
    expect(find.text('.mp4'), findsNothing);
    expect(find.textContaining('EXTENSION_BREAKDOWN'), findsOneWidget);
  });
}

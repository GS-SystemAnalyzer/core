import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/widgets/export_scan_dialog.dart';

void main() {
  testWidgets('ExportScanDialog renders header, formats, and handles selection', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ExportScanDialog(driveName: 'C:\\'),
          ),
        ),
      ),
    );

    // Header checks
    expect(find.text('EXPORT SCAN REPORT'), findsOneWidget);
    expect(find.text('C:\\'), findsOneWidget);

    // Formats rendered
    expect(find.text('JSON'), findsOneWidget);
    expect(find.text('CSV'), findsOneWidget);
    expect(find.text('HTML'), findsOneWidget);

    // Checkbox rendered
    expect(find.text('REDACT USER PATHS'), findsOneWidget);

    // Tap CSV format
    await tester.tap(find.text('CSV'));
    await tester.pumpAndSettle();

    // Tap HTML format
    await tester.tap(find.text('HTML'));
    await tester.pumpAndSettle();

    // Toggle Redact Paths
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);
    await tester.tap(checkboxFinder);
    await tester.pumpAndSettle();

    // Checkbox is now true
    final checkboxWidget = tester.widget<Checkbox>(checkboxFinder);
    expect(checkboxWidget.value, true);

    // Buttons rendered
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('EXPORT'), findsOneWidget);
  });
}

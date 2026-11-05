import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_bar_chart.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_line_chart.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_load_report.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_summary_dialog.dart';
import 'package:gs_analyzer_ui/models/cpu_snapshot.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

class MockCpuNotifier extends StateNotifier<CpuState> implements CpuNotifier {
  MockCpuNotifier([CpuState state = const CpuState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CpuLoadReport Tests', () {
    final sampleSnapshot = CpuSnapshot(
      averageLoad: 42.5,
      delta: 1.8,
      currentFrequencyGhz: 3.6,
      totalProcesses: 195,
      totalThreads: 2500,
      totalHandles: 92000,
      l1Cache: '512 KB',
      l2Cache: '4 MB',
      l3Cache: '16 MB',
      coreGroups: {
        'C0': [35.0],
        'C1': [50.0],
      },
    );

    testWidgets('renders placeholder when snapshot is null', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cpuProvider.overrideWith((ref) => MockCpuNotifier(const CpuState(snapshot: null))),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: CpuLoadReport(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COLLECTING DATA — CHECK BACK IN A MOMENT'), findsOneWidget);
    });

    testWidgets('renders LineChart by default and displays average load %', (tester) async {
      final stateWithData = CpuState(
        snapshot: sampleSnapshot,
        history: [30.0, 38.0, 42.5],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cpuProvider.overrideWith((ref) => MockCpuNotifier(stateWithData)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: CpuLoadReport(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CPU LOAD [AVG]'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText && widget.text.toPlainText().contains('42.5'),
        ),
        findsOneWidget,
      );
      expect(find.text('LINE'), findsOneWidget);

      // Line chart is default
      expect(find.byType(CpuLineChart), findsOneWidget);
      expect(find.byType(CpuBarChart), findsNothing);
    });

    testWidgets('switches to BarChart using the dropdown selector', (tester) async {
      final stateWithData = CpuState(
        snapshot: sampleSnapshot,
        history: [30.0, 38.0, 42.5],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cpuProvider.overrideWith((ref) => MockCpuNotifier(stateWithData)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: CpuLoadReport(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify line chart is initially present
      expect(find.byType(CpuLineChart), findsOneWidget);
      expect(find.byType(CpuBarChart), findsNothing);

      // Tap dropdown to open popup menu
      await tester.tap(find.text('LINE'));
      await tester.pumpAndSettle();

      expect(find.text('LINE (TREND)'), findsOneWidget);
      expect(find.text('BAR (CORES)'), findsOneWidget);

      // Select BAR
      await tester.tap(find.text('BAR (CORES)'));
      await tester.pumpAndSettle();

      // Should now show BarChart
      expect(find.byType(CpuBarChart), findsOneWidget);
      expect(find.byType(CpuLineChart), findsNothing);
      expect(find.text('BAR'), findsOneWidget);
    });

    testWidgets('opens CpuSummaryDialog on right-click / secondary tap', (tester) async {
      final stateWithData = CpuState(
        snapshot: sampleSnapshot,
        history: [30.0, 38.0, 42.5],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cpuProvider.overrideWith((ref) => MockCpuNotifier(stateWithData)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: CpuLoadReport(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Right-click on the chart
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(CpuLineChart)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // Verify CpuSummaryDialog is shown
      expect(find.byType(CpuSummaryDialog), findsOneWidget);
      expect(find.text('CPU TELEMETRY SUMMARY'), findsOneWidget);
      expect(find.text('NORMAL STATUS'), findsOneWidget);
      expect(find.text('CURRENT LOAD'), findsOneWidget);
      expect(find.text('COPY METRICS'), findsOneWidget);
      expect(find.text('CLOSE'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('CLOSE'));
      await tester.pumpAndSettle();

      expect(find.byType(CpuSummaryDialog), findsNothing);
    });
  });
}

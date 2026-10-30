import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_line_chart.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

void main() {
  group('CpuLineChart Tests', () {
    final sampleHistory = [20.0, 45.0, 60.0];
    final highLoadHistory = [20.0, 45.0, 85.0];

    testWidgets('renders LineChart with correct spots and normal cyan color', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuLineChart(history: sampleHistory),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      expect(find.byType(CpuLineChart), findsOneWidget);

      final lineChart = tester.widget<LineChart>(find.byType(LineChart));
      final barData = lineChart.data.lineBarsData.first;
      expect(barData.spots.length, 3);
      expect(barData.spots[0].y, 20.0);
      expect(barData.spots[1].y, 45.0);
      expect(barData.spots[2].y, 60.0);

      // Latest spot is 60.0 (<= 80 -> accentCyan)
      expect(barData.color, HudColor.darkAccentCyan);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('switches line color to amber when latest load exceeds 80%', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuLineChart(history: highLoadHistory),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lineChart = tester.widget<LineChart>(find.byType(LineChart));
      final barData = lineChart.data.lineBarsData.first;

      // Latest spot is 85.0 (> 80 -> accentAmber)
      expect(barData.color, HudColor.darkAccentAmber);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts line and grid colors between Light and Dark themes', (tester) async {
      // 1. Light Theme
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuLineChart(history: sampleHistory),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightLineChart = tester.widget<LineChart>(find.byType(LineChart));
      expect(lightLineChart.data.lineBarsData.first.color, HudColor.lightAccentCyan);
      final lightGridLine = lightLineChart.data.gridData.getDrawingHorizontalLine(50);
      expect(lightGridLine.color, HudColor.lightTextMain.withValues(alpha: 0.12));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Theme
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuLineChart(history: sampleHistory),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkLineChart = tester.widget<LineChart>(find.byType(LineChart));
      expect(darkLineChart.data.lineBarsData.first.color, HudColor.darkAccentCyan);
      final darkGridLine = darkLineChart.data.gridData.getDrawingHorizontalLine(50);
      expect(darkGridLine.color, HudColor.darkTextMain.withValues(alpha: 0.12));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('handles empty and single-item history gracefully', (tester) async {
      // Empty history
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuLineChart(history: []),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // Single item history
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuLineChart(history: [75.0]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_bar_chart.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

void main() {
  group('CpuBarChart Tests', () {
    final sampleCoreGroups = {
      'C0': [50.0],
      'C1': [90.0],
    };

    testWidgets('renders BarChart with correct rods and values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuBarChart(coreGroups: sampleCoreGroups),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(CpuBarChart), findsOneWidget);

      final barChart = tester.widget<BarChart>(find.byType(BarChart));
      final barGroups = barChart.data.barGroups;
      expect(barGroups.length, 2);

      // C0 rod has load 50.0 (<= 80 -> accentCyan)
      expect(barGroups[0].barRods[0].toY, 50.0);
      expect(barGroups[0].barRods[0].color, HudColor.darkAccentCyan);

      // C1 rod has load 90.0 (> 80 -> accentAmber)
      expect(barGroups[1].barRods[0].toY, 90.0);
      expect(barGroups[1].barRods[0].color, HudColor.darkAccentAmber);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts rod colors and grid lines between Light and Dark themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuBarChart(coreGroups: sampleCoreGroups),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightBarChart = tester.widget<BarChart>(find.byType(BarChart));
      final lightRods = lightBarChart.data.barGroups;
      expect(lightRods[0].barRods[0].color, HudColor.lightAccentCyan);
      expect(lightRods[1].barRods[0].color, HudColor.lightAccentAmber);

      final lightGridLine = lightBarChart.data.gridData.getDrawingHorizontalLine(50);
      expect(lightGridLine.color, HudColor.lightTextMain.withValues(alpha: 0.12));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 200,
              child: CpuBarChart(coreGroups: sampleCoreGroups),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkBarChart = tester.widget<BarChart>(find.byType(BarChart));
      final darkRods = darkBarChart.data.barGroups;
      expect(darkRods[0].barRods[0].color, HudColor.darkAccentCyan);
      expect(darkRods[1].barRods[0].color, HudColor.darkAccentAmber);

      final darkGridLine = darkBarChart.data.gridData.getDrawingHorizontalLine(50);
      expect(darkGridLine.color, HudColor.darkTextMain.withValues(alpha: 0.12));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

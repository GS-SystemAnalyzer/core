import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/custom_progress_indicator.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';

void main() {
  group('CustomProgressIndicator Tests', () {
    testWidgets('renders labels and progress values correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: CustomProgressIndicator(
              label: 'cpu load',
              tag: 'normal',
              value: 0.45,
              height: 8.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CPU LOAD'), findsOneWidget);
      expect(find.text('NORMAL'), findsOneWidget);

      final indicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(indicator.value, 0.45);
      expect(indicator.minHeight, 8.0);
      expect(indicator.backgroundColor, HudColor.darkTextMuted);

      final tagText = tester.widget<Text>(find.text('NORMAL'));
      expect(tagText.style?.color, HudColor.darkAccentGreen);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts statGreen tag and textMuted background between themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: const Scaffold(
            body: CustomProgressIndicator(
              label: 'ram usage',
              tag: 'optimal',
              value: 0.60,
              height: 10.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(lightIndicator.backgroundColor, HudColor.lightTextMuted);

      final lightTagText = tester.widget<Text>(find.text('OPTIMAL'));
      expect(lightTagText.style?.color, HudColor.lightAccentGreen);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: CustomProgressIndicator(
              label: 'ram usage',
              tag: 'optimal',
              value: 0.60,
              height: 10.0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(darkIndicator.backgroundColor, HudColor.darkTextMuted);

      final darkTagText = tester.widget<Text>(find.text('OPTIMAL'));
      expect(darkTagText.style?.color, HudColor.darkAccentGreen);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

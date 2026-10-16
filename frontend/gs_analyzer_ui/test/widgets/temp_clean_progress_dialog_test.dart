import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
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

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  group('TempCleanProgressDialog Theme Adaptation Tests', () {
    testWidgets('adapts dialog panel, border, icon, and colors between themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tempCleanProgressProvider.overrideWith((ref) => 50.0),
            tempCleanTargetProvider.overrideWith((ref) => 'User temp'),
            tempCleanCompletedProvider.overrideWith((ref) => 5),
            tempCleanTotalProvider.overrideWith((ref) => 10),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: TempCleanProgressDialog(),
            ),
          ),
        ),
      );
      await tester.pump();

      final lightDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(lightDialog.backgroundColor, equals(HudColor.lightBgPanel));
      final lightShape = lightDialog.shape as RoundedRectangleBorder;
      expect(lightShape.side.color, equals(HudColor.lightAccentGreen));

      final lightIcon = tester.widget<Icon>(find.byIcon(Icons.cleaning_services_outlined));
      expect(lightIcon.color, equals(HudColor.lightAccentGreen));

      final lightTitle = tester.widget<Text>(find.text('PURGING TEMP SECTORS...'));
      expect(lightTitle.style?.color, equals(HudColor.lightAccentGreen));

      final lightPercent = tester.widget<Text>(find.text('50.0%'));
      expect(lightPercent.style?.color, equals(HudColor.lightAccentGreen));

      final lightIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(lightIndicator.color, equals(HudColor.lightAccentGreen));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tempCleanProgressProvider.overrideWith((ref) => 50.0),
            tempCleanTargetProvider.overrideWith((ref) => 'User temp'),
            tempCleanCompletedProvider.overrideWith((ref) => 5),
            tempCleanTotalProvider.overrideWith((ref) => 10),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: TempCleanProgressDialog(),
            ),
          ),
        ),
      );
      await tester.pump();

      final darkDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(darkDialog.backgroundColor, equals(HudColor.darkBgPanel));
      final darkShape = darkDialog.shape as RoundedRectangleBorder;
      expect(darkShape.side.color, equals(HudColor.darkAccentGreen));

      final darkIcon = tester.widget<Icon>(find.byIcon(Icons.cleaning_services_outlined));
      expect(darkIcon.color, equals(HudColor.darkAccentGreen));

      final darkTitle = tester.widget<Text>(find.text('PURGING TEMP SECTORS...'));
      expect(darkTitle.style?.color, equals(HudColor.darkAccentGreen));

      final darkPercent = tester.widget<Text>(find.text('50.0%'));
      expect(darkPercent.style?.color, equals(HudColor.darkAccentGreen));

      final darkIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(darkIndicator.color, equals(HudColor.darkAccentGreen));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

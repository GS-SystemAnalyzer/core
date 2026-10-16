import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/nuke_progress_dialog.dart';

void main() {
  group('NukeProgressDialog Tests', () {
    testWidgets('renders target, completed count, and progress percentage', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nukeTargetProvider.overrideWith((ref) => 'C:/Temp/target.iso'),
            nukeCompletedProvider.overrideWith((ref) => 4),
            nukeTotalProvider.overrideWith((ref) => 10),
            nukeProgressProvider.overrideWith((ref) => 40.0),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: NukeProgressDialog(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('NUKE IN PROGRESS...'), findsOneWidget);
      expect(find.text('Target: C:/Temp/target.iso'), findsOneWidget);
      expect(find.text('Completed: 4 of 10'), findsOneWidget);
      expect(find.text('40.0%'), findsOneWidget);
      expect(find.text('ABORT'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('adapts dialog panel background, accentRed border and colors between themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nukeTargetProvider.overrideWith((ref) => 'C:/Temp/target.iso'),
            nukeCompletedProvider.overrideWith((ref) => 5),
            nukeTotalProvider.overrideWith((ref) => 10),
            nukeProgressProvider.overrideWith((ref) => 50.0),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: NukeProgressDialog(),
            ),
          ),
        ),
      );
      await tester.pump();

      final lightDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(lightDialog.backgroundColor, equals(HudColor.lightBgPanel));
      final lightShape = lightDialog.shape as RoundedRectangleBorder;
      expect(lightShape.side.color, equals(HudColor.lightAccentRed));

      final lightTitle = tester.widget<Text>(find.text('NUKE IN PROGRESS...'));
      expect(lightTitle.style?.color, equals(HudColor.lightAccentRed));

      final lightIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(lightIndicator.color, equals(HudColor.lightAccentRed));

      final lightMinimizeIcon = tester.widget<Icon>(find.byIcon(Icons.remove));
      expect(lightMinimizeIcon.color, equals(HudColor.lightAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nukeTargetProvider.overrideWith((ref) => 'C:/Temp/target.iso'),
            nukeCompletedProvider.overrideWith((ref) => 5),
            nukeTotalProvider.overrideWith((ref) => 10),
            nukeProgressProvider.overrideWith((ref) => 50.0),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: NukeProgressDialog(),
            ),
          ),
        ),
      );
      await tester.pump();

      final darkDialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(darkDialog.backgroundColor, equals(HudColor.darkBgPanel));
      final darkShape = darkDialog.shape as RoundedRectangleBorder;
      expect(darkShape.side.color, equals(HudColor.darkAccentRed));

      final darkTitle = tester.widget<Text>(find.text('NUKE IN PROGRESS...'));
      expect(darkTitle.style?.color, equals(HudColor.darkAccentRed));

      final darkIndicator = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(darkIndicator.color, equals(HudColor.darkAccentRed));

      final darkMinimizeIcon = tester.widget<Icon>(find.byIcon(Icons.remove));
      expect(darkMinimizeIcon.color, equals(HudColor.darkAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

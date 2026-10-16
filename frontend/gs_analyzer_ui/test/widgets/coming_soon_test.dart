import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/coming_soon.dart';

void main() {
  group('ComingSoon Widget Tests', () {
    testWidgets('Renders locked overlay and adapts theme colors in Light and Dark mode', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: const Scaffold(
            body: ComingSoon(
              child: Text('UNLOCKED_CONTENT'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COMING SOON'), findsOneWidget);
      expect(find.text('THIS MODULE IS NOT AVAILABLE YET'), findsOneWidget);
      expect(find.text('UNLOCKED_CONTENT'), findsNothing);

      // Verify lock icon color in Light mode
      final lightLockIcon = tester.widget<Icon>(find.byIcon(Icons.lock));
      expect(lightLockIcon.color, equals(HudColor.lightTextMain));

      // Verify subtitle color
      final lightSubtitle = tester.widget<Text>(find.text('THIS MODULE IS NOT AVAILABLE YET'));
      expect(lightSubtitle.style?.color, equals(HudColor.lightTextMain.withValues(alpha: 0.6)));

      // Verify dummy background containers
      final lightHeaderContainer = tester.widget<Container>(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.minHeight == 40 &&
            w.constraints?.maxWidth == 250),
      );
      final lightHeaderDec = lightHeaderContainer.decoration as BoxDecoration;
      expect(lightHeaderDec.color, equals(HudColor.lightTextMain.withValues(alpha: 0.1)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: ComingSoon(
              child: Text('UNLOCKED_CONTENT'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COMING SOON'), findsOneWidget);
      expect(find.text('THIS MODULE IS NOT AVAILABLE YET'), findsOneWidget);
      expect(find.text('UNLOCKED_CONTENT'), findsNothing);

      // Verify lock icon color in Dark mode
      final darkLockIcon = tester.widget<Icon>(find.byIcon(Icons.lock));
      expect(darkLockIcon.color, equals(HudColor.darkTextMain));

      // Verify subtitle color
      final darkSubtitle = tester.widget<Text>(find.text('THIS MODULE IS NOT AVAILABLE YET'));
      expect(darkSubtitle.style?.color, equals(HudColor.darkTextMain.withValues(alpha: 0.6)));

      // Verify dummy background containers
      final darkHeaderContainer = tester.widget<Container>(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.minHeight == 40 &&
            w.constraints?.maxWidth == 250),
      );
      final darkHeaderDec = darkHeaderContainer.decoration as BoxDecoration;
      expect(darkHeaderDec.color, equals(HudColor.darkTextMain.withValues(alpha: 0.1)));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('Double-tapping lock icon unlocks and displays child content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: ComingSoon(
              child: Text('UNLOCKED_CONTENT'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('UNLOCKED_CONTENT'), findsNothing);
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // Double tap lock icon
      await tester.tap(find.byIcon(Icons.lock));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byIcon(Icons.lock));
      await tester.pumpAndSettle();

      // Should now be unlocked
      expect(find.text('UNLOCKED_CONTENT'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.text('COMING SOON'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

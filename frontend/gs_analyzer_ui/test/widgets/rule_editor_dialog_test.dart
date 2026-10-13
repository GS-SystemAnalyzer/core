import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/rule_editor_dialog.dart';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1280, 800);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  group('RuleEditorDialog Tests', () {
    testWidgets('renders new rule editor header, steps, and step 0 fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: RuleEditorDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NEW_AUTOMATION_RULE'), findsOneWidget);
      expect(find.text('ROOT'), findsOneWidget);
      expect(find.text('CRITERIA'), findsOneWidget);
      expect(find.text('SCHEDULE'), findsOneWidget);
      expect(find.text('DRY_RUN'), findsOneWidget);
      expect(find.text('ARM'), findsOneWidget);

      expect(find.text('RULE NAME'), findsOneWidget);
      expect(find.text('CLEANUP ROOT PATH'), findsOneWidget);
      expect(find.text('NEXT'), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('navigates through steps and allows going back', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: RuleEditorDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 0 -> Step 1 (CRITERIA)
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
      expect(find.text('OLDER THAN (DAYS)'), findsOneWidget);
      expect(find.text('BACK'), findsOneWidget);

      // Step 1 -> Step 2 (SCHEDULE)
      await tester.tap(find.text('NEXT'));
      await tester.pumpAndSettle();
      expect(find.text('RUN FREQUENCY'), findsOneWidget);

      // Step 2 -> Back to Step 1
      await tester.tap(find.text('BACK'));
      await tester.pumpAndSettle();
      expect(find.text('OLDER THAN (DAYS)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('renders existing rule with EDIT_AUTOMATION_RULE title', (tester) async {
      final existing = AutomationRule(
        id: 'rule-1',
        name: 'CUSTOM CLEAN',
        isEnabled: true,
        isArmed: true,
        root: 'C:/Temp',
        criteria: RuleCriteria(olderThanDays: 14),
        schedule: ScheduleSpec(
          kind: AutomationScheduleKind.weekly,
          timeOfDay: '04:00',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: Scaffold(
            body: RuleEditorDialog(existingRule: existing),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('EDIT_AUTOMATION_RULE'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('adapts dialog styling and colors between Light and Dark themes', (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: const Scaffold(
            body: RuleEditorDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightDialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(lightDialog.backgroundColor, equals(HudColor.lightBgPanel));
      final lightShape = lightDialog.shape as RoundedRectangleBorder;
      expect(lightShape.side.color, equals(HudColor.lightPrimaryBorder.withValues(alpha: 0.5)));

      final lightHeaderIcon = tester.widget<Icon>(find.byIcon(Icons.security));
      expect(lightHeaderIcon.color, equals(HudColor.lightAccentCyan));

      final lightHeaderText = tester.widget<Text>(find.text('NEW_AUTOMATION_RULE'));
      expect(lightHeaderText.style?.color, equals(HudColor.lightAccentCyan));

      final lightNextText = tester.widget<Text>(find.text('NEXT'));
      expect(lightNextText.style?.color, equals(HudColor.lightAccentCyan));

      final lightCancelText = tester.widget<Text>(find.text('CANCEL'));
      expect(lightCancelText.style?.color, equals(HudColor.lightTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // 2. Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: RuleEditorDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkDialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(darkDialog.backgroundColor, equals(HudColor.darkBgPanel));
      final darkShape = darkDialog.shape as RoundedRectangleBorder;
      expect(darkShape.side.color, equals(HudColor.darkPrimaryBorder.withValues(alpha: 0.5)));

      final darkHeaderIcon = tester.widget<Icon>(find.byIcon(Icons.security));
      expect(darkHeaderIcon.color, equals(HudColor.darkAccentCyan));

      final darkHeaderText = tester.widget<Text>(find.text('NEW_AUTOMATION_RULE'));
      expect(darkHeaderText.style?.color, equals(HudColor.darkAccentCyan));

      final darkNextText = tester.widget<Text>(find.text('NEXT'));
      expect(darkNextText.style?.color, equals(HudColor.darkAccentCyan));

      final darkCancelText = tester.widget<Text>(find.text('CANCEL'));
      expect(darkCancelText.style?.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}

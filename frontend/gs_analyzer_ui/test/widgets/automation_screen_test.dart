import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/providers/automation_provider.dart';
import 'package:gs_analyzer_ui/screen/automation_screen.dart';
import 'package:gs_analyzer_ui/widgets/rule_editor_dialog.dart';

void main() {
  testWidgets('AutomationScreen renders header, panels, and empty states', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          automationRulesProvider.overrideWith(() => MockEmptyRulesNotifier()),
          automationAuditProvider.overrideWith((ref) async => <AutomationAuditEntry>[]),
        ],
        child: const MaterialApp(
          home: AutomationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AUTOMATION PROTOCOL'), findsOneWidget);
    expect(find.text('RULES'), findsOneWidget);
    expect(find.text('AUDIT LOG'), findsOneWidget);
    expect(find.text('NO AUTOMATION RULES CONFIGURED — CLICK + NEW RULE TO ADD ONE'), findsOneWidget);
    expect(find.text('NO AUDIT ENTRIES RECORDED'), findsOneWidget);
  });

  testWidgets('AutomationScreen displays rule with un-armed amber badge', (tester) async {
    final testRule = AutomationRule(
      id: 'rule-1',
      name: 'TEMP CLEANUP',
      isEnabled: true,
      isArmed: false,
      root: 'C:\\Temp',
      criteria: RuleCriteria(olderThanDays: 7, recurseSubdirectories: true),
      schedule: ScheduleSpec(kind: AutomationScheduleKind.daily),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          automationRulesProvider.overrideWith(() => MockSingleRuleNotifier(testRule)),
          automationAuditProvider.overrideWith((ref) async => <AutomationAuditEntry>[]),
        ],
        child: const MaterialApp(
          home: AutomationScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('TEMP CLEANUP'), findsOneWidget);
    expect(find.text('NOT ARMED — REVIEW DRY RUN'), findsOneWidget);
  });

  testWidgets('RuleEditorDialog renders steps and navigation', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: RuleEditorDialog(),
          ),
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
    expect(find.text('NEXT'), findsOneWidget);
  });
}

class MockEmptyRulesNotifier extends AutomationRulesNotifier {
  @override
  Future<List<AutomationRule>> build() async => [];
}

class MockSingleRuleNotifier extends AutomationRulesNotifier {
  final AutomationRule rule;
  MockSingleRuleNotifier(this.rule);

  @override
  Future<List<AutomationRule>> build() async => [rule];
}

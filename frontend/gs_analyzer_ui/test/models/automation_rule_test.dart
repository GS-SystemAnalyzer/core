import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';

void main() {
  group('AutomationRule model tests', () {
    test('Roundtrip serialization of AutomationRule', () {
      final rule = AutomationRule(
        id: 'rule-123',
        name: 'TEMP CLEANUP',
        isEnabled: true,
        isArmed: false,
        root: 'C:\\Temp',
        criteria: RuleCriteria(
          olderThanDays: 7,
          largerThanBytes: 1048576,
          extensionAllowlist: ['.tmp', '.log'],
          pathContainsAny: ['cache'],
          recurseSubdirectories: true,
        ),
        schedule: ScheduleSpec(
          kind: AutomationScheduleKind.daily,
          timeOfDay: '03:00:00',
        ),
        lastRunUtc: DateTime.utc(2026, 8, 9, 3, 0),
        nextRunUtc: DateTime.utc(2026, 8, 10, 3, 0),
      );

      final json = rule.toJson();
      final fromJson = AutomationRule.fromJson(json);

      expect(fromJson.id, 'rule-123');
      expect(fromJson.name, 'TEMP CLEANUP');
      expect(fromJson.isArmed, false);
      expect(fromJson.isEnabled, true);
      expect(fromJson.root, 'C:\\Temp');
      expect(fromJson.criteria.olderThanDays, 7);
      expect(fromJson.criteria.extensionAllowlist, ['.tmp', '.log']);
      expect(fromJson.schedule.kind, AutomationScheduleKind.daily);
      expect(fromJson.schedule.timeOfDay, '03:00:00');
    });

    test('Roundtrip serialization of AutomationAuditEntry', () {
      final entry = AutomationAuditEntry(
        id: 'audit-999',
        ruleId: 'rule-123',
        ruleName: 'TEMP CLEANUP',
        startedUtc: DateTime.utc(2026, 8, 9, 3, 0),
        finishedUtc: DateTime.utc(2026, 8, 9, 3, 1),
        matchedCount: 4180,
        deletedCount: 4180,
        bytesFreed: 1800000000,
        skippedCount: 0,
        isDryRun: false,
        wasAborted: false,
        abortReason: null,
      );

      final json = {
        'id': entry.id,
        'ruleId': entry.ruleId,
        'ruleName': entry.ruleName,
        'startedUtc': entry.startedUtc.toIso8601String(),
        'finishedUtc': entry.finishedUtc.toIso8601String(),
        'matchedCount': entry.matchedCount,
        'deletedCount': entry.deletedCount,
        'bytesFreed': entry.bytesFreed,
        'skippedCount': entry.skippedCount,
        'isDryRun': entry.isDryRun,
        'wasAborted': entry.wasAborted,
        'abortReason': entry.abortReason,
      };

      final fromJson = AutomationAuditEntry.fromJson(json);
      expect(fromJson.id, 'audit-999');
      expect(fromJson.matchedCount, 4180);
      expect(fromJson.deletedCount, 4180);
      expect(fromJson.wasAborted, false);
    });
  });
}

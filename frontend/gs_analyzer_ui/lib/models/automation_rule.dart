enum AutomationScheduleKind {
  daily,
  weekly,
  onAppStart,
  intervalHours;

  static AutomationScheduleKind fromString(String val) {
    switch (val.toLowerCase()) {
      case 'daily':
        return AutomationScheduleKind.daily;
      case 'weekly':
        return AutomationScheduleKind.weekly;
      case 'onappstart':
        return AutomationScheduleKind.onAppStart;
      case 'intervalhours':
      default:
        return AutomationScheduleKind.intervalHours;
    }
  }

  String toSerializedString() {
    switch (this) {
      case AutomationScheduleKind.daily:
        return 'Daily';
      case AutomationScheduleKind.weekly:
        return 'Weekly';
      case AutomationScheduleKind.onAppStart:
        return 'OnAppStart';
      case AutomationScheduleKind.intervalHours:
        return 'IntervalHours';
    }
  }
}

class RuleCriteria {
  final int? olderThanDays;
  final int? largerThanBytes;
  final List<String>? extensionAllowlist;
  final List<String>? pathContainsAny;
  final bool recurseSubdirectories;

  RuleCriteria({
    this.olderThanDays,
    this.largerThanBytes,
    this.extensionAllowlist,
    this.pathContainsAny,
    this.recurseSubdirectories = true,
  });

  factory RuleCriteria.fromJson(Map<String, dynamic> json) {
    return RuleCriteria(
      olderThanDays: json['olderThanDays'],
      largerThanBytes: json['largerThanBytes'],
      extensionAllowlist: json['extensionAllowlist'] != null
          ? List<String>.from(json['extensionAllowlist'])
          : null,
      pathContainsAny: json['pathContainsAny'] != null
          ? List<String>.from(json['pathContainsAny'])
          : null,
      recurseSubdirectories: json['recurseSubdirectories'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'olderThanDays': olderThanDays,
      'largerThanBytes': largerThanBytes,
      'extensionAllowlist': extensionAllowlist,
      'pathContainsAny': pathContainsAny,
      'recurseSubdirectories': recurseSubdirectories,
    };
  }
}

class ScheduleSpec {
  final AutomationScheduleKind kind;
  final int? intervalHours;
  final String? timeOfDay;
  final int? dayOfWeek;

  ScheduleSpec({
    required this.kind,
    this.intervalHours,
    this.timeOfDay,
    this.dayOfWeek,
  });

  factory ScheduleSpec.fromJson(Map<String, dynamic> json) {
    return ScheduleSpec(
      kind: AutomationScheduleKind.fromString(json['kind']?.toString() ?? 'IntervalHours'),
      intervalHours: json['intervalHours'],
      timeOfDay: json['timeOfDay']?.toString(),
      dayOfWeek: json['dayOfWeek'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind.toSerializedString(),
      'intervalHours': intervalHours,
      'timeOfDay': timeOfDay,
      'dayOfWeek': dayOfWeek,
    };
  }
}

class AutomationRule {
  final String id;
  final String name;
  final bool isEnabled;
  final bool isArmed;
  final String root;
  final RuleCriteria criteria;
  final ScheduleSpec schedule;
  final DateTime? lastRunUtc;
  final DateTime? nextRunUtc;

  AutomationRule({
    required this.id,
    required this.name,
    required this.isEnabled,
    required this.isArmed,
    required this.root,
    required this.criteria,
    required this.schedule,
    this.lastRunUtc,
    this.nextRunUtc,
  });

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    return AutomationRule(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isEnabled: json['isEnabled'] ?? true,
      isArmed: json['isArmed'] ?? false,
      root: json['root'] ?? '',
      criteria: RuleCriteria.fromJson(json['criteria'] ?? {}),
      schedule: ScheduleSpec.fromJson(json['schedule'] ?? {}),
      lastRunUtc: json['lastRunUtc'] != null ? DateTime.tryParse(json['lastRunUtc']) : null,
      nextRunUtc: json['nextRunUtc'] != null ? DateTime.tryParse(json['nextRunUtc']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isEnabled': isEnabled,
      'isArmed': isArmed,
      'root': root,
      'criteria': criteria.toJson(),
      'schedule': schedule.toJson(),
      'lastRunUtc': lastRunUtc?.toIso8601String(),
      'nextRunUtc': nextRunUtc?.toIso8601String(),
    };
  }

  AutomationRule copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    bool? isArmed,
    String? root,
    RuleCriteria? criteria,
    ScheduleSpec? schedule,
    DateTime? lastRunUtc,
    DateTime? nextRunUtc,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      isArmed: isArmed ?? this.isArmed,
      root: root ?? this.root,
      criteria: criteria ?? this.criteria,
      schedule: schedule ?? this.schedule,
      lastRunUtc: lastRunUtc ?? this.lastRunUtc,
      nextRunUtc: nextRunUtc ?? this.nextRunUtc,
    );
  }
}

class AutomationAuditEntry {
  final String id;
  final String ruleId;
  final String ruleName;
  final DateTime startedUtc;
  final DateTime finishedUtc;
  final int matchedCount;
  final int deletedCount;
  final int bytesFreed;
  final int skippedCount;
  final bool isDryRun;
  final bool wasAborted;
  final String? abortReason;

  AutomationAuditEntry({
    required this.id,
    required this.ruleId,
    required this.ruleName,
    required this.startedUtc,
    required this.finishedUtc,
    required this.matchedCount,
    required this.deletedCount,
    required this.bytesFreed,
    required this.skippedCount,
    required this.isDryRun,
    required this.wasAborted,
    this.abortReason,
  });

  factory AutomationAuditEntry.fromJson(Map<String, dynamic> json) {
    return AutomationAuditEntry(
      id: json['id'] ?? '',
      ruleId: json['ruleId'] ?? '',
      ruleName: json['ruleName'] ?? 'Rule',
      startedUtc: DateTime.tryParse(json['startedUtc'] ?? '') ?? DateTime.now(),
      finishedUtc: DateTime.tryParse(json['finishedUtc'] ?? '') ?? DateTime.now(),
      matchedCount: json['matchedCount'] ?? 0,
      deletedCount: json['deletedCount'] ?? 0,
      bytesFreed: (json['bytesFreed'] as num?)?.toInt() ?? 0,
      skippedCount: json['skippedCount'] ?? 0,
      isDryRun: json['isDryRun'] ?? false,
      wasAborted: json['wasAborted'] ?? false,
      abortReason: json['abortReason'],
    );
  }
}

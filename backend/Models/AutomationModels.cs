using System;
using System.Text.Json.Serialization;

namespace GSSystemAnalyzer.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum AutomationScheduleKind
{
	Daily,
	Weekly,
	OnAppStart,
	IntervalHours
}

public record AutomationRule(
	string Id,
	string Name,
	bool IsEnabled,
	bool IsArmed,
	string Root,
	RuleCriteria Criteria,
	ScheduleSpec Schedule,
	DateTimeOffset? LastRunUtc,
	DateTimeOffset? NextRunUtc);

public record RuleCriteria(
	int? OlderThanDays,
	long? LargerThanBytes,
	string[]? ExtensionAllowlist,
	string[]? PathContainsAny,
	bool RecurseSubdirectories);

public record ScheduleSpec(
	AutomationScheduleKind Kind,
	int? IntervalHours,
	TimeOnly? TimeOfDay,
	DayOfWeek? DayOfWeek);

public record AutomationAuditEntry(
	string Id,
	string RuleId,
	string RuleName,
	DateTimeOffset StartedUtc,
	DateTimeOffset FinishedUtc,
	int MatchedCount,
	int DeletedCount,
	long BytesFreed,
	int SkippedCount,
	bool IsDryRun,
	bool WasAborted,
	string? AbortReason);

public record CreateAutomationRuleRequest(
	string Name,
	bool IsEnabled,
	string Root,
	RuleCriteria Criteria,
	ScheduleSpec Schedule);

public record UpdateAutomationRuleRequest(
	string Name,
	bool IsEnabled,
	string Root,
	RuleCriteria Criteria,
	ScheduleSpec Schedule);

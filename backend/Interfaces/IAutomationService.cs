using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IAutomationService
{
	List<AutomationRule> GetRules();
	AutomationRule? GetRule(string id);
	AutomationRule CreateRule(CreateAutomationRuleRequest request);
	AutomationRule UpdateRule(string id, UpdateAutomationRuleRequest request);
	bool DeleteRule(string id);
	Task<NukePreviewResponse> DryRunRuleAsync(string id, CancellationToken ct = default);
	AutomationRule ArmRule(string id);
	Task<AutomationAuditEntry?> ExecuteRuleAsync(string id, bool isManualTrigger = false, CancellationToken ct = default);
	List<AutomationRule> GetDueRules(DateTimeOffset now);
	DateTimeOffset CalculateNextRun(ScheduleSpec schedule, DateTimeOffset fromUtc);
	void ValidateRuleRoot(string root);
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

public class AutomationService : IAutomationService
{
	private readonly IAutomationRuleStore _ruleStore;
	private readonly IAutomationAuditService _auditService;
	private readonly INukeProtocolService _nukeService;
	private readonly IDiskScannerEngine _scanner;
	private readonly ISettingService _settings;
	private readonly IHubContext<SystemHub> _hubContext;
	private readonly ILogger<AutomationService> _logger;

	private readonly SemaphoreSlim _executionLock = new(1, 1);
	private readonly object _rulesLock = new();

	// Default safety caps per techspec-v2.md:4273
	public int MaxFilesPerRun { get; set; } = 5000;
	public long MaxBytesPerRun { get; set; } = 10L * 1024 * 1024 * 1024; // 10 GB

	private static readonly HashSet<string> ProjectCacheAllowlist = new(StringComparer.OrdinalIgnoreCase)
	{
		".next", "node_modules", ".turbo", ".parcel-cache",
		".nuxt", ".svelte-kit", ".angular", ".vite",
		".gradle", ".dart_tool", "__pycache__", ".pytest_cache",
		"target", "dist", "build", ".output"
	};

	public AutomationService(
		IAutomationRuleStore ruleStore,
		IAutomationAuditService auditService,
		INukeProtocolService nukeService,
		IDiskScannerEngine scanner,
		ISettingService settings,
		IHubContext<SystemHub> hubContext,
		ILogger<AutomationService> logger)
	{
		_ruleStore = ruleStore;
		_auditService = auditService;
		_nukeService = nukeService;
		_scanner = scanner;
		_settings = settings;
		_hubContext = hubContext;
		_logger = logger;
	}

	public List<AutomationRule> GetRules()
	{
		lock (_rulesLock)
		{
			return _ruleStore.LoadAll();
		}
	}

	public AutomationRule? GetRule(string id)
	{
		lock (_rulesLock)
		{
			return _ruleStore.LoadAll().FirstOrDefault(r => r.Id == id);
		}
	}

	public AutomationRule CreateRule(CreateAutomationRuleRequest request)
	{
		ValidateRuleRoot(request.Root);

		var now = DateTimeOffset.UtcNow;
		var nextRun = CalculateNextRun(request.Schedule, now);

		var rule = new AutomationRule(
			Id: $"rule-{Guid.NewGuid():N}",
			Name: string.IsNullOrWhiteSpace(request.Name) ? "Automated Rule" : request.Name.Trim(),
			IsEnabled: request.IsEnabled,
			IsArmed: false, // Mandatory: first run of any new rule is dry run only until armed
			Root: Path.GetFullPath(request.Root),
			Criteria: request.Criteria,
			Schedule: request.Schedule,
			LastRunUtc: null,
			NextRunUtc: nextRun
		);

		lock (_rulesLock)
		{
			var rules = _ruleStore.LoadAll();
			rules.Add(rule);
			_ruleStore.SaveAll(rules);
		}

		_logger.LogInformation("Created automation rule {RuleId} ({RuleName}) for root {Root}", rule.Id, rule.Name, rule.Root);
		return rule;
	}

	public AutomationRule UpdateRule(string id, UpdateAutomationRuleRequest request)
	{
		ValidateRuleRoot(request.Root);

		lock (_rulesLock)
		{
			var rules = _ruleStore.LoadAll();
			var index = rules.FindIndex(r => r.Id == id);
			if (index < 0)
			{
				throw new KeyNotFoundException($"Rule with ID '{id}' not found.");
			}

			var existing = rules[index];
			var now = DateTimeOffset.UtcNow;
			var nextRun = CalculateNextRun(request.Schedule, now);

			// If root or criteria changed, disarm the rule to enforce preview verification
			bool rootOrCriteriaChanged = !string.Equals(existing.Root, Path.GetFullPath(request.Root), StringComparison.OrdinalIgnoreCase) ||
			                             existing.Criteria != request.Criteria;

			var updated = existing with
			{
				Name = string.IsNullOrWhiteSpace(request.Name) ? existing.Name : request.Name.Trim(),
				IsEnabled = request.IsEnabled,
				IsArmed = rootOrCriteriaChanged ? false : existing.IsArmed,
				Root = Path.GetFullPath(request.Root),
				Criteria = request.Criteria,
				Schedule = request.Schedule,
				NextRunUtc = nextRun
			};

			rules[index] = updated;
			_ruleStore.SaveAll(rules);
			return updated;
		}
	}

	public bool DeleteRule(string id)
	{
		lock (_rulesLock)
		{
			var rules = _ruleStore.LoadAll();
			var removedCount = rules.RemoveAll(r => r.Id == id);
			if (removedCount > 0)
			{
				_ruleStore.SaveAll(rules);
				_logger.LogInformation("Deleted automation rule {RuleId}", id);
				return true;
			}
			return false;
		}
	}

	public async Task<NukePreviewResponse> DryRunRuleAsync(string id, CancellationToken ct = default)
	{
		var rule = GetRule(id);
		if (rule == null)
		{
			throw new KeyNotFoundException($"Rule '{id}' not found.");
		}

		var startedUtc = DateTimeOffset.UtcNow;
		var candidates = FindMatchingFiles(rule);
		var preview = await _nukeService.PreviewNukeAsync(candidates, ct);
		var finishedUtc = DateTimeOffset.UtcNow;

		// Record audit entry for the dry run
		var auditEntry = new AutomationAuditEntry(
			Id: $"audit-{Guid.NewGuid():N}",
			RuleId: rule.Id,
			RuleName: rule.Name,
			StartedUtc: startedUtc,
			FinishedUtc: finishedUtc,
			MatchedCount: preview.TotalFiles,
			DeletedCount: 0,
			BytesFreed: 0,
			SkippedCount: 0,
			IsDryRun: true,
			WasAborted: false,
			AbortReason: null
		);

		await _auditService.AppendEntryAsync(auditEntry);

		await _hubContext.Clients.All.SendAsync("AutomationRunComplete", new
		{
			ruleId = rule.Id,
			ruleName = rule.Name,
			completedAtUtc = finishedUtc,
			filesDeleted = 0,
			bytesFreed = preview.TotalBytes,
			isDryRun = true
		}, ct);

		return preview;
	}

	public AutomationRule ArmRule(string id)
	{
		lock (_rulesLock)
		{
			var rules = _ruleStore.LoadAll();
			var index = rules.FindIndex(r => r.Id == id);
			if (index < 0)
			{
				throw new KeyNotFoundException($"Rule '{id}' not found.");
			}

			var armed = rules[index] with { IsArmed = true };
			rules[index] = armed;
			_ruleStore.SaveAll(rules);

			_logger.LogInformation("Automation rule {RuleId} has been ARMED by user review", id);
			return armed;
		}
	}

	public async Task<AutomationAuditEntry?> ExecuteRuleAsync(string id, bool isManualTrigger = false, CancellationToken ct = default)
	{
		var rule = GetRule(id);
		if (rule == null) return null;

		// Un-armed rules never execute unattended
		if (!isManualTrigger && !rule.IsArmed)
		{
			_logger.LogWarning("Skipping execution for rule {RuleId} ({RuleName}) — rule is NOT ARMED", rule.Id, rule.Name);
			return null;
		}

		// Overlap guard: never run while a scan or manual nuke is active
		if (_scanner.IsScanning || _nukeService.IsNuking)
		{
			_logger.LogInformation("Skipping automation rule {RuleId} due to active scan or nuke in progress", rule.Id);
			return null;
		}

		// Enforce single-threaded rule execution
		if (!await _executionLock.WaitAsync(0, ct))
		{
			_logger.LogInformation("Another automation rule is currently executing; skipping this tick for rule {RuleId}", rule.Id);
			return null;
		}

		var startedUtc = DateTimeOffset.UtcNow;
		await _hubContext.Clients.All.SendAsync("AutomationRunStarted", new
		{
			ruleId = rule.Id,
			ruleName = rule.Name,
			startedAtUtc = startedUtc
		}, ct);

		try
		{
			var candidatePaths = FindMatchingFiles(rule);

			// Always dry-run preview first
			var preview = await _nukeService.PreviewNukeAsync(candidatePaths, ct);

			// Check safety caps
			if (preview.TotalFiles > MaxFilesPerRun || preview.TotalBytes > MaxBytesPerRun)
			{
				_logger.LogWarning("Automation rule {RuleId} aborted: cap exceeded (Files: {Files}/{MaxFiles}, Bytes: {Bytes}/{MaxBytes})",
					rule.Id, preview.TotalFiles, MaxFilesPerRun, preview.TotalBytes, MaxBytesPerRun);

				var abortedEntry = new AutomationAuditEntry(
					Id: $"audit-{Guid.NewGuid():N}",
					RuleId: rule.Id,
					RuleName: rule.Name,
					StartedUtc: startedUtc,
					FinishedUtc: DateTimeOffset.UtcNow,
					MatchedCount: preview.TotalFiles,
					DeletedCount: 0,
					BytesFreed: 0,
					SkippedCount: 0,
					IsDryRun: false,
					WasAborted: true,
					AbortReason: "CAP_EXCEEDED"
				);

				await _auditService.AppendEntryAsync(abortedEntry);

				await _hubContext.Clients.All.SendAsync("AutomationRunAborted", new
				{
					ruleId = rule.Id,
					ruleName = rule.Name,
					abortedAtUtc = abortedEntry.FinishedUtc,
					reason = "CAP_EXCEEDED"
				}, ct);

				UpdateRuleScheduleOnFinish(rule.Id, startedUtc);
				return abortedEntry;
			}

			// Mandatory recycle bin execution
			NukeResultDto result;
			if (candidatePaths.Count > 0)
			{
				result = await _nukeService.ObliterateNodeAsync(candidatePaths, preview.PlanToken, useRecycleBin: true, cancellationToken: ct);
			}
			else
			{
				result = new NukeResultDto
				{
					DeletedFiles = 0,
					FreedBytes = 0,
					SkippedFiles = 0,
					RecycleBinUsed = true
				};
			}

			var finishedUtc = DateTimeOffset.UtcNow;
			var auditEntry = new AutomationAuditEntry(
				Id: $"audit-{Guid.NewGuid():N}",
				RuleId: rule.Id,
				RuleName: rule.Name,
				StartedUtc: startedUtc,
				FinishedUtc: finishedUtc,
				MatchedCount: preview.TotalFiles,
				DeletedCount: result.DeletedFiles,
				BytesFreed: result.FreedBytes,
				SkippedCount: result.SkippedFiles,
				IsDryRun: false,
				WasAborted: false,
				AbortReason: null
			);

			await _auditService.AppendEntryAsync(auditEntry);

			await _hubContext.Clients.All.SendAsync("AutomationRunComplete", new
			{
				ruleId = rule.Id,
				ruleName = rule.Name,
				completedAtUtc = finishedUtc,
				filesDeleted = result.DeletedFiles,
				bytesFreed = result.FreedBytes,
				isDryRun = false
			}, ct);

			UpdateRuleScheduleOnFinish(rule.Id, startedUtc);
			return auditEntry;
		}
		finally
		{
			_executionLock.Release();
		}
	}

	public List<AutomationRule> GetDueRules(DateTimeOffset now)
	{
		lock (_rulesLock)
		{
			var rules = _ruleStore.LoadAll();
			return rules
				.Where(r => r.IsEnabled && r.NextRunUtc.HasValue && r.NextRunUtc.Value <= now)
				.ToList();
		}
	}

	public DateTimeOffset CalculateNextRun(ScheduleSpec schedule, DateTimeOffset fromUtc)
	{
		switch (schedule.Kind)
		{
			case AutomationScheduleKind.IntervalHours:
				var hours = Math.Max(1, schedule.IntervalHours ?? 24);
				return fromUtc.AddHours(hours);

			case AutomationScheduleKind.Daily:
				var targetTime = schedule.TimeOfDay ?? new TimeOnly(3, 0); // Default 03:00
				var todayTarget = new DateTimeOffset(fromUtc.Year, fromUtc.Month, fromUtc.Day,
					targetTime.Hour, targetTime.Minute, targetTime.Second, TimeSpan.Zero);
				return todayTarget <= fromUtc ? todayTarget.AddDays(1) : todayTarget;

			case AutomationScheduleKind.Weekly:
				var targetDay = schedule.DayOfWeek ?? DayOfWeek.Sunday;
				var weekTime = schedule.TimeOfDay ?? new TimeOnly(3, 0);
				var nextWeekly = new DateTimeOffset(fromUtc.Year, fromUtc.Month, fromUtc.Day,
					weekTime.Hour, weekTime.Minute, weekTime.Second, TimeSpan.Zero);
				while (nextWeekly.DayOfWeek != targetDay || nextWeekly <= fromUtc)
				{
					nextWeekly = nextWeekly.AddDays(1);
				}
				return nextWeekly;

			case AutomationScheduleKind.OnAppStart:
			default:
				return fromUtc;
		}
	}

	public void ValidateRuleRoot(string root)
	{
		if (string.IsNullOrWhiteSpace(root))
		{
			throw new ArgumentException("Rule root path cannot be empty.");
		}

		var fullPath = Path.GetFullPath(root);

		// 1. Drive roots rejection: e.g. "C:\", "D:\", "/"
		var rootDir = Path.GetPathRoot(fullPath);
		if (string.Equals(rootDir, fullPath, StringComparison.OrdinalIgnoreCase) ||
		    fullPath.TrimEnd('\\', '/').Length <= 3)
		{
			throw new ArgumentException($"Targeting a drive root directly ('{fullPath}') is strictly prohibited for automated rules.");
		}

		// 2. Reject protected system directories: Windows, Program Files
		var windowsDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
		if (!string.IsNullOrEmpty(windowsDir) && fullPath.StartsWith(Path.GetFullPath(windowsDir), StringComparison.OrdinalIgnoreCase))
		{
			throw new ArgumentException($"System directory '{windowsDir}' cannot be targeted by automated rules.");
		}

		var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
		if (!string.IsNullOrEmpty(programFiles) && fullPath.StartsWith(Path.GetFullPath(programFiles), StringComparison.OrdinalIgnoreCase))
		{
			throw new ArgumentException($"Program Files directory '{programFiles}' cannot be targeted by automated rules.");
		}

		var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
		if (!string.IsNullOrEmpty(programFilesX86) && fullPath.StartsWith(Path.GetFullPath(programFilesX86), StringComparison.OrdinalIgnoreCase))
		{
			throw new ArgumentException($"Program Files directory '{programFilesX86}' cannot be targeted by automated rules.");
		}

		// 3. Excluded paths check
		var excluded = _settings.Current?.Scan?.ExcludedPaths ?? new List<string>();
		foreach (var exc in excluded)
		{
			if (string.IsNullOrWhiteSpace(exc)) continue;
			var excFull = Path.GetFullPath(exc);
			if (fullPath.StartsWith(excFull, StringComparison.OrdinalIgnoreCase))
			{
				throw new ArgumentException($"Path '{fullPath}' is inside excluded paths and cannot be targeted.");
			}
		}

		// 4. Allowlist: platform temp paths, user profile directory, ~/.cache, project cache allowlist
		var tempPath = Path.GetFullPath(Path.GetTempPath()).TrimEnd('\\', '/');
		var userProfile = Path.GetFullPath(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)).TrimEnd('\\', '/');
		var localAppData = Path.GetFullPath(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)).TrimEnd('\\', '/');

		bool isTemp = fullPath.StartsWith(tempPath, StringComparison.OrdinalIgnoreCase) ||
		              fullPath.StartsWith(Path.Combine(localAppData, "Temp"), StringComparison.OrdinalIgnoreCase);

		bool isUnderUserProfile = !string.IsNullOrEmpty(userProfile) && fullPath.StartsWith(userProfile, StringComparison.OrdinalIgnoreCase);

		// Check if it's a recognized project cache folder name
		bool isProjectCache = ProjectCacheAllowlist.Any(pc =>
			fullPath.IndexOf(pc, StringComparison.OrdinalIgnoreCase) >= 0);

		if (!isTemp && !isUnderUserProfile && !isProjectCache)
		{
			throw new ArgumentException($"Path root '{fullPath}' is outside the permitted allowlist (temp paths, user profile, or recognized cache dirs).");
		}
	}

	private List<string> FindMatchingFiles(AutomationRule rule)
	{
		var results = new List<string>();
		if (!Directory.Exists(rule.Root))
		{
			return results;
		}

		var criteria = rule.Criteria;
		var now = DateTime.UtcNow;
		var cutoff = criteria.OlderThanDays.HasValue ? now.AddDays(-criteria.OlderThanDays.Value) : (DateTime?)null;

		var options = new EnumerationOptions
		{
			IgnoreInaccessible = true,
			RecurseSubdirectories = criteria.RecurseSubdirectories,
			ReturnSpecialDirectories = false,
			AttributesToSkip = FileAttributes.ReparsePoint // Skip symlinks/junctions
		};

		try
		{
			var files = Directory.EnumerateFiles(rule.Root, "*", options);
			foreach (var file in files)
			{
				try
				{
					var fi = new FileInfo(file);

					// Filter 1: OlderThanDays
					if (cutoff.HasValue && fi.LastWriteTimeUtc > cutoff.Value)
					{
						continue;
					}

					// Filter 2: LargerThanBytes
					if (criteria.LargerThanBytes.HasValue && fi.Length < criteria.LargerThanBytes.Value)
					{
						continue;
					}

					// Filter 3: ExtensionAllowlist
					if (criteria.ExtensionAllowlist != null && criteria.ExtensionAllowlist.Length > 0)
					{
						var ext = fi.Extension;
						if (!criteria.ExtensionAllowlist.Any(e => string.Equals(e.StartsWith('.') ? e : "." + e, ext, StringComparison.OrdinalIgnoreCase)))
						{
							continue;
						}
					}

					// Filter 4: PathContainsAny
					if (criteria.PathContainsAny != null && criteria.PathContainsAny.Length > 0)
					{
						if (!criteria.PathContainsAny.Any(sub => file.Contains(sub, StringComparison.OrdinalIgnoreCase)))
						{
							continue;
						}
					}

					results.Add(file);
				}
				catch (Exception)
				{
					// Skip unreadable files
				}
			}
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Failed to enumerate files for automation rule {RuleId} in {Root}", rule.Id, rule.Root);
		}

		return results;
	}

	private void UpdateRuleScheduleOnFinish(string ruleId, DateTimeOffset runTimeUtc)
	{
		lock (_rulesLock)
		{
			var rules = _ruleStore.LoadAll();
			var index = rules.FindIndex(r => r.Id == ruleId);
			if (index >= 0)
			{
				var rule = rules[index];
				var nextRun = CalculateNextRun(rule.Schedule, DateTimeOffset.UtcNow);
				rules[index] = rule with
				{
					LastRunUtc = runTimeUtc,
					NextRunUtc = nextRun
				};
				_ruleStore.SaveAll(rules);
			}
		}
	}
}

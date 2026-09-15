using System;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.BackgroundWorkers;

public class AutomationWorker : BackgroundService
{
	private readonly IAutomationService _automationService;
	private readonly IDiskScannerEngine _scanner;
	private readonly INukeProtocolService _nukeService;
	private readonly ILogger<AutomationWorker> _logger;

	internal int TickIntervalMs { get; set; } = 30_000;

	public AutomationWorker(
		IAutomationService automationService,
		IDiskScannerEngine scanner,
		INukeProtocolService nukeService,
		ILogger<AutomationWorker> logger)
	{
		_automationService = automationService;
		_scanner = scanner;
		_nukeService = nukeService;
		_logger = logger;
	}

	protected override async Task ExecuteAsync(CancellationToken stoppingToken)
	{
		_logger.LogInformation("AutomationWorker is starting");

		// Startup grace period
		await Task.Delay(3000, stoppingToken);

		while (!stoppingToken.IsCancellationRequested)
		{
			try
			{
				await TickAsync(stoppingToken);
			}
			catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
			{
				break;
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Unhandled error in AutomationWorker tick loop");
			}

			await Task.Delay(TickIntervalMs, stoppingToken);
		}

		_logger.LogInformation("AutomationWorker is stopping");
	}

	internal async Task TickAsync(CancellationToken stoppingToken)
	{
		// Overlap guard — never run any automation rule while a disk scan or manual nuke is active
		if (_scanner.IsScanning || _nukeService.IsNuking)
		{
			_logger.LogInformation("AutomationWorker: Skipping tick — active scan or nuke in progress");
			return;
		}

		var now = DateTimeOffset.UtcNow;
		var dueRules = _automationService.GetDueRules(now);

		if (dueRules.Count == 0)
			return;

		foreach (var rule in dueRules)
		{
			if (stoppingToken.IsCancellationRequested)
				break;

			// Overlap guard check before each rule
			if (_scanner.IsScanning || _nukeService.IsNuking)
			{
				_logger.LogInformation("AutomationWorker: Skipping due rule {RuleId} — active scan or nuke started", rule.Id);
				break;
			}

			try
			{
				_logger.LogInformation("AutomationWorker executing due rule {RuleId} ({RuleName})", rule.Id, rule.Name);
				await _automationService.ExecuteRuleAsync(rule.Id, isManualTrigger: false, stoppingToken);
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "AutomationWorker encountered error executing rule {RuleId}", rule.Id);
			}
		}
	}
}

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Controllers;

[ApiController]
[Route("api/automation")]
public class AutomationController : ControllerBase
{
	private readonly IAutomationService _automationService;
	private readonly IAutomationAuditService _auditService;
	private readonly ILogger<AutomationController> _logger;

	public AutomationController(
		IAutomationService automationService,
		IAutomationAuditService auditService,
		ILogger<AutomationController> logger)
	{
		_automationService = automationService;
		_auditService = auditService;
		_logger = logger;
	}

	[HttpGet("rules")]
	public IActionResult GetRules()
	{
		return Ok(_automationService.GetRules());
	}

	[HttpGet("rules/{id}")]
	public IActionResult GetRule(string id)
	{
		var rule = _automationService.GetRule(id);
		if (rule == null) return NotFound(new { error = "NOT_FOUND", message = $"Rule '{id}' not found." });
		return Ok(rule);
	}

	[HttpPost("rules")]
	public IActionResult CreateRule([FromBody] CreateAutomationRuleRequest request)
	{
		try
		{
			var rule = _automationService.CreateRule(request);
			return CreatedAtAction(nameof(GetRule), new { id = rule.Id }, rule);
		}
		catch (ArgumentException ex)
		{
			return BadRequest(new { error = "ALLOWLIST_VIOLATION", message = ex.Message });
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Failed to create automation rule");
			return StatusCode(500, new { error = "INTERNAL_ERROR", message = ex.Message });
		}
	}

	[HttpPut("rules/{id}")]
	public IActionResult UpdateRule(string id, [FromBody] UpdateAutomationRuleRequest request)
	{
		try
		{
			var updated = _automationService.UpdateRule(id, request);
			return Ok(updated);
		}
		catch (KeyNotFoundException)
		{
			return NotFound(new { error = "NOT_FOUND", message = $"Rule '{id}' not found." });
		}
		catch (ArgumentException ex)
		{
			return BadRequest(new { error = "ALLOWLIST_VIOLATION", message = ex.Message });
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Failed to update automation rule {RuleId}", id);
			return StatusCode(500, new { error = "INTERNAL_ERROR", message = ex.Message });
		}
	}

	[HttpDelete("rules/{id}")]
	public IActionResult DeleteRule(string id)
	{
		var success = _automationService.DeleteRule(id);
		if (!success)
		{
			return NotFound(new { error = "NOT_FOUND", message = $"Rule '{id}' not found." });
		}
		return NoContent();
	}

	[HttpPost("rules/{id}/dryrun")]
	public async Task<IActionResult> DryRunRule(string id, CancellationToken ct)
	{
		try
		{
			var preview = await _automationService.DryRunRuleAsync(id, ct);
			return Ok(preview);
		}
		catch (KeyNotFoundException)
		{
			return NotFound(new { error = "NOT_FOUND", message = $"Rule '{id}' not found." });
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Failed to execute dry-run for rule {RuleId}", id);
			return StatusCode(500, new { error = "INTERNAL_ERROR", message = ex.Message });
		}
	}

	[HttpPost("rules/{id}/arm")]
	public IActionResult ArmRule(string id)
	{
		try
		{
			var armed = _automationService.ArmRule(id);
			return Ok(armed);
		}
		catch (KeyNotFoundException)
		{
			return NotFound(new { error = "NOT_FOUND", message = $"Rule '{id}' not found." });
		}
	}

	[HttpPost("rules/{id}/run")]
	public async Task<IActionResult> RunRule(string id, CancellationToken ct)
	{
		var rule = _automationService.GetRule(id);
		if (rule == null) return NotFound(new { error = "NOT_FOUND", message = $"Rule '{id}' not found." });

		try
		{
			var entry = await _automationService.ExecuteRuleAsync(id, isManualTrigger: true, ct);
			if (entry == null)
			{
				return Conflict(new { error = "OPERATION_BUSY", message = "Scan or nuke is actively running, or rule could not be executed." });
			}
			return Ok(entry);
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Error running rule {RuleId}", id);
			return StatusCode(500, new { error = "INTERNAL_ERROR", message = ex.Message });
		}
	}

	[HttpGet("audit")]
	public async Task<IActionResult> GetAudit([FromQuery] int days = 30)
	{
		var entries = await _auditService.GetEntriesAsync(days);
		return Ok(entries);
	}
}

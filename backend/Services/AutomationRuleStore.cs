using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

public class AutomationRuleStore : IAutomationRuleStore
{
	private readonly string _filePath;
	private readonly object _fileLock = new();
	private readonly ILogger<AutomationRuleStore> _logger;

	private static readonly JsonSerializerOptions _jsonOptions = new()
	{
		WriteIndented = true,
		PropertyNamingPolicy = JsonNamingPolicy.CamelCase
	};

	public AutomationRuleStore(ILogger<AutomationRuleStore> logger, string? testFilePath = null)
	{
		_logger = logger;

		if (testFilePath != null)
		{
			_filePath = testFilePath;
		}
		else
		{
			var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
			var appFolder = Path.Combine(appData, "GSAnalyzer");
			Directory.CreateDirectory(appFolder);
			_filePath = Path.Combine(appFolder, "automation_rules.json");
		}
	}

	public List<AutomationRule> LoadAll()
	{
		lock (_fileLock)
		{
			if (!File.Exists(_filePath))
				return new List<AutomationRule>();

			try
			{
				var json = File.ReadAllText(_filePath);
				var rules = JsonSerializer.Deserialize<List<AutomationRule>>(json, _jsonOptions);
				return rules ?? new List<AutomationRule>();
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Corrupt automation rules file detected, returning empty list");
				return new List<AutomationRule>();
			}
		}
	}

	public void SaveAll(List<AutomationRule> rules)
	{
		lock (_fileLock)
		{
			try
			{
				var dir = Path.GetDirectoryName(_filePath);
				if (!string.IsNullOrEmpty(dir))
				{
					Directory.CreateDirectory(dir);
				}

				var json = JsonSerializer.Serialize(rules, _jsonOptions);
				var tmpPath = _filePath + ".tmp";
				File.WriteAllText(tmpPath, json);

				// Atomic swap
				File.Move(tmpPath, _filePath, overwrite: true);
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Failed to save automation rules to disk");
			}
		}
	}
}

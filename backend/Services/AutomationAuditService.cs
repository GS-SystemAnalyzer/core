using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

public class AutomationAuditService : IAutomationAuditService
{
	private readonly string _filePath;
	private readonly SemaphoreSlim _lock = new(1, 1);
	private readonly ILogger<AutomationAuditService> _logger;

	private static readonly JsonSerializerOptions _jsonOptions = new()
	{
		WriteIndented = true,
		PropertyNamingPolicy = JsonNamingPolicy.CamelCase
	};

	public AutomationAuditService(ILogger<AutomationAuditService> logger, string? testFilePath = null)
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
			_filePath = Path.Combine(appFolder, "automation_audit.json");
		}
	}

	public async Task AppendEntryAsync(AutomationAuditEntry entry)
	{
		await _lock.WaitAsync();
		try
		{
			var entries = await LoadEntriesInternalAsync();
			entries.Add(entry);

			// Automatically prune records older than 90 days
			var cutoff = DateTimeOffset.UtcNow.AddDays(-90);
			entries = entries.Where(e => e.StartedUtc >= cutoff).ToList();

			await SaveEntriesInternalAsync(entries);
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Failed to append automation audit entry {EntryId}", entry.Id);
		}
		finally
		{
			_lock.Release();
		}
	}

	public async Task<List<AutomationAuditEntry>> GetEntriesAsync(int days = 30)
	{
		await _lock.WaitAsync();
		try
		{
			var entries = await LoadEntriesInternalAsync();
			if (days <= 0) return entries.OrderByDescending(e => e.StartedUtc).ToList();

			var cutoff = DateTimeOffset.UtcNow.AddDays(-days);
			return entries
				.Where(e => e.StartedUtc >= cutoff)
				.OrderByDescending(e => e.StartedUtc)
				.ToList();
		}
		finally
		{
			_lock.Release();
		}
	}

	public async Task PruneOldEntriesAsync(int retentionDays = 90)
	{
		await _lock.WaitAsync();
		try
		{
			var entries = await LoadEntriesInternalAsync();
			var cutoff = DateTimeOffset.UtcNow.AddDays(-retentionDays);
			var pruned = entries.Where(e => e.StartedUtc >= cutoff).ToList();
			if (pruned.Count != entries.Count)
			{
				await SaveEntriesInternalAsync(pruned);
			}
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Failed to prune old automation audit entries");
		}
		finally
		{
			_lock.Release();
		}
	}

	private async Task<List<AutomationAuditEntry>> LoadEntriesInternalAsync()
	{
		if (!File.Exists(_filePath))
			return new List<AutomationAuditEntry>();

		try
		{
			using var stream = File.OpenRead(_filePath);
			var entries = await JsonSerializer.DeserializeAsync<List<AutomationAuditEntry>>(stream, _jsonOptions);
			return entries ?? new List<AutomationAuditEntry>();
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Failed to read audit file, returning empty list");
			return new List<AutomationAuditEntry>();
		}
	}

	private async Task SaveEntriesInternalAsync(List<AutomationAuditEntry> entries)
	{
		var dir = Path.GetDirectoryName(_filePath);
		if (!string.IsNullOrEmpty(dir))
		{
			Directory.CreateDirectory(dir);
		}

		var tmpPath = _filePath + ".tmp";
		await using (var stream = File.Create(tmpPath))
		{
			await JsonSerializer.SerializeAsync(stream, entries, _jsonOptions);
		}

		File.Move(tmpPath, _filePath, overwrite: true);
	}
}

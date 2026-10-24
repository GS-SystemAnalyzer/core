namespace GSSystemAnalyzer.Engine;

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;

public class FileSystemIndexer : IFileSystemIndexer
{
	private readonly IHubContext<SystemHub>? _hub;
	private readonly ISettingService _settings;
	private readonly ILogger<FileSystemIndexer> _logger;
	private readonly ConcurrentDictionary<string, ConcurrentDictionary<string, IndexEntry>> _driveIndices =
		new(StringComparer.OrdinalIgnoreCase);

	public FileSystemIndexer(
		ISettingService settings,
		ILogger<FileSystemIndexer> logger,
		IHubContext<SystemHub>? hub = null)
	{
		_settings = settings;
		_logger = logger;
		_hub = hub;
	}

	public bool TryGetIndex(string rootPath, out IReadOnlyDictionary<string, IndexEntry> index)
	{
		var normalized = NormalizeDriveRoot(rootPath);
		if (_driveIndices.TryGetValue(normalized, out var dict))
		{
			index = dict;
			return true;
		}

		index = null!;
		return false;
	}

	public void Invalidate(string? rootPath = null)
	{
		if (string.IsNullOrWhiteSpace(rootPath))
		{
			_driveIndices.Clear();
		}
		else
		{
			_driveIndices.TryRemove(NormalizeDriveRoot(rootPath), out _);
		}
	}

	public async Task<IReadOnlyDictionary<string, IndexEntry>> IndexRootAsync(
		string rootPath,
		Guid scanId,
		CancellationToken cancellationToken)
	{
		var normalizedRoot = NormalizeDriveRoot(rootPath);
		var rootDir = new DirectoryInfo(rootPath);

		if (!rootDir.Exists)
		{
			_logger.LogWarning("Directory {Path} does not exist for indexing", rootPath);
			return new Dictionary<string, IndexEntry>();
		}

		var rules = new ScanTraversalRules(_settings.Current.Scan);
		var index = new ConcurrentDictionary<string, IndexEntry>(StringComparer.OrdinalIgnoreCase);

		long fileCount = 0;
		int throttleCount = 0;

		await EmitProgressAsync(scanId, "INITIALIZING", 0, "Starting unified filesystem scan...");

		var parallelOptions = new ParallelOptions
		{
			CancellationToken = cancellationToken,
			MaxDegreeOfParallelism = Math.Max(1, Environment.ProcessorCount)
		};

		var currentLevel = new List<(DirectoryInfo Dir, string ParentPath, int Depth)>
		{
			(rootDir, string.Empty, 1)
		};

		try
		{
			while (currentLevel.Count > 0)
			{
				cancellationToken.ThrowIfCancellationRequested();

				var nextLevel = new ConcurrentBag<(DirectoryInfo Dir, string ParentPath, int Depth)>();

				await Parallel.ForEachAsync(currentLevel, parallelOptions, (item, ct) =>
				{
					ct.ThrowIfCancellationRequested();

					if (rules.IsDirectorySkipped(item.Dir.FullName, item.Dir.Attributes, item.Depth))
					{
						return ValueTask.CompletedTask;
					}

					index[item.Dir.FullName] = new IndexEntry(
						item.Dir.FullName,
						item.ParentPath,
						true,
						0,
						item.Dir.LastWriteTimeUtc,
						item.Dir.Attributes
					);

					var pulse = Interlocked.Increment(ref throttleCount);
					if (pulse % 50 == 0)
					{
						_ = EmitProgressAsync(scanId, "SCANNING", Volatile.Read(ref fileCount), item.Dir.Name);
					}

					// Enumerate files
					try
					{
						foreach (var file in item.Dir.EnumerateFiles("*"))
						{
							ct.ThrowIfCancellationRequested();

							long length = 0;
							try { length = file.Length; } catch { continue; }

							if (!rules.IsFileSkipped(file.FullName, file.Attributes, length))
							{
								index[file.FullName] = new IndexEntry(
									file.FullName,
									item.Dir.FullName,
									false,
									length,
									file.LastWriteTimeUtc,
									file.Attributes
								);
								Interlocked.Increment(ref fileCount);
							}
						}
					}
					catch (UnauthorizedAccessException) { }
					catch (DirectoryNotFoundException) { }
					catch (IOException) { }

					// Enumerate subdirectories for next depth level
					if (item.Depth + 1 <= _settings.Current.Scan.Depth)
					{
						try
						{
							foreach (var subDir in item.Dir.EnumerateDirectories("*"))
							{
								ct.ThrowIfCancellationRequested();
								nextLevel.Add((subDir, item.Dir.FullName, item.Depth + 1));
							}
						}
						catch (UnauthorizedAccessException) { }
						catch (DirectoryNotFoundException) { }
						catch (IOException) { }
					}

					return ValueTask.CompletedTask;
				});

				currentLevel = nextLevel.ToList();
			}

			_driveIndices[normalizedRoot] = index;
			await EmitProgressAsync(scanId, "COMPLETED", Volatile.Read(ref fileCount), "Scan completed");
			return index;
		}
		catch (OperationCanceledException)
		{
			await EmitProgressAsync(scanId, "CANCELED", Volatile.Read(ref fileCount), "Scan canceled");
			throw;
		}
	}

	private async Task EmitProgressAsync(Guid scanId, string status, long count, string currentTarget)
	{
		if (_hub == null) return;

		try
		{
			await _hub.Clients.All.SendAsync("ScanProgress", new
			{
				scanId = scanId,
				status = status,
				count = count,
				currentTarget = currentTarget
			});
		}
		catch (Exception ex)
		{
			_logger.LogDebug(ex, "Failed to emit ScanProgress over SignalR");
		}
	}

	private static string NormalizeDriveRoot(string path)
	{
		return path.Replace('\\', '/').TrimEnd('/');
	}
}

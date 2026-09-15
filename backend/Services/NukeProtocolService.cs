using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.IO;
using Microsoft.Extensions.Caching.Memory;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Interfaces;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

public class NukeProtocolService : INukeProtocolService
{
	private readonly IDiskScannerEngine _scanner;
	private readonly IHubContext<SystemHub> _hubContext;
	private readonly ILogger<NukeProtocolService> _logger;

	// Session-scoped undo stack — max 5 entries, not persisted across restarts.
	private readonly Stack<NukeOperation> _undoStack = new();
	private readonly object _undoLock = new();
	private const int MaxUndoEntries = 5;

	// Cache of active plan tokens to their normalized paths (TTL 15 mins)
	private readonly MemoryCache _activePlanTokens = new MemoryCache(new MemoryCacheOptions());
	private int _activeNukeCount = 0;
	public bool IsNuking => Volatile.Read(ref _activeNukeCount) > 0;

	public async Task<NukePreviewResponse> PreviewNukeAsync(List<string> paths, CancellationToken cancellationToken = default)
	{
		return await Task.Run(() =>
		{
			var response = new NukePreviewResponse();

			var options = new EnumerationOptions
			{
				IgnoreInaccessible = true,
				RecurseSubdirectories = true,
				ReturnSpecialDirectories = false
			};

			foreach (var path in paths)
			{
				cancellationToken.ThrowIfCancellationRequested();

				long pathBytes = 0;
				int pathFileCount = 0;

				if (File.Exists(path))
				{
					// if it's a single file
					pathBytes = new FileInfo(path).Length;
					pathFileCount = 1;
				}
				else if (Directory.Exists(path))
				{
					// The Zero Allocation Counter
					// We parse the raw OS struct, update the tally, and discard the object instantly
					var counter = new System.IO.Enumeration.FileSystemEnumerable<byte>(
						path,
						(ref System.IO.Enumeration.FileSystemEntry entry) =>
						{
							if (!entry.IsDirectory)
							{
								try
								{
									pathBytes += entry.Length;
									pathFileCount++;
								}
								catch (FileNotFoundException)
								{
									// File was deleted between enumeration and size check
								}
								catch (UnauthorizedAccessException)
								{
									// Access denied for this file
								}
							}
							return 0;
						},
						options
					);

					foreach (var _ in counter)
					{
						cancellationToken.ThrowIfCancellationRequested();
					}
				}
				else
				{
					// if it's a ghost path
					continue;
				}


				response.Breakdown.Add(new NukePathBreakdown
				{
					Path = path,
					SizeBytes = pathBytes,
					FileCount = pathFileCount
				});

				response.TotalBytes += pathBytes;
				response.TotalFiles += pathFileCount;
			}

			response.TotalFormatted = FormatSize(response.TotalBytes);

			var planToken = Guid.NewGuid().ToString("N");
			response.PlanToken = planToken;

			var normalizedPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
			foreach (var p in paths)
			{
				normalizedPaths.Add(Path.GetFullPath(p));
			}
			_activePlanTokens.Set(planToken, normalizedPaths, TimeSpan.FromMinutes(15));

			return response;

		}, cancellationToken);
	}

	public async Task<NukeResultDto> ObliterateNodeAsync(List<string> paths, string planToken, bool useRecycleBin = false, CancellationToken cancellationToken = default)
	{
		if (string.IsNullOrWhiteSpace(planToken) || !_activePlanTokens.TryGetValue(planToken, out HashSet<string> validPaths))
		{
			throw new UnauthorizedAccessException("Execution requires a valid Dry-Run planToken.");
		}

		foreach (var path in paths)
		{
			var normalizedPath = Path.GetFullPath(path);
			if (!validPaths.Contains(normalizedPath))
			{
				throw new UnauthorizedAccessException("Target path was not part of the previewed plan.");
			}
		}

		// Remove the token so it can't be reused
		_activePlanTokens.Remove(planToken);

		Interlocked.Increment(ref _activeNukeCount);
		try
		{
			var totalNodes = paths.Count;
		var processedNodes = 0;
		var cancelToken = _scanner.NukeToken();
		using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancelToken, cancellationToken);
		var combinedToken = linkedCts.Token;

		// Throttle progress so we don't await a hub round-trip per file.
		var lastProgressSent = DateTime.MinValue;
		var progressInterval = TimeSpan.FromMilliseconds(150);

		// Counters for the new result shape
		int deletedFiles = 0;
		long freedBytes = 0;
		long stagedBytes = 0;
		int skippedFiles = 0;
		var deletedPaths = new List<string>();
		var aborted = false;

		// Generate a unique operation ID for undo tracking
		var operationId = $"nuke-{Guid.NewGuid():N}";

		foreach (var path in paths)
		{
			if (combinedToken.IsCancellationRequested)
			{
				aborted = true;
				break;
			}

			try
			{
				if (File.Exists(path))
				{
					var fileInfo = new FileInfo(path);
					var fileSize = fileInfo.Length;

					if (useRecycleBin)
					{
						MoveToStaging(path, operationId, isDirectory: false);
					}
					else
					{
						ExecuteWithRetry(() =>
						{
							// Only clear attributes when needed — skip a syscall on normal files.
							var attributes = File.GetAttributes(path);
							if ((attributes & FileAttributes.ReadOnly) != 0)
							{
								File.SetAttributes(path, FileAttributes.Normal);
							}
							File.Delete(path);
						});
					}

					deletedFiles++;
					if (useRecycleBin) stagedBytes += fileSize;
					else freedBytes += fileSize;
					deletedPaths.Add(path);
				}
				else if (Directory.Exists(path))
				{
					// Count files and size before deletion
					var (fileCount, totalSize) = CountDirectoryContents(path);

					if (useRecycleBin)
					{
						MoveToStaging(path, operationId, isDirectory: true);
					}
					else
					{
						AggressiveObliterate(path);
					}

					deletedFiles += fileCount;
					if (useRecycleBin) stagedBytes += totalSize;
					else freedBytes += totalSize;
					deletedPaths.Add(path);
				}
				else
				{
					skippedFiles++;
					continue; // ghost path
				}


				processedNodes++;

				var percentage = Math.Round(((double)processedNodes / totalNodes) * 100, 1);

				// Emit at most every 150ms, but always emit the final tick.
				if (DateTime.UtcNow - lastProgressSent >= progressInterval || processedNodes == totalNodes)
				{
					lastProgressSent = DateTime.UtcNow;
					await _hubContext.Clients.All.SendAsync("NukeProgress", new
					{
						completed = processedNodes,
						total = totalNodes,
						percentage = percentage,
						currentTarget = Path.GetFileName(path)
					});
				}
			}
			catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
			{
				_logger.LogDebug("Skipped {Path}: in use or access denied ({Message})", path, ex.Message);
				skippedFiles++;
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Failed to nuke {Path}", path);
				skippedFiles++;
			}
		}

		// Invalidate everything we removed in a single cache pass, then persist to disk ONCE.
		_scanner.InvalidatePaths(deletedPaths);

		// Push to undo stack
		if (deletedPaths.Count > 0)
		{
			var operation = new NukeOperation(
				OperationId: operationId,
				ExecutedAt: DateTime.UtcNow,
				OriginalPaths: new List<string>(paths),
				DeletedPaths: new List<string>(deletedPaths),
				UsedRecycleBin: useRecycleBin,
				DeletedFiles: deletedFiles
			);
			PushUndo(operation);
		}

		if (aborted)
		{
			await _hubContext.Clients.All.SendAsync("NukeAborted", "OPERATION ABORTED BY USER");
		}

			return new NukeResultDto
			{
				DeletedFiles = deletedFiles,
				FreedBytes = freedBytes,
				FreedFormatted = FormatSize(freedBytes),
				StagedBytes = stagedBytes,
				StagedFormatted = FormatSize(stagedBytes),
				SkippedFiles = skippedFiles,
				RecycleBinUsed = useRecycleBin,
				Recoverable = useRecycleBin && deletedPaths.Count > 0,
				OperationId = operationId
			};
		}
		finally
		{
			Interlocked.Decrement(ref _activeNukeCount);
		}
	}

	private void MoveToStaging(string originalPath, string operationId, bool isDirectory)
	{
		var driveRoot = StagingBaseResolver(originalPath);
		var stagingDir = Path.Combine(driveRoot, ".gsanalyzer_trash", operationId);

		// Preserve the full path inside staging so we know where to restore.
		// e.g. "C:/projects/old" → "{stagingDir}/C/projects/old"
		var relativePath = originalPath
			.Replace(":", "_DRIVE_")   // "C:" → "C_DRIVE_"
			.Replace("\\", "/")
			.TrimStart('/');

		var destination = Path.Combine(stagingDir, relativePath);
		var destinationDir = Path.GetDirectoryName(destination);

		if (!string.IsNullOrEmpty(destinationDir))
			Directory.CreateDirectory(destinationDir);

		ExecuteWithRetry(() =>
		{
			if (isDirectory)
			{
				// Clear only read-only attributes before moving, preserving others
				var dir = new DirectoryInfo(originalPath);
				foreach (var info in dir.GetFileSystemInfos("*", SearchOption.AllDirectories))
				{
					if ((info.Attributes & FileAttributes.ReadOnly) != 0)
					{
						info.Attributes &= ~FileAttributes.ReadOnly;
					}
				}
				if ((dir.Attributes & FileAttributes.ReadOnly) != 0)
				{
					dir.Attributes &= ~FileAttributes.ReadOnly;
				}

				Directory.Move(originalPath, destination);
			}
			else
			{
				var attributes = File.GetAttributes(originalPath);
				if ((attributes & FileAttributes.ReadOnly) != 0)
				{
					File.SetAttributes(originalPath, attributes & ~FileAttributes.ReadOnly);
				}
				File.Move(originalPath, destination);
			}
		});
	}

	private (int restoredCount, int failedCount) RestoreFromStaging(NukeOperation operation)
	{
		int restored = 0;
		int failed = 0;

		foreach (var originalPath in operation.DeletedPaths)
		{
			try
			{
				var driveRoot = StagingBaseResolver(originalPath);
				var stagingDir = Path.Combine(driveRoot, ".gsanalyzer_trash", operation.OperationId);

				var relativePath = originalPath
					.Replace(":", "_DRIVE_")
					.Replace("\\", "/")
					.TrimStart('/');

				var stagedPath = Path.Combine(stagingDir, relativePath);

				if (Directory.Exists(stagedPath))
				{
					// Ensure parent directory exists
					var parentDir = Path.GetDirectoryName(originalPath);
					if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir))
						Directory.CreateDirectory(parentDir);

					var finalPath = GetUniqueRestorePath(originalPath, isDirectory: true);
					Directory.Move(stagedPath, finalPath);
					restored++;
				}
				else if (File.Exists(stagedPath))
				{
					var parentDir = Path.GetDirectoryName(originalPath);
					if (!string.IsNullOrEmpty(parentDir) && !Directory.Exists(parentDir))
						Directory.CreateDirectory(parentDir);

					var finalPath = GetUniqueRestorePath(originalPath, isDirectory: false);
					File.Move(stagedPath, finalPath);
					restored++;
				}
				else
				{
					_logger.LogWarning("Staged item not found during undo: {StagedPath}", stagedPath);
					failed++;
				}
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to restore {OriginalPath} during undo", originalPath);
				failed++;
			}
		}

		// Clean up staging directory for this operation
		var drives = operation.OriginalPaths
			.Select(p => StagingBaseResolver(p))
			.Where(r => !string.IsNullOrEmpty(r))
			.Distinct();

		foreach (var drive in drives)
		{
			var stagingDir = Path.Combine(drive!, ".gsanalyzer_trash", operation.OperationId);
			int retries = 3;
			while (retries > 0)
			{
				try
				{
					if (Directory.Exists(stagingDir))
						Directory.Delete(stagingDir, true);
					break;
				}
				catch (Exception ex)
				{
					retries--;
					if (retries == 0)
						_logger.LogWarning(ex, "Failed to clean staging directory {StagingDir}", stagingDir);
					else
						Thread.Sleep(50);
				}
			}
		}

		return (restored, failed);
	}

	private string GetUniqueRestorePath(string originalPath, bool isDirectory)
	{
		if (!File.Exists(originalPath) && !Directory.Exists(originalPath))
			return originalPath;

		var directory = Path.GetDirectoryName(originalPath) ?? string.Empty;
		var name = isDirectory ? Path.GetFileName(originalPath) : Path.GetFileNameWithoutExtension(originalPath);
		var ext = isDirectory ? "" : Path.GetExtension(originalPath);

		int count = 1;
		while (true)
		{
			var newName = $"{name}_Restored_{count}{ext}";
			var newPath = Path.Combine(directory, newName);
			if (!File.Exists(newPath) && !Directory.Exists(newPath))
				return newPath;
			count++;
		}
	}

	private void PushUndo(NukeOperation operation)
	{
		lock (_undoLock)
		{
			// Enforce max capacity — drop oldest if at limit
			if (_undoStack.Count >= MaxUndoEntries)
			{
				// Convert to list, remove bottom, rebuild stack
				var items = _undoStack.ToList();
				items.Reverse(); // Stack.ToList() gives newest-first — reverse to get chronological order

				// Remove oldest and clean up its staging directory
				var oldest = items[0];
				CleanupStagingForOperation(oldest);
				items.RemoveAt(0);

				_undoStack.Clear();
				foreach (var item in items)
					_undoStack.Push(item);
			}

			_undoStack.Push(operation);
		}
	}

	public NukeOperation? PeekUndo()
	{
		lock (_undoLock)
		{
			return _undoStack.FirstOrDefault(op => op.UsedRecycleBin);
		}
	}

	public NukeResultDto? UndoNuke(string? operationId = null)
	{
		NukeOperation? operation = null;

		lock (_undoLock)
		{
			if (_undoStack.Count == 0)
				return null;

			var items = _undoStack.ToList();
			int targetIndex;

			if (operationId != null)
			{
				targetIndex = items.FindIndex(op => op.OperationId == operationId && op.UsedRecycleBin);
			}
			else
			{
				targetIndex = items.FindIndex(op => op.UsedRecycleBin);
			}

			if (targetIndex == -1)
				return null;

			operation = items[targetIndex];
			items.RemoveAt(targetIndex);

			_undoStack.Clear();
			items.Reverse();
			foreach (var item in items)
				_undoStack.Push(item);
		}

		var (restoredCount, failedCount) = RestoreFromStaging(operation);

		// Invalidate cache for restored paths so the scanner picks up the restored files
		_scanner.InvalidatePaths(operation.DeletedPaths);

		return new NukeResultDto
		{
			DeletedFiles = restoredCount,       // reusing field — "restored files" in undo context
			FreedBytes = 0,
			FreedFormatted = "0 B",
			StagedBytes = 0,
			StagedFormatted = "0 B",
			SkippedFiles = failedCount,
			RecycleBinUsed = true,
			Recoverable = false,                // no longer recoverable after undo
			OperationId = operation.OperationId
		};
	}

	public void ClearUndoStack()
	{
		lock (_undoLock)
		{
			// Clean up all staging directories
			foreach (var operation in _undoStack)
			{
				CleanupStagingForOperation(operation);
			}
			_undoStack.Clear();
		}
	}

	private void CleanupStagingForOperation(NukeOperation operation)
	{
		if (!operation.UsedRecycleBin) return;

		var drives = operation.OriginalPaths
			.Select(p => StagingBaseResolver(p))
			.Where(r => !string.IsNullOrEmpty(r))
			.Distinct();

		foreach (var drive in drives)
		{
			var stagingDir = Path.Combine(drive!, ".gsanalyzer_trash", operation.OperationId);
			int retries = 3;
			while (retries > 0)
			{
				try
				{
					if (Directory.Exists(stagingDir))
						Directory.Delete(stagingDir, true);
					break;
				}
				catch (Exception ex)
				{
					retries--;
					if (retries == 0)
						_logger.LogWarning(ex, "Failed to clean staging {StagingDir} for operation {OperationId}", stagingDir, operation.OperationId);
					else
						Thread.Sleep(50);
				}
			}
		}
	}

	private (int fileCount, long totalSize) CountDirectoryContents(string path)
	{
		int count = 0;
		long size = 0;

		try
		{
			var options = new EnumerationOptions
			{
				IgnoreInaccessible = true,
				RecurseSubdirectories = true,
				ReturnSpecialDirectories = false
			};

			foreach (var file in new DirectoryInfo(path).EnumerateFiles("*", options))
			{
				count++;
				size += file.Length;
			}
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Failed to count directory contents at {Path}", path);
		}

		return (count, size);
	}

	private void ExecuteWithRetry(Action action, int maxRetries = 3, int delayMs = 50)
	{
		for (int i = 0; i < maxRetries; i++)
		{
			try
			{
				action();
				return;
			}
			catch (Exception ex) when (i < maxRetries - 1 && (ex is IOException || ex is UnauthorizedAccessException))
			{
				Thread.Sleep(delayMs);
			}
		}
	}

	private void AggressiveObliterate(string targetPath)
	{
		ExecuteWithRetry(() =>
		{
			var dir = new DirectoryInfo(targetPath);

			foreach (var info in dir.GetFileSystemInfos("*", SearchOption.AllDirectories))
			{
				info.Attributes = FileAttributes.Normal;
			}

			dir.Attributes = FileAttributes.Normal;
			dir.Delete(true);
		});
	}

	private string FormatSize(long bytes)
	{
		string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
		int counter = 0;
		decimal number = bytes;

		while (Math.Round(number / 1024) >= 1)
		{
			number /= 1024;
			counter++;
		}

		return string.Format("{0:n1} {1}", number, suffixes[counter]);
	}

	public List<NukeOperation> GetUndoHistory()
	{
		lock (_undoLock)
		{
			return _undoStack.ToList();
		}
	}

	public void TriggerNukeAbort()
	{
		_scanner.TriggerNukeAbort();
	}

	private void CleanupOrphanedStagingDirs()
	{
		long totalFreed = 0;

		// 1. Clean up old StagingRoot (AppData) if it exists
		try
		{
			var oldStagingRoot = Path.Combine(
				Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
				"GSAnalyzer", "nuke_trash");

			if (Directory.Exists(oldStagingRoot))
			{
				totalFreed += GetDirectorySize(oldStagingRoot);
				Directory.Delete(oldStagingRoot, true);
			}
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Failed to clean old staging root on startup");
		}

		// 2. Clean up per-volume .gsanalyzer_trash
		foreach (var drive in DriveInfo.GetDrives())
		{
			if (!drive.IsReady) continue;

			try
			{
				var stagingDir = Path.Combine(drive.RootDirectory.FullName, ".gsanalyzer_trash");
				if (Directory.Exists(stagingDir))
				{
					totalFreed += GetDirectorySize(stagingDir);
					Directory.Delete(stagingDir, true);
				}
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to clean staging dir on {DriveName} during startup", drive.Name);
			}
		}

		if (totalFreed > 0)
		{
			_logger.LogInformation("Startup cleanup completed: freed {FreedSize} of orphaned nuke trash", FormatSize(totalFreed));
		}
	}

	private long GetDirectorySize(string path)
	{
		long size = 0;
		try
		{
			var dirInfo = new DirectoryInfo(path);
			foreach (var file in dirInfo.EnumerateFiles("*", SearchOption.AllDirectories))
			{
				size += file.Length;
			}
		}
		catch
		{
			// Ignore access issues during size calculation
		}
		return size;
	}

	public Func<string, string> StagingBaseResolver { get; set; } = p => Path.GetPathRoot(p) ?? "C:\\";

	public NukeProtocolService(IDiskScannerEngine scanner, IHubContext<SystemHub> hubContext,
		ILogger<NukeProtocolService> logger, bool runStartupCleanup = true)
	{
		_scanner = scanner;
		_hubContext = hubContext;
		_logger = logger;
		if (runStartupCleanup) Task.Run(() => CleanupOrphanedStagingDirs());
	}
}

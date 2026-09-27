using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

public class TempFolderCleanerService : ITempFolderCleanerService
{
	private readonly INukeProtocolService _nukeService;
	private readonly ILogger<TempFolderCleanerService> _logger;
	private readonly IDiskScannerEngine? _scanner;
	private readonly List<string>? _tempPathsOverride;

	public TempFolderCleanerService(
		INukeProtocolService nukeService,
		ILogger<TempFolderCleanerService> logger,
		IEnumerable<string>? tempPathsOverride = null)
		: this(nukeService, logger, null, tempPathsOverride)
	{
	}

	public TempFolderCleanerService(
		INukeProtocolService nukeService,
		ILogger<TempFolderCleanerService> logger,
		IDiskScannerEngine? scanner,
		IEnumerable<string>? tempPathsOverride = null)
	{
		_nukeService = nukeService;
		_logger = logger;
		_scanner = scanner;

		var overrides = tempPathsOverride?
			.Where(p => !string.IsNullOrWhiteSpace(p))
			.ToList();
		_tempPathsOverride = overrides is { Count: > 0 } ? overrides : null;
	}

	// Delegates target discovery to the centralized TempFolderDictionary registry.
	public static List<CleanTarget> ResolveCleanTargets() => TempFolderDictionary.ResolveCleanTargets();

	/// <summary>Back-compat shim: existing whitelist + unit tests keep working unchanged.</summary>
	public static List<string> ResolveTempPaths() => TempFolderDictionary.ResolveTempPaths();

	public async Task<TempPreviewResponse> PreviewAsync(CancellationToken cancellationToken = default)
	{
		return await Task.Run(() =>
		{
			var response = new TempPreviewResponse();

			// When _tempPathsOverride is set (tests), fall back to string-only mode
			// with generic labels. Otherwise, use full typed discovery.
			List<CleanTarget> targets;
			if (_tempPathsOverride != null)
			{
				targets = _tempPathsOverride
					.Where(p => !string.IsNullOrWhiteSpace(p) && Directory.Exists(p))
					.Select(p => new CleanTarget(Path.GetFullPath(p), Path.GetFileName(p.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)), CleanCategory.Temp))
					.ToList();
			}
			else
			{
				targets = ResolveCleanTargets();
			}

			_logger.LogInformation("Cleaner resolved {Count} locations: {Targets}",
				targets.Count, string.Join(" | ", targets.Select(t => $"{t.Label}={t.Path}")));

			var options = new EnumerationOptions
			{
				IgnoreInaccessible = true,
				RecurseSubdirectories = true,
				ReturnSpecialDirectories = false,
				AttributesToSkip = FileAttributes.ReparsePoint
			};

			foreach (var target in targets)
			{
				cancellationToken.ThrowIfCancellationRequested();

				long sizeBytes = 0;
				int fileCount = 0;

				try
				{
					foreach (var file in new DirectoryInfo(target.Path).EnumerateFiles("*", options))
					{
						cancellationToken.ThrowIfCancellationRequested();
						try
						{
							sizeBytes += file.Length;
							fileCount++;
						}
						catch
						{
							// Locked or permission-denied on individual file — skip silently.
						}
					}
				}
				catch (Exception ex)
				{
					// Entire directory unreadable (permission denied, etc.) — omit it.
					_logger.LogWarning(ex, "Skipping unreadable location {Path}", target.Path);
					continue;
				}

				response.Locations.Add(new TempLocationPreview
				{
					Path = target.Path,
					Label = target.Label,
					Category = target.Category.ToString(),
					SizeBytes = sizeBytes,
					SizeFormatted = FormatSize(sizeBytes),
					FileCount = fileCount
				});

				response.TotalBytes += sizeBytes;
			}

			response.Locations = response.Locations.OrderByDescending(l => l.SizeBytes).ToList();
			response.TotalFormatted = FormatSize(response.TotalBytes);
			return response;
		}, cancellationToken);
	}

	public async Task<TempCleanResult> CleanAsync(List<string> paths, CancellationToken cancellationToken = default)
	{
		return await Task.Run(() =>
		{
			var knownPaths = _tempPathsOverride ?? ResolveTempPaths();
			var comparer = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
				? StringComparer.OrdinalIgnoreCase
				: StringComparer.Ordinal;
			var knownSet = new HashSet<string>(
				knownPaths.Select(NormalizePath), comparer);

			foreach (var p in paths)
			{
				var normalized = NormalizePath(p);
				if (!knownSet.Contains(normalized))
					throw new UnauthorizedAccessException(
						$"Path '{p}' is not a recognised temp directory. Only known temp locations may be cleaned.");
			}

			int totalDeleted = 0;
			long totalFreed = 0;
			int totalSkipped = 0;
			var allDeletedPaths = new List<string>();

			var options = new EnumerationOptions
			{
				IgnoreInaccessible = true,
				RecurseSubdirectories = true,
				ReturnSpecialDirectories = false,
				AttributesToSkip = FileAttributes.ReparsePoint
			};

			foreach (var p in paths)
			{
				cancellationToken.ThrowIfCancellationRequested();

				var tempDir = NormalizePath(p);
				if (!Directory.Exists(tempDir))
					continue;

				try
				{
					foreach (var file in new DirectoryInfo(tempDir).EnumerateFiles("*", options))
					{
						cancellationToken.ThrowIfCancellationRequested();

						try
						{
							var len = file.Length;
							if ((file.Attributes & FileAttributes.ReadOnly) != 0)
							{
								file.Attributes = FileAttributes.Normal;
							}
							file.Delete();

							totalDeleted++;
							totalFreed += len;
							allDeletedPaths.Add(file.FullName);
						}
						catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
						{
							// In-use by active processes or access-denied: skip immediately without sleep retry.
							totalSkipped++;
						}
						catch (Exception ex)
						{
							_logger.LogDebug(ex, "Failed to delete temp file {File}", file.FullName);
							totalSkipped++;
						}
					}
				}
				catch (Exception ex)
				{
					_logger.LogWarning(ex, "Failed to enumerate files in temp dir: {Path}", tempDir);
				}

				// Clean up empty subdirectories left behind (bottom-up).
				CleanEmptySubdirectories(tempDir);
			}

			// Single cache invalidation pass across all deleted paths at the end.
			if (allDeletedPaths.Count > 0 && _scanner != null)
			{
				try
				{
					_scanner.InvalidatePaths(allDeletedPaths);
				}
				catch (Exception ex)
				{
					_logger.LogWarning(ex, "Failed to invalidate scanner memory for temp deleted paths");
				}
			}

			return new TempCleanResult
			{
				DeletedFiles = totalDeleted,
				FreedBytes = totalFreed,
				FreedFormatted = FormatSize(totalFreed),
				SkippedFiles = totalSkipped
			};
		}, cancellationToken);
	}

	private static string NormalizePath(string path)
	{
		var full = Path.GetFullPath(path);
		return full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
	}

	private void CleanEmptySubdirectories(string tempDir)
	{
		var normalizedRoot = NormalizePath(tempDir);

		try
		{
			// Use a non-recursive first pass to collect only real (non-reparse) subdirectories,
			// then recurse manually. This avoids following symlinks/junctions.
			var options = new EnumerationOptions
			{
				IgnoreInaccessible = true,
				RecurseSubdirectories = true,
				ReturnSpecialDirectories = false,
				AttributesToSkip = FileAttributes.ReparsePoint // skip symlinks & junctions
			};

			var subdirs = new DirectoryInfo(tempDir)
				.EnumerateDirectories("*", options)
				.Select(d => d.FullName)
				.OrderByDescending(d => d.Length) // deepest first
				.ToList();

			foreach (var dir in subdirs)
			{
				// Double-guard: never delete the root temp directory itself.
				if (string.Equals(NormalizePath(dir), normalizedRoot,
					RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
						? StringComparison.OrdinalIgnoreCase
						: StringComparison.Ordinal))
					continue;

				try
				{
					if (Directory.Exists(dir) && !Directory.EnumerateFileSystemEntries(dir).Any())
						Directory.Delete(dir);
				}
				catch
				{
					// Locked or permission-denied — skip silently.
				}
			}
		}
		catch (Exception ex)
		{
			_logger.LogDebug(ex, "Could not clean empty subdirectories in {TempDir}", tempDir);
		}
	}

	private static string FormatSize(long bytes)
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
}

using System.Collections.Concurrent;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Caching.Memory;

namespace GSSystemAnalyzer.Engine;

public class FileTypeScanner : IFileTypeScanner
{
	private readonly DiskScannerEngine _engine;
	private readonly IMemoryCache _cache;
	private readonly IScanCacheService? _cacheService;

	public FileTypeScanner(DiskScannerEngine engine, IMemoryCache cache, IScanCacheService? cacheService = null)
	{
		_engine = engine;
		_cache = cache;
		_cacheService = cacheService;

		if (_cacheService != null)
		{
			_cacheService.OnSubtreeInvalidated += (s, root) =>
			{
				if (!string.IsNullOrEmpty(root))
				{
					Invalidate(root);
				}
			};
		}
	}

	/// <inheritdoc/>
	public FileTypeScanResult? Analyze(string root)
	{
		var normalized = NormalizeRoot(root);
		var cacheKey = $"filetypes:{normalized.ToLowerInvariant()}";

		if (_cache.TryGetValue(cacheKey, out FileTypeScanResult? hit))
			return hit;

		var normalizedNoSlash = normalized.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
		var wasScanned = (_cacheService != null && _cacheService.HasScanRoot(root)) ||
			_engine.DirectorySizeCache.Keys
			.Any(k => k.Equals(normalizedNoSlash, StringComparison.OrdinalIgnoreCase) ||
					  k.Equals(normalized, StringComparison.OrdinalIgnoreCase) ||
					  k.StartsWith(normalized, StringComparison.OrdinalIgnoreCase) ||
					  k.StartsWith(normalizedNoSlash + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
					  k.StartsWith(normalizedNoSlash + "/", StringComparison.OrdinalIgnoreCase));

		if (!wasScanned) return null;

		var result = BuildResult(normalized);
		_cache.Set(cacheKey, result, TimeSpan.FromMinutes(15));
		return result;
	}

	public void Invalidate(string root)
	{
		var norm = NormalizeRoot(root).ToLowerInvariant();
		_cache.Remove($"filetypes:{norm}");
		_cache.Remove($"extbreakdown:{norm}");
		var normNoSlash = norm.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
		_cache.Remove($"filetypes:{normNoSlash}");
		_cache.Remove($"extbreakdown:{normNoSlash}");
	}

	public ExtensionBreakdownResult? GetExtensionBreakdown(string root)
	{
		var normalized = NormalizeRoot(root);
		var cacheKey = $"extbreakdown:{normalized.ToLowerInvariant()}";

		if (_cache.TryGetValue(cacheKey, out ExtensionBreakdownResult? hit))
			return hit;

		var normalizedNoSlash = normalized.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
		var wasScanned = (_cacheService != null && _cacheService.HasScanRoot(root)) ||
			_engine.DirectorySizeCache.Keys
			.Any(k => k.Equals(normalizedNoSlash, StringComparison.OrdinalIgnoreCase) ||
					  k.Equals(normalized, StringComparison.OrdinalIgnoreCase) ||
					  k.StartsWith(normalized, StringComparison.OrdinalIgnoreCase) ||
					  k.StartsWith(normalizedNoSlash + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
					  k.StartsWith(normalizedNoSlash + "/", StringComparison.OrdinalIgnoreCase));

		if (!wasScanned) return null;

		var result = BuildExtensionBreakdownResult(normalized);
		_cache.Set(cacheKey, result, TimeSpan.FromMinutes(15));
		return result;
	}

	private ExtensionBreakdownResult BuildExtensionBreakdownResult(string root)
	{
		var normalizedRoot = NormalizeRoot(root);
		var extMap = BuildFromMemory(normalizedRoot);
		var realEntries = extMap.Where(kvp => !kvp.Key.StartsWith("__visited__")).ToList();
		var totalBytes = realEntries.Sum(v => v.Value.Bytes);

		var extensions = realEntries.Select(e =>
		{
			var extName = string.IsNullOrEmpty(e.Key) || e.Key == "no extension" ? "(none)" : e.Key.ToLowerInvariant();
			var cat = FileCategoryDictionary.GetCategory(extName);

			// if it was "no extension" in extMap, map to "(none)"
			if (e.Key == "no extension") extName = "(none)";

			var avgBytes = e.Value.Count > 0 ? e.Value.Bytes / e.Value.Count : 0;
			return new ExtensionBreakdownItem
			{
				Ext = extName,
				Category = cat,
				FileCount = e.Value.Count,
				TotalBytes = e.Value.Bytes,
				SizeFormatted = FormatBytes(e.Value.Bytes),
				PercentOfDisk = totalBytes > 0 ? Math.Round((double)e.Value.Bytes / totalBytes * 100, 1) : 0.0,
				AverageFileSizeBytes = avgBytes,
				AverageSizeFormatted = FormatBytes(avgBytes),
				LargestFileBytes = e.Value.LargestFileBytes,
				LargestFilePath = e.Value.LargestFilePath ?? string.Empty,
				LargestSizeFormatted = FormatBytes(e.Value.LargestFileBytes)
			};
		})
		.OrderByDescending(x => x.TotalBytes)
		.ToList();

		return new ExtensionBreakdownResult
		{
			Root = root,
			Extensions = extensions
		};
	}

	private FileTypeScanResult BuildResult(string root)
	{
		var normalizedRoot = NormalizeRoot(root);

		var extMap = BuildFromMemory(normalizedRoot);

		var realEntries = extMap.Where(kvp => !kvp.Key.StartsWith("__visited__")).ToList();
		var totalBytes = realEntries.Sum(v => v.Value.Bytes);

		var categories = extMap
			.GroupBy(kvp => FileCategoryDictionary.GetCategory(kvp.Key))
			.Select(g =>
			{
				var catBytes = g.Sum(e => (long)e.Value.Bytes);
				var catCount = g.Sum(e => e.Value.Count);

				var extensions = g
					.Select(e => new FileTypeExtensionEntry
					{
						Ext = e.Key,
						FileCount = e.Value.Count,
						TotalBytes = e.Value.Bytes,
						SizeFormatted = FormatBytes(e.Value.Bytes),
						PercentOfDisk = totalBytes > 0
							? Math.Round((double)catBytes > 0 ? (double)e.Value.Bytes / totalBytes * 100 : 0.0, 1) : 0.0,
					})
					.OrderByDescending(e => e.TotalBytes)
					.ToList();

				return new FileTypeCategory
				{
					Name = g.Key,
					TotalBytes = catBytes,
					SizeFormatted = FormatBytes(catBytes),
					FileCount = catCount,
					PercentOfDisk = totalBytes > 0
						? Math.Round((double)catBytes / totalBytes * 100, 1) : 0.0,
					Extensions = extensions,
				};
			})
			.OrderByDescending(c => c.TotalBytes)
			.ToList();

		return new FileTypeScanResult
		{
			Root = root,
			TotalScannedBytes = totalBytes,
			TotalScannedFormatted = FormatBytes(totalBytes),
			ScannedAt = DateTime.UtcNow,
			Categories = categories,
		};
	}

	private ConcurrentDictionary<string, FileTypeEntry> BuildFromMemory(string root)
	{
		var extMap = new ConcurrentDictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase);

		var rootNoSlash = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
		var cachedDirs = _engine.DirectorySizeCache
			.Where(kvp => kvp.Key.Equals(rootNoSlash, StringComparison.OrdinalIgnoreCase) ||
						  kvp.Key.Equals(root, StringComparison.OrdinalIgnoreCase) ||
						  kvp.Key.StartsWith(root, StringComparison.OrdinalIgnoreCase) ||
						  kvp.Key.StartsWith(rootNoSlash + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
						  kvp.Key.StartsWith(rootNoSlash + "/", StringComparison.OrdinalIgnoreCase) ||
						  (kvp.Value.ScanRoot != null && kvp.Value.ScanRoot.TrimEnd('\\', '/').Equals(rootNoSlash, StringComparison.OrdinalIgnoreCase)))
			.ToList();

		foreach (var kvp in cachedDirs)
		{
			if (kvp.Value.Extensions != null)
			{
				foreach (var ext in kvp.Value.Extensions)
				{
					extMap.AddOrUpdate(
						ext.Key,
						_ => new FileTypeEntry
						{
							Count = ext.Value.Count,
							Bytes = ext.Value.Bytes,
							LargestFileBytes = ext.Value.LargestFileBytes,
							LargestFilePath = ext.Value.LargestFilePath
						},
						(_, prev) =>
						{
							prev.Count += ext.Value.Count;
							prev.Bytes += ext.Value.Bytes;
							if (ext.Value.LargestFileBytes > prev.LargestFileBytes)
							{
								prev.LargestFileBytes = ext.Value.LargestFileBytes;
								prev.LargestFilePath = ext.Value.LargestFilePath;
							}
							return prev;
						});
				}
			}
		}

		if (extMap.Count > 0)
		{
			return extMap;
		}

		// Fallback to _cacheService if DirectorySizeCache has no extension data (e.g. mocked cacheService in tests)
		if (_cacheService != null)
		{
			var nodes = _cacheService.GetNodesUnderRoot(root).ToList();
			if (nodes.Count > 0)
			{
				foreach (var node in nodes)
				{
					foreach (var file in node.Files)
					{
						var ext = string.IsNullOrEmpty(file.Extension) ? "no extension" : file.Extension.ToLowerInvariant();
						var filePath = Path.Combine(node.Path, file.Name);

						extMap.AddOrUpdate(
							ext,
							_ => new FileTypeEntry
							{
								Count = 1,
								Bytes = file.Length,
								LargestFileBytes = file.Length,
								LargestFilePath = filePath
							},
							(_, prev) =>
							{
								prev.Count += 1;
								prev.Bytes += file.Length;
								if (file.Length > prev.LargestFileBytes)
								{
									prev.LargestFileBytes = file.Length;
									prev.LargestFilePath = filePath;
								}
								return prev;
							});
					}
				}

				return extMap;
			}
		}

		return extMap;
	}

	private static string NormalizeRoot(string root)
	{
		var fullPath = Path.GetFullPath(root);
		if (!fullPath.EndsWith(Path.DirectorySeparatorChar) &&
			!fullPath.EndsWith(Path.AltDirectorySeparatorChar))
		{
			fullPath += Path.DirectorySeparatorChar;
		}
		return fullPath;
	}

	public static string FormatBytes(long bytes) => bytes switch
	{
		>= 1_099_511_627_776L => $"{bytes / 1_099_511_627_776.0:F1} TB",
		>= 1_073_741_824L => $"{bytes / 1_073_741_824.0:F1} GB",
		>= 1_048_576L => $"{bytes / 1_048_576.0:F1} MB",
		>= 1_024L => $"{bytes / 1_024.0:F1} KB",
		_ => $"{bytes} B",
	};
}

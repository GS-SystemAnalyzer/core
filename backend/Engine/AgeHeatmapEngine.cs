using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Caching.Memory;

namespace GSSystemAnalyzer.Engine;

public class AgeHeatmapEngine : IAgeHeatmapEngine
{
	private readonly DiskScannerEngine _engine;
	private readonly IMemoryCache _cache;
	private readonly IScanCacheService? _cacheService;

	public AgeHeatmapEngine(DiskScannerEngine engine, IMemoryCache cache, IScanCacheService? cacheService = null)
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
					_cache.Remove($"ageheatmap:{NormalizeRoot(root)}");
				}
			};
		}
	}

	/// <inheritdoc/>
	public AgeHeatmapResult? Analyze(string root)
	{
		var normalized = NormalizeRoot(root);
		var cacheKey = $"ageheatmap:{normalized}";

		if (_cache.TryGetValue(cacheKey, out AgeHeatmapResult? hit))
			return hit;

		// Check whether a scan has been run for this root (normalize cache keys before comparing)
		var normalizedNoSlash = normalized.TrimEnd('/');
		var wasScanned = (_cacheService != null && _cacheService.HasScanRoot(root)) ||
			_engine.DirectorySizeCache.Keys
			.Any(k =>
			{
				var nk = NormalizeKey(k);
				return nk == normalizedNoSlash || nk.StartsWith(normalized);
			});

		if (!wasScanned) return null;

		var result = BuildResult(normalized);
		_cache.Set(cacheKey, result, new MemoryCacheEntryOptions()
			.SetAbsoluteExpiration(TimeSpan.FromMinutes(15))
			.AddExpirationToken(_engine.SnapshotResetToken));
		return result;
	}

	private AgeHeatmapResult BuildResult(string root)
	{
		var now = DateTime.UtcNow;
		var nodes = new List<AgeHeatmapNode>();

		var normalizedNoSlash = root.TrimEnd('/');

		// Build summary — initialize all four buckets so they always appear
		var summary = new Dictionary<string, AgeBucketSummary>
		{
			["fresh"] = new AgeBucketSummary(),
			["recent"] = new AgeBucketSummary(),
			["aging"] = new AgeBucketSummary(),
			["stale"] = new AgeBucketSummary()
		};

		if (_cacheService != null)
		{
			var cachedNodes = _cacheService.GetNodesUnderRoot(root).ToList();
			if (cachedNodes.Count > 0)
			{
				foreach (var node in cachedNodes)
				{
					long directSize = node.OwnBytes;
					int directCount = node.Files.Count;
					DateTime lastModified = node.Files.Count > 0
						? node.Files.Max(f => f.LastModifiedUtc)
						: node.CachedAt.UtcDateTime;

					var bucketName = ClassifyAge(lastModified, now);

					nodes.Add(new AgeHeatmapNode
					{
						Path = node.Path.Replace("\\", "/"),
						SizeBytes = directSize,
						AgeBucket = bucketName,
						LastModified = lastModified
					});

					var bucket = summary[bucketName];
					bucket.Count += directCount;
					bucket.TotalBytes += directSize;
				}

				return new AgeHeatmapResult
				{
					Root = root.TrimEnd('/'),
					Nodes = nodes,
					Summary = summary
				};
			}
		}

		// Fallback: Walk every cached directory under this root — normalize keys before comparing
		var cachedDirs = _engine.DirectorySizeCache
			.Where(kvp =>
			{
				var nk = NormalizeKey(kvp.Key);
				return nk == normalizedNoSlash || nk.StartsWith(root);
			});

		foreach (var kvp in cachedDirs)
		{
			var entry = kvp.Value;

			// Calculate non-recursive size and file count to prevent double-counting descendants
			long directSize = entry.Extensions?.Sum(e => e.Value.Bytes) ?? 0;
			int directCount = entry.Extensions?.Sum(e => e.Value.Count) ?? 0;

			var bucketName = ClassifyAge(entry.LastUpdated, now);

			// Use the cached LastUpdated timestamp directly — no filesystem access
			nodes.Add(new AgeHeatmapNode
			{
				Path = kvp.Key.Replace("\\", "/"),
				SizeBytes = directSize,
				AgeBucket = bucketName,
				LastModified = entry.LastUpdated
			});

			var bucket = summary[bucketName];
			bucket.Count += directCount; // Number of files
			bucket.TotalBytes += directSize; // Non-recursive size
		}

		return new AgeHeatmapResult
		{
			Root = root.TrimEnd('/'),
			Nodes = nodes,
			Summary = summary
		};
	}

	/// <summary>
	/// Classify a timestamp into one of four age buckets relative to the current UTC time.
	/// </summary>
	private static string ClassifyAge(DateTime lastModified, DateTime now)
	{
		var age = now - lastModified;

		return age.TotalDays switch
		{
			< 7 => "fresh",
			< 30 => "recent",
			< 365 => "aging",
			_ => "stale"
		};
	}

	/// <summary>
	/// Normalizes a root path to a canonical format: forward slashes, lowercase, trailing slash.
	/// Example: "C:\Users\Foo" → "c:/users/foo/"
	/// </summary>
	private static string NormalizeRoot(string root)
	{
		var fullPath = Path.GetFullPath(root);
		var canonical = fullPath.Replace("\\", "/").ToLowerInvariant();
		if (!canonical.EndsWith('/'))
			canonical += '/';
		return canonical;
	}

	/// <summary>
	/// Normalizes a cache key to the same canonical format used by NormalizeRoot (without trailing slash).
	/// </summary>
	private static string NormalizeKey(string key)
	{
		return key.Replace("\\", "/").ToLowerInvariant().TrimEnd('/');
	}
}

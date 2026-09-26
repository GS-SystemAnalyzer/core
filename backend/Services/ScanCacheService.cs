using System.Collections.Concurrent;
using System.IO;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services;

/// <summary>
/// Fine-grained, node-keyed directory cache service.
/// Provides two-tiered caching (roots and nodes), lazy recursive size roll-up,
/// 500ms debounced targeted watcher invalidations, prefix eviction, and stampede protection.
/// </summary>
public class ScanCacheService : IScanCacheService, IDisposable
{
	private readonly ISettingService _settings;
	private readonly ILogger<ScanCacheService> _logger;

	private IMemoryCache _memoryCache;
	private readonly object _cacheRebuildLock = new();

	// Root metadata map: normalized root -> ScanRootMeta
	private readonly ConcurrentDictionary<string, ScanRootMeta> _rootMetas = new(StringComparer.OrdinalIgnoreCase);

	// Side index: parent path -> direct child paths
	private readonly ConcurrentDictionary<string, HashSet<string>> _parentToChildren = new(StringComparer.OrdinalIgnoreCase);
	private readonly object _parentIndexLock = new();

	// Node tracking: path -> CachedAt timestamp (for TTL shortening pruning & stats)
	private readonly ConcurrentDictionary<string, DateTimeOffset> _nodeCachedTimes = new(StringComparer.OrdinalIgnoreCase);

	// Node tracking: path -> Root
	private readonly ConcurrentDictionary<string, string> _nodeToRoot = new(StringComparer.OrdinalIgnoreCase);

	// Node tracking: path -> OwnBytes (for fast approximate bytes calculation)
	private readonly ConcurrentDictionary<string, long> _nodeOwnBytes = new(StringComparer.OrdinalIgnoreCase);

	// Stampede protection: per-node locks
	private readonly ConcurrentDictionary<string, SemaphoreSlim> _nodeLocks = new(StringComparer.OrdinalIgnoreCase);

	// Watcher debounce: (path, changeType) -> token
	private readonly ConcurrentDictionary<string, CancellationTokenSource> _debounceTokens = new(StringComparer.OrdinalIgnoreCase);

	// Hit / Miss metrics
	private long _hitCount;
	private long _missCount;

	public event EventHandler<string>? OnSubtreeInvalidated;

	public ScanCacheService(ISettingService settings, ILogger<ScanCacheService> logger)
	{
		_settings = settings;
		_logger = logger;

		_memoryCache = CreateMemoryCache(_settings.Current.Cache.MaxCachedNodes);

		_settings.OnSettingsChanged += HandleSettingsChanged;
	}

	private static IMemoryCache CreateMemoryCache(int maxNodes)
	{
		var options = new MemoryCacheOptions
		{
			SizeLimit = Math.Max(1000, maxNodes)
		};
		return new MemoryCache(options);
	}

	#region Key Generation & Normalization

	public static string NormalizePath(string path)
	{
		if (string.IsNullOrWhiteSpace(path)) return string.Empty;
		try
		{
			var full = Path.GetFullPath(path);
			var root = Path.GetPathRoot(full);
			if (!string.IsNullOrEmpty(root) && full.Equals(root, StringComparison.OrdinalIgnoreCase))
			{
				return root;
			}
			return full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
		}
		catch
		{
			return path.TrimEnd('/', '\\');
		}
	}

	public static string NormalizeRoot(string root)
	{
		if (string.IsNullOrWhiteSpace(root)) return string.Empty;
		try
		{
			var full = Path.GetFullPath(root);
			var pathRoot = Path.GetPathRoot(full);
			return !string.IsNullOrEmpty(pathRoot) ? pathRoot : (full.EndsWith('\\') ? full : full + "\\");
		}
		catch
		{
			return root.EndsWith('\\') || root.EndsWith('/') ? root : root + "\\";
		}
	}

	private static string NodeKey(string path) => $"scan:node:{NormalizePath(path)}";
	private static string RootKey(string root, int depth) => $"scan:root:{NormalizeRoot(root)}:{depth}";

	#endregion

	#region Node Operations

	public CachedDirNode? GetNode(string path)
	{
		TryGetNode(path, out var node);
		return node;
	}

	public bool TryGetNode(string path, out CachedDirNode? node)
	{
		var key = NodeKey(path);
		if (_memoryCache.TryGetValue(key, out CachedDirNode? cached) && cached != null)
		{
			Interlocked.Increment(ref _hitCount);
			node = cached;
			return true;
		}

		Interlocked.Increment(ref _missCount);
		node = null;
		return false;
	}

	public void SetNode(CachedDirNode node, string? scanRoot = null)
	{
		var normPath = NormalizePath(node.Path);
		var key = NodeKey(normPath);
		var ttlMinutes = Math.Max(1, _settings.Current.Cache.ScanCacheTtlMinutes);

		var resolvedRoot = scanRoot != null ? NormalizeRoot(scanRoot) : ResolveRootForPath(normPath);

		var entryOptions = new MemoryCacheEntryOptions
		{
			AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(ttlMinutes),
			Size = Math.Max(1, 1 + node.Files.Count)
		};

		entryOptions.RegisterPostEvictionCallback((k, v, reason, state) =>
		{
			if (k is string keyStr && keyStr.StartsWith("scan:node:"))
			{
				var evictedPath = keyStr.Substring("scan:node:".Length);
				_nodeCachedTimes.TryRemove(evictedPath, out _);
				_nodeToRoot.TryRemove(evictedPath, out _);
				_nodeOwnBytes.TryRemove(evictedPath, out _);

				var parent = GetParentPath(evictedPath);
				if (!string.IsNullOrEmpty(parent))
				{
					lock (_parentIndexLock)
					{
						if (_parentToChildren.TryGetValue(parent, out var set))
						{
							set.Remove(evictedPath);
						}
					}
				}
			}
		});

		_memoryCache.Set(key, node, entryOptions);

		_nodeCachedTimes[normPath] = node.CachedAt;
		_nodeToRoot[normPath] = resolvedRoot;
		_nodeOwnBytes[normPath] = node.OwnBytes;

		var parentPath = GetParentPath(normPath);
		if (!string.IsNullOrEmpty(parentPath))
		{
			lock (_parentIndexLock)
			{
				var set = _parentToChildren.GetOrAdd(parentPath, _ => new HashSet<string>(StringComparer.OrdinalIgnoreCase));
				set.Add(normPath);
			}
		}
	}

	public async Task<CachedDirNode?> GetOrAddNodeAsync(
		string path,
		Func<string, CancellationToken, Task<CachedDirNode>> factory,
		string? scanRoot = null,
		CancellationToken ct = default)
	{
		var normPath = NormalizePath(path);
		if (TryGetNode(normPath, out var existing) && existing != null)
		{
			return existing;
		}

		var sem = _nodeLocks.GetOrAdd(normPath, _ => new SemaphoreSlim(1, 1));
		await sem.WaitAsync(ct);
		try
		{
			// Double check after lock acquisition
			if (TryGetNode(normPath, out var doubleChecked) && doubleChecked != null)
			{
				return doubleChecked;
			}

			var created = await factory(normPath, ct);
			if (created != null)
			{
				SetNode(created, scanRoot);
			}
			return created;
		}
		finally
		{
			sem.Release();
		}
	}

	#endregion

	#region Recursive Bytes Roll-Up & Ancestor Staleness

	public long GetOrRecomputeRecursiveBytes(string path)
	{
		var normPath = NormalizePath(path);
		if (!TryGetNode(normPath, out var node) || node == null)
		{
			return 0;
		}

		if (!node.RecursiveBytesStale)
		{
			return node.RecursiveBytes;
		}

		// Recompute lazily by traversing only stale children
		long sum = node.OwnBytes;
		foreach (var childPath in node.ChildDirectoryPaths)
		{
			sum += GetOrRecomputeRecursiveBytes(childPath);
		}

		var updated = node with
		{
			RecursiveBytes = sum,
			RecursiveBytesStale = false
		};

		SetNode(updated, _nodeToRoot.TryGetValue(normPath, out var r) ? r : null);
		return sum;
	}

	public void MarkAncestorsStale(string path)
	{
		var current = GetParentPath(NormalizePath(path));
		var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

		while (!string.IsNullOrEmpty(current) && visited.Add(current))
		{
			if (TryGetNode(current, out var ancestor) && ancestor != null)
			{
				if (!ancestor.RecursiveBytesStale)
				{
					var updated = ancestor with { RecursiveBytesStale = true };
					SetNode(updated, _nodeToRoot.TryGetValue(current, out var r) ? r : null);
				}
			}

			var next = GetParentPath(current);
			if (string.IsNullOrEmpty(next) || next.Equals(current, StringComparison.OrdinalIgnoreCase)) break;
			current = next;
		}
	}

	#endregion

	#region Root Operations & 409 Contract

	public bool HasScanRoot(string root)
	{
		var normRoot = NormalizeRoot(root);
		return _rootMetas.Keys.Any(k => k.StartsWith(normRoot, StringComparison.OrdinalIgnoreCase));
	}

	public ScanRootMeta? GetScanRoot(string root, int? depth = null)
	{
		var normRoot = NormalizeRoot(root);
		if (depth.HasValue)
		{
			var exactKey = $"{normRoot}:{depth.Value}";
			return _rootMetas.TryGetValue(exactKey, out var meta) ? meta : null;
		}

		// Find most recent for root
		return _rootMetas
			.Where(kvp => kvp.Key.StartsWith(normRoot, StringComparison.OrdinalIgnoreCase))
			.Select(kvp => kvp.Value)
			.OrderByDescending(m => m.ScannedAt)
			.FirstOrDefault();
	}

	public void SetScanRoot(ScanRootMeta rootMeta)
	{
		var normRoot = NormalizeRoot(rootMeta.DriveRoot);
		var key = $"{normRoot}:{rootMeta.Depth}";
		_rootMetas[key] = rootMeta;

		// Also register in memory cache for stats and eviction hooks
		var cacheKey = RootKey(normRoot, rootMeta.Depth);
		_memoryCache.Set(cacheKey, rootMeta, new MemoryCacheEntryOptions
		{
			AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(_settings.Current.Cache.ScanCacheTtlMinutes),
			Size = 1
		});
	}

	public IEnumerable<ScanRootMeta> GetAllScanRoots() => _rootMetas.Values;

	public IEnumerable<CachedDirNode> GetNodesUnderRoot(string root)
	{
		var normRoot = NormalizeRoot(root);
		var list = new List<CachedDirNode>();

		foreach (var kvp in _nodeToRoot)
		{
			if (kvp.Value.Equals(normRoot, StringComparison.OrdinalIgnoreCase) ||
				kvp.Key.StartsWith(normRoot, StringComparison.OrdinalIgnoreCase))
			{
				if (TryGetNode(kvp.Key, out var node) && node != null)
				{
					list.Add(node);
				}
			}
		}

		return list;
	}

	#endregion

	#region Targeted Invalidation & Watcher Handling

	public void InvalidatePath(string path, bool isDirectory)
	{
		var normPath = NormalizePath(path);
		if (isDirectory)
		{
			InvalidatePrefix(normPath);
		}
		else
		{
			var parent = GetParentPath(normPath);
			if (!string.IsNullOrEmpty(parent))
			{
				_memoryCache.Remove(NodeKey(parent));
				_nodeCachedTimes.TryRemove(parent, out _);
				_nodeToRoot.TryRemove(parent, out _);
				_nodeOwnBytes.TryRemove(parent, out _);
				MarkAncestorsStale(parent);
			}
		}

		var root = ResolveRootForPath(normPath);
		OnSubtreeInvalidated?.Invoke(this, root);
	}

	public void InvalidatePrefix(string directoryPath)
	{
		var normPath = NormalizePath(directoryPath);
		var nodesToEvict = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

		// Collect descendants via BFS through side index
		var queue = new Queue<string>();
		queue.Enqueue(normPath);

		while (queue.Count > 0)
		{
			var curr = queue.Dequeue();
			nodesToEvict.Add(curr);

			lock (_parentIndexLock)
			{
				if (_parentToChildren.TryRemove(curr, out var children))
				{
					foreach (var child in children)
					{
						queue.Enqueue(child);
					}
				}
			}
		}

		// Also find any orphaned prefix matches in node tracking
		var prefix = normPath + Path.DirectorySeparatorChar;
		foreach (var key in _nodeCachedTimes.Keys)
		{
			if (key.Equals(normPath, StringComparison.OrdinalIgnoreCase) ||
				key.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
			{
				nodesToEvict.Add(key);
			}
		}

		foreach (var nodePath in nodesToEvict)
		{
			_memoryCache.Remove(NodeKey(nodePath));
			_nodeCachedTimes.TryRemove(nodePath, out _);
			_nodeToRoot.TryRemove(nodePath, out _);
			_nodeOwnBytes.TryRemove(nodePath, out _);
		}

		// Mark ancestors stale
		MarkAncestorsStale(normPath);

		var root = ResolveRootForPath(normPath);
		OnSubtreeInvalidated?.Invoke(this, root);
	}

	public void InvalidatePaths(IEnumerable<string> paths)
	{
		foreach (var p in paths)
		{
			if (string.IsNullOrWhiteSpace(p)) continue;
			InvalidatePrefix(p);
		}
	}

	public void InvalidateSubtree(string rootPath)
	{
		var normRoot = NormalizeRoot(rootPath);
		var nodesUnderRoot = _nodeToRoot
			.Where(kvp => kvp.Value.Equals(normRoot, StringComparison.OrdinalIgnoreCase) ||
						  kvp.Key.StartsWith(normRoot, StringComparison.OrdinalIgnoreCase))
			.Select(kvp => kvp.Key)
			.ToList();

		foreach (var n in nodesUnderRoot)
		{
			_memoryCache.Remove(NodeKey(n));
			_nodeCachedTimes.TryRemove(n, out _);
			_nodeToRoot.TryRemove(n, out _);
			_nodeOwnBytes.TryRemove(n, out _);
		}

		lock (_parentIndexLock)
		{
			var keysToRemove = _parentToChildren.Keys
				.Where(k => k.StartsWith(normRoot, StringComparison.OrdinalIgnoreCase))
				.ToList();
			foreach (var k in keysToRemove)
			{
				_parentToChildren.TryRemove(k, out _);
			}
		}

		OnSubtreeInvalidated?.Invoke(this, normRoot);
	}

	public void HandleWatcherEvent(string fullPath, WatcherChangeTypes changeType)
	{
		if (IsAppInternalPath(fullPath)) return;

		var key = $"{fullPath}:{changeType}";
		var cts = new CancellationTokenSource();

		_debounceTokens.AddOrUpdate(
			key,
			cts,
			(_, oldCts) =>
			{
				try { oldCts.Cancel(); } catch { }
				return cts;
			});

		_ = Task.Run(async () =>
		{
			try
			{
				await Task.Delay(500, cts.Token);
				if (cts.Token.IsCancellationRequested) return;

				_debounceTokens.TryRemove(new KeyValuePair<string, CancellationTokenSource>(key, cts));

				switch (changeType)
				{
					case WatcherChangeTypes.Deleted:
						InvalidatePrefix(fullPath);
						break;
					case WatcherChangeTypes.Created:
					case WatcherChangeTypes.Changed:
					case WatcherChangeTypes.Renamed:
					default:
						var parent = GetParentPath(fullPath);
						if (!string.IsNullOrEmpty(parent))
						{
							InvalidatePrefix(parent);
						}
						else
						{
							InvalidatePath(fullPath, isDirectory: false);
						}
						break;
				}
			}
			catch (OperationCanceledException) { }
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Error processing debounced watcher event for {Path}", fullPath);
			}
			finally
			{
				cts.Dispose();
			}
		});
	}

	public void HandleWatcherOverflow(string watchedRoot)
	{
		_logger.LogWarning("FileSystemWatcher buffer overflowed for root {Root}. Invalidating cached subtree.", watchedRoot);
		InvalidateSubtree(watchedRoot);
	}

	// internal so DiskScannerEngine's watcher filters on the same list; a second, narrower
	// copy there would let the app's own writes re-trigger a scan.
	internal static bool IsAppInternalPath(string path)
	{
		if (string.IsNullOrWhiteSpace(path)) return true;
		var lower = path.ToLowerInvariant();
		return lower.EndsWith("appsettings.user.json") ||
			   lower.Contains("scan_snapshots") ||
			   lower.EndsWith("scheduled_scans.json") ||
			   lower.EndsWith("scanner_memory.json") ||
			   lower.EndsWith(".tmp") ||
			   lower.Contains("\\.git\\") ||
			   lower.Contains("/.git/");
	}

	#endregion

	#region Eviction, Clear & Stats

	public void EvictRoot(string root)
	{
		var normRoot = NormalizeRoot(root);

		// Remove all root metadata keys starting with this root
		var rootKeys = _rootMetas.Keys.Where(k => k.StartsWith(normRoot, StringComparison.OrdinalIgnoreCase)).ToList();
		foreach (var k in rootKeys)
		{
			_rootMetas.TryRemove(k, out _);
		}

		InvalidateSubtree(normRoot);
	}

	public void Clear()
	{
		_rootMetas.Clear();
		_nodeCachedTimes.Clear();
		_nodeToRoot.Clear();
		_nodeOwnBytes.Clear();
		lock (_parentIndexLock)
		{
			_parentToChildren.Clear();
		}

		lock (_cacheRebuildLock)
		{
			_memoryCache.Dispose();
			_memoryCache = CreateMemoryCache(_settings.Current.Cache.MaxCachedNodes);
		}

		Interlocked.Exchange(ref _hitCount, 0);
		Interlocked.Exchange(ref _missCount, 0);

		OnSubtreeInvalidated?.Invoke(this, string.Empty);
	}

	public CacheStatsDto GetStats()
	{
		var nodeCount = _nodeCachedTimes.Count;
		var rootCount = _rootMetas.Count;
		var totalEntries = nodeCount + rootCount;
		var approximateBytes = _nodeOwnBytes.Values.Sum();

		var hits = Interlocked.Read(ref _hitCount);
		var misses = Interlocked.Read(ref _missCount);
		var totalRequests = hits + misses;
		var ratio = totalRequests > 0 ? Math.Round((double)hits / totalRequests, 4) : 0.0;

		DateTimeOffset? oldest = _nodeCachedTimes.Values.Any()
			? _nodeCachedTimes.Values.Min()
			: null;

		return new CacheStatsDto(
			EntryCount: totalEntries,
			NodeCount: nodeCount,
			RootCount: rootCount,
			ApproximateBytes: approximateBytes,
			HitCount: hits,
			MissCount: misses,
			HitMissRatio: ratio,
			OldestCachedAt: oldest
		);
	}

	#endregion

	#region Settings & Reactivity

	private void HandleSettingsChanged(object? sender, AppSettingDto newSettings)
	{
		try
		{
			// Check if TTL shortened
			var ttlMinutes = newSettings.Cache.ScanCacheTtlMinutes;
			var cutoff = DateTimeOffset.UtcNow.AddMinutes(-ttlMinutes);

			var expiredNodes = _nodeCachedTimes
				.Where(kvp => kvp.Value < cutoff)
				.Select(kvp => kvp.Key)
				.ToList();

			foreach (var path in expiredNodes)
			{
				_memoryCache.Remove(NodeKey(path));
				_nodeCachedTimes.TryRemove(path, out _);
				_nodeToRoot.TryRemove(path, out _);
				_nodeOwnBytes.TryRemove(path, out _);
			}

			if (expiredNodes.Count > 0)
			{
				_logger.LogInformation("Pruned {Count} nodes due to TTL shortening to {Ttl} minutes", expiredNodes.Count, ttlMinutes);
			}
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Error reacting to settings changed in ScanCacheService");
		}
	}

	#endregion

	#region Helper Methods

	private static string GetParentPath(string path)
	{
		if (string.IsNullOrWhiteSpace(path)) return string.Empty;
		try
		{
			var norm = NormalizePath(path);
			var root = Path.GetPathRoot(norm);
			if (!string.IsNullOrEmpty(root) && (norm.Equals(root, StringComparison.OrdinalIgnoreCase) || norm.Equals(root.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase)))
			{
				return string.Empty;
			}

			var dir = Path.GetDirectoryName(norm);
			if (string.IsNullOrEmpty(dir)) return string.Empty;

			var normDir = NormalizePath(dir);
			if (normDir.Equals(norm, StringComparison.OrdinalIgnoreCase)) return string.Empty;
			return normDir;
		}
		catch
		{
			return string.Empty;
		}
	}

	private static string ResolveRootForPath(string path)
	{
		try
		{
			var root = Path.GetPathRoot(NormalizePath(path));
			return string.IsNullOrEmpty(root) ? "C:\\" : NormalizeRoot(root);
		}
		catch
		{
			return "C:\\";
		}
	}

	public void Dispose()
	{
		_settings.OnSettingsChanged -= HandleSettingsChanged;
		foreach (var cts in _debounceTokens.Values)
		{
			try { cts.Cancel(); cts.Dispose(); } catch { }
		}
		_debounceTokens.Clear();
		_memoryCache.Dispose();
	}

	#endregion
}

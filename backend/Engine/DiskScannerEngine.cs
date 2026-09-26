using System.Collections.Concurrent;
using System.Runtime;
using System.Text.Json;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Primitives;

namespace GSSystemAnalyzer.Engine;

public class CacheEntry
{
	public long Size { get; set; }

	public DateTime LastUpdated { get; set; }
	public DateTime CachedAtUtc { get; set; }
	public string? ScanRoot { get; set; }

	public Dictionary<string, FileTypeEntry>? Extensions { get; set; }
}


public class DiskScannerEngine : IDiskScannerEngine, IDisposable
{
	public ConcurrentDictionary<string, CacheEntry> DirectorySizeCache = new(StringComparer.OrdinalIgnoreCase);
	private CancellationTokenSource? _nukeCts;

	// Cancelling this evicts every analyzer snapshot that registered SnapshotResetToken.
	// A token, not _cache.Clear(), because ScanDiffService shares that IMemoryCache (Program.cs:25).
	private CancellationTokenSource _snapshotResetCts = new();
	private readonly object _snapshotTokenLock = new object();

	/// <summary>Expiration token for cached analyzer snapshots. Read a fresh one per cache entry:
	/// the source is replaced on every reset, so an earlier token is already spent.</summary>
	public IChangeToken SnapshotResetToken
	{
		get
		{
			lock (_snapshotTokenLock)
			{
				return new CancellationChangeToken(_snapshotResetCts.Token);
			}
		}
	}

	/// <summary>Evicts every analyzer snapshot that registered <see cref="SnapshotResetToken"/>.</summary>
	private void ResetAnalyzerSnapshots()
	{
		CancellationTokenSource spent;
		lock (_snapshotTokenLock)
		{
			spent = _snapshotResetCts;
			_snapshotResetCts = new CancellationTokenSource();
		}

		// Cancelled outside the lock: MemoryCache fires eviction callbacks inside Cancel(), and one
		// reading SnapshotResetToken on another thread would block on a lock held here.
		try { spent.Cancel(); } catch (ObjectDisposedException) { /* already reset */ }
		spent.Dispose();
	}
	private readonly ConcurrentDictionary<Guid, ScanSession> _activeSessions = new();
	private readonly SemaphoreSlim _scanLock = new SemaphoreSlim(1, 1);

	/// <summary>True when a scan is actively running (the scan semaphore is held).</summary>
	public bool IsScanning => _scanLock.CurrentCount == 0;

	private readonly object _fileWriteLock = new object();
	private int _deepScanThrottle = 0;
	private readonly string _cacheFilePath = Path.Combine(
		Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
		"GSAnalyzer", "scanner_memory.json");
	private FileSystemWatcher? _liveRader;
	private readonly object _radarLock = new object();
	private const int MaxRadarViewDepth = 2;
	private static readonly string[] _highChurnSegments =
	[
		@"\windows\prefetch\",
		@"\programdata\microsoft\search\",
		@"\appdata\local\packages\",
		@"\$recycle.bin\",
		@"\system volume information\"
	];

	// Bursts coalesce within 1000ms; cooldown limits broadcasts to once per 5000ms to stop
	// rescan loops on busy drive roots like C:/.
	private readonly TimeSpan _radarDebounce = TimeSpan.FromMilliseconds(1000);
	private readonly TimeSpan _radarBurstCap = TimeSpan.FromMilliseconds(1000);
	private readonly TimeSpan _radarCooldown = TimeSpan.FromMilliseconds(5000);
	private DateTime _lastRadarBroadcastUtc = DateTime.MinValue;
	private string? _radarTargetPath;
	private CancellationTokenSource? _radarDebounceCts;
	private DateTime _radarBurstStartedUtc = DateTime.MinValue;
	private bool _disposed;
	private readonly ISettingService _settings;
	private readonly IHubContext<SystemHub> _hub;
	private readonly ILogger<DiskScannerEngine> _logger;
	private readonly IScanCacheService? _cacheService;
	private readonly IWatcherEventLogService? _watcherLog;
	private int _scannedFilesCount = 0;

	public DiskScannerEngine(IHubContext<SystemHub> hub, ISettingService settings, ILogger<DiskScannerEngine> logger, IScanCacheService? cacheService = null, IWatcherEventLogService? watcherLog = null)
	{
		_hub = hub;
		_settings = settings;
		_logger = logger;
		_cacheService = cacheService;
		_watcherLog = watcherLog;
		if (File.Exists(_cacheFilePath))
		{
			try
			{
				var json = File.ReadAllText(_cacheFilePath);

				var savedMemory = JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(json);

				if (savedMemory != null)
				{
					DirectorySizeCache = new ConcurrentDictionary<string, CacheEntry>(savedMemory);
					_logger.LogInformation("Cache restored: {Count} folders loaded from disk", DirectorySizeCache.Count);

					PruneStaleCacheEntries();
					EnforceMaxCacheScans();

					if (_cacheService != null)
					{
						HydrateScanCacheService(savedMemory);
					}
				}
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Cache file corrupted, starting fresh");
				try { File.Delete(_cacheFilePath); } catch { /* best effort */ }
			}
		}
	}

	public void HydrateScanCacheService(IDictionary<string, CacheEntry> savedMemory)
	{
		try
		{
			var parentToChildren = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
			foreach (var path in savedMemory.Keys)
			{
				try
				{
					var parent = Path.GetDirectoryName(path);
					if (!string.IsNullOrEmpty(parent))
					{
						if (!parentToChildren.TryGetValue(parent, out var children))
						{
							children = new List<string>();
							parentToChildren[parent] = children;
						}
						children.Add(path);
					}
				}
				catch { }
			}

			foreach (var (path, entry) in savedMemory)
			{
				parentToChildren.TryGetValue(path, out var childList);
				var dirNode = new CachedDirNode(
					Path: path,
					ChildDirectoryPaths: childList ?? (IReadOnlyList<string>)Array.Empty<string>(),
					Files: Array.Empty<CachedFileEntry>(),
					OwnBytes: entry.Size,
					RecursiveBytes: entry.Size,
					CachedAt: entry.CachedAtUtc != default ? entry.CachedAtUtc : DateTimeOffset.UtcNow,
					RecursiveBytesStale: false
				);
				_cacheService?.SetNode(dirNode, entry.ScanRoot ?? path);
			}

			var scanRoots = savedMemory.Values
				.Select(v => v.ScanRoot)
				.Where(r => !string.IsNullOrEmpty(r))
				.Distinct(StringComparer.OrdinalIgnoreCase);

			foreach (var root in scanRoots)
			{
				if (root != null)
				{
					var rootMeta = new ScanRootMeta(
						DriveRoot: root,
						Depth: _settings.Current.Scan.Depth,
						ScannedAt: DateTimeOffset.UtcNow,
						TotalBytes: savedMemory.TryGetValue(root, out var rootEntry) ? rootEntry.Size : 0,
						TotalFiles: 0,
						RootNodeKey: ScanCacheService.NormalizePath(root)
					);
					_cacheService?.SetScanRoot(rootMeta);
				}
			}
		}
		catch (Exception ex)
		{
			_logger.LogWarning(ex, "Error while hydrating ScanCacheService from disk memory");
		}
	}

	public List<FileSystemInfo> LoadDirectoryItems(string path)
	{
		var items = new List<FileSystemInfo>();

		if (string.IsNullOrWhiteSpace(path))
		{
			_logger.LogDebug("LoadDirectoryItems called with empty path");
			return items;
		}

		MoveRadarToSector(path);

		try
		{
			// FIX: hidden/System filter is logically wrong(Should be two separate Check)
			var dirInfo = new DirectoryInfo(path);
			items.AddRange(dirInfo.GetDirectories().Where(d => !d.Attributes.HasFlag(FileAttributes.Hidden | FileAttributes.System)));
			items.AddRange(dirInfo.GetFiles().Where(f => !f.Attributes.HasFlag(FileAttributes.Hidden | FileAttributes.System)));
		}
		catch (UnauthorizedAccessException ex)
		{
			_logger.LogDebug(ex, "Access denied while listing {Path}", path);
		}

		return items;
	}

	public async Task CalculateMissingSizesAsync(List<FileSystemInfo> items, Guid scanId)
	{
		await _scanLock.WaitAsync();
		try
		{
			var directoriesToScan = items.OfType<DirectoryInfo>()
				.Where(d => !DirectorySizeCache.ContainsKey(d.FullName) || (_cacheService != null && !_cacheService.TryGetNode(d.FullName, out _)))
				.ToList();

			var totalNodes = directoriesToScan.Count;

			if (totalNodes > 0)
			{
				var completedNode = 0;
				_deepScanThrottle = 0;
				_scannedFilesCount = 0;

				// The top-level path being scanned (parent of the scanned items). Every
				// folder cached during this scan is tagged with this root so MaxCacheScans
				// can evict whole scans, not individual folders.
				var scanRoot = directoriesToScan
					.Select(d => d.Parent?.FullName)
					.FirstOrDefault(p => !string.IsNullOrEmpty(p))
					?? directoriesToScan[0].FullName;

				// Retrieve the specific session's token
				var scanToken = _activeSessions.TryGetValue(scanId, out var session) ? session.Cts.Token : CancellationToken.None;

				await _hub.Clients.All.SendAsync("ScanProgress", new { scanId = scanId, status = "INITIALIZING", count = 0, currentTarget = "Walking up the Engine...." });

				var options = new ParallelOptions
				{
					CancellationToken = scanToken,
					MaxDegreeOfParallelism = Math.Max(1, Environment.ProcessorCount / 2)
				};

				try
				{
					await Parallel.ForEachAsync(directoriesToScan, options, async (dir, ct) =>
					{
						try
						{
							var size = await Task.Run(() => GetDirectorySize(dir, ct, scanRoot), ct);

							DirectorySizeCache.TryGetValue(dir.FullName, out var existingEntry);
							DirectorySizeCache[dir.FullName] = new CacheEntry
							{
								Size = size,
								LastUpdated = dir.LastWriteTimeUtc,
								CachedAtUtc = DateTime.UtcNow,
								ScanRoot = scanRoot,
								Extensions = existingEntry?.Extensions
							};
						}
						catch (OperationCanceledException)
						{
							return;
						}

						var completed = Interlocked.Increment(ref completedNode);
						var percentage = Math.Round(((double)completed / totalNodes) * 100, 1);

						_ = _hub.Clients.All.SendAsync("ScanProgress", new
						{
							scanId = scanId,
							completed = completed,
							total = totalNodes,
							percentageComplete = percentage,
							currentTarget = dir.Name
						});
					});

					// TTL expiry (now based on real scan time) + cap to N most-recent scans.
					PruneStaleCacheEntries();
					EnforceMaxCacheScans();

					SaveMemoryToDisk();

					var rootNodeKey = ScanCacheService.NormalizePath(scanRoot);
					var rootMeta = new ScanRootMeta(
						DriveRoot: scanRoot,
						Depth: _settings.Current.Scan.Depth,
						ScannedAt: DateTimeOffset.UtcNow,
						TotalBytes: DirectorySizeCache.TryGetValue(scanRoot, out var rootEntry) ? rootEntry.Size : _scannedFilesCount,
						TotalFiles: _scannedFilesCount,
						RootNodeKey: rootNodeKey
					);
					_cacheService?.SetScanRoot(rootMeta);

					await _hub.Clients.All.SendAsync("ScanProgress", new { scanId = scanId, status = "COMPLETED", count = _scannedFilesCount, currentTarget = "Scan completed" });
				}
				catch (OperationCanceledException)
				{
					_logger.LogInformation("Scan {ScanId} was canceled by user.", scanId);
					await _hub.Clients.All.SendAsync("ScanProgress", new { scanId = scanId, status = "CANCELED", count = _scannedFilesCount, currentTarget = "Scan canceled" });
					throw;
				}
			}
		}
		finally
		{
			_scanLock.Release();
		}

	}

	private long GetDirectorySize(DirectoryInfo dir, CancellationToken token, string scanRoot, int currentDepth = 1)
	{
		token.ThrowIfCancellationRequested();

		var config = _settings.Current.Scan;

		if (currentDepth > config.Depth) return 0;

		var normalizedPath = dir.FullName.Replace("\\", "/");
		if (config.ExcludedPaths.Any(p =>
				normalizedPath.StartsWith(p, StringComparison.OrdinalIgnoreCase)))
			return 0;


		// Fix: The directory LastWriteTimeUts  only changes when its direct children are modified, so we need to check the LastWriteTimeUtc of the directory and its children to determine if the cache is stale.
		if (DirectorySizeCache.TryGetValue(dir.FullName, out var entry))
		{
			if (dir.LastWriteTimeUtc <= entry.LastUpdated)
			{
				if (_cacheService != null && !_cacheService.TryGetNode(dir.FullName, out _))
				{
					var cachedNode = new CachedDirNode(
						Path: dir.FullName,
						ChildDirectoryPaths: Array.Empty<string>(),
						Files: Array.Empty<CachedFileEntry>(),
						OwnBytes: entry.Size,
						RecursiveBytes: entry.Size,
						CachedAt: entry.CachedAtUtc != default ? entry.CachedAtUtc : DateTimeOffset.UtcNow,
						RecursiveBytesStale: false
					);
					_cacheService.SetNode(cachedNode, scanRoot);
				}
				return entry.Size;
			}

			_logger.LogDebug("Cache stale for directory, rescanning");
		}

		long size = 0;
		var extMap = new Dictionary<string, FileTypeEntry>(StringComparer.OrdinalIgnoreCase);

		try
		{
			var option = new EnumerationOptions
			{
				IgnoreInaccessible = true,
				AttributesToSkip = 0
			};

			if (config.SkipHiddenFiles) option.AttributesToSkip |= FileAttributes.Hidden;
			if (config.SkipSystemFiles) option.AttributesToSkip |= FileAttributes.System;

			if (!config.FollowSymlinks &&
				dir.Attributes.HasFlag(FileAttributes.ReparsePoint))
				return 0;

			// Single streaming pass: EnumerateFiles replaces a GetFiles array that was walked five times.
			// Everything the folder needs is accumulated here, or a naive swap would re-walk per use.
			long ownBytes = 0;
			int fileCount = 0;
			List<CachedFileEntry>? fileEntries = _cacheService != null ? new List<CachedFileEntry>() : null;

			foreach (var f in dir.EnumerateFiles("*", option))
			{
				var length = f.Length;
				ownBytes += length;
				fileCount++;

				var ext = f.Extension.ToLowerInvariant();
				if (string.IsNullOrEmpty(ext)) ext = "no extension";

				if (!extMap.TryGetValue(ext, out var fte))
				{
					fte = new FileTypeEntry { Count = 0, Bytes = 0, LargestFileBytes = 0, LargestFilePath = string.Empty };
					extMap[ext] = fte;
				}
				fte.Count++;
				fte.Bytes += length;

				if (length > fte.LargestFileBytes)
				{
					fte.LargestFileBytes = length;
					fte.LargestFilePath = f.FullName;
				}

				// Built inline rather than in a second pass; stays null with no cache service.
				fileEntries?.Add(new CachedFileEntry(
					f.Name,
					string.IsNullOrEmpty(f.Extension) ? "(none)" : f.Extension.ToLowerInvariant(),
					length,
					f.LastWriteTimeUtc
				));
			}

			size += ownBytes;

			var pulse = Interlocked.Increment(ref _deepScanThrottle);
			var currentCount = Interlocked.Add(ref _scannedFilesCount, fileCount);

			if (pulse % 50 == 0)
			{
				_ = _hub.Clients.All.SendAsync("ScanProgress", new
				{
					status = "SCANNING",
					count = currentCount,
					currentTarget = dir.Name
				});
			}

			var subDirs = dir.GetDirectories("*", option);
			var childPaths = new List<string>();
			foreach (var subDir in subDirs)
			{
				childPaths.Add(subDir.FullName);
				// Pass depth + 1 so each recursive level is tracked
				size += GetDirectorySize(subDir, token, scanRoot, currentDepth + 1);
			}

			// Only build the ScanCacheService payload when a cache service will consume it.
			// With none (tests, benchmark) this allocated a node + entry per file and dropped it. See D-11.
			if (_cacheService != null && fileEntries != null)
			{
				var dirNode = new CachedDirNode(
					Path: dir.FullName,
					ChildDirectoryPaths: childPaths,
					Files: fileEntries,
					OwnBytes: ownBytes,
					RecursiveBytes: size,
					CachedAt: DateTimeOffset.UtcNow,
					RecursiveBytesStale: false
				);
				_cacheService.SetNode(dirNode, scanRoot);
			}
		}
		catch (OperationCanceledException) { throw; }
		catch (Exception) { /* access denied etc — skip silently */ }

		DirectorySizeCache[dir.FullName] = new CacheEntry
		{
			Size = size,
			LastUpdated = dir.LastWriteTimeUtc,
			CachedAtUtc = DateTime.UtcNow,
			ScanRoot = scanRoot,
			Extensions = extMap
		};

		return size;
	}

	public void SaveMemoryToDisk()
	{
		lock (_fileWriteLock)
		{
			try
			{
				var dir = Path.GetDirectoryName(_cacheFilePath)!;
				Directory.CreateDirectory(dir);

				var tmpPath = _cacheFilePath + ".tmp";

				// Stream straight to the file; the previous version held a dictionary copy plus the
				// whole JSON string, which lands on the LOH. Written via IDictionary so the shape is unchanged.
				using (var stream = new FileStream(tmpPath, FileMode.Create, FileAccess.Write, FileShare.None))
				{
					JsonSerializer.Serialize<IDictionary<string, CacheEntry>>(stream, DirectorySizeCache);
				}

				// Atomic swap — readers see either the old file or the new one, never a stump.
				File.Move(tmpPath, _cacheFilePath, overwrite: true);
			}
			catch (Exception ex)
			{
				_logger.LogError(ex, "Failed to save cache to disk");
			}
		}
	}

	public void MoveRadarToSector(string targetPath)
	{
		lock (_radarLock)
		{
			if (_disposed) return;

			try
			{
				StopRadarLocked();

				if (Directory.Exists(targetPath))
				{
					_radarTargetPath = targetPath;
					_liveRader = new FileSystemWatcher(targetPath);

					_liveRader.IncludeSubdirectories = true;

					_liveRader.NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.Size;
					_liveRader.InternalBufferSize = 65536;

					_liveRader.Created += OnRadarTriggered;
					_liveRader.Deleted += OnRadarTriggered;
					_liveRader.Renamed += OnRadarTriggered;
					_liveRader.Changed += OnRadarTriggered;
					_liveRader.Error += OnRadarError;

					_liveRader.EnableRaisingEvents = true;
					_logger.LogInformation("File system watcher active on {Path}", targetPath);
				}
			}
			catch (Exception ex)
			{
				StopRadarLocked();
				_logger.LogWarning(ex, "Failed to deploy file system watcher on {Path}", targetPath);
			}
		}
	}

	// Cancels any pending broadcast and detaches every handler before disposing, so a
	// retired watcher cannot deliver an event against the new sector.
	private void StopRadarLocked()
	{
		_radarDebounceCts?.Cancel();
		_radarDebounceCts?.Dispose();
		_radarDebounceCts = null;
		_radarBurstStartedUtc = DateTime.MinValue;
		_lastRadarBroadcastUtc = DateTime.MinValue;
		_radarTargetPath = null;

		if (_liveRader == null) return;

		_liveRader.EnableRaisingEvents = false;
		_liveRader.Created -= OnRadarTriggered;
		_liveRader.Deleted -= OnRadarTriggered;
		_liveRader.Renamed -= OnRadarTriggered;
		_liveRader.Changed -= OnRadarTriggered;
		_liveRader.Error -= OnRadarError;
		_liveRader.Dispose();
		_liveRader = null;
	}

	public void Dispose()
	{
		lock (_radarLock)
		{
			if (_disposed) return;
			_disposed = true;
			StopRadarLocked();
		}
	}

	private void OnRadarTriggered(object sender, FileSystemEventArgs e)
	{
		// The app's own writes land inside the watched tree once subdirectories are watched,
		// so reuse the cache service's exclusion list rather than a second narrower one.
		if (ScanCacheService.IsAppInternalPath(e.FullPath)) return;

		_logger.LogDebug("File system change detected: {ChangeType} on {Name}", e.ChangeType, e.Name);
		_cacheService?.HandleWatcherEvent(e.FullPath, e.ChangeType);

		// Log to the watcher event log
		WatcherChangeKind kind = e.ChangeType switch
		{
			WatcherChangeTypes.Created => WatcherChangeKind.Created,
			WatcherChangeTypes.Deleted => WatcherChangeKind.Deleted,
			WatcherChangeTypes.Changed => WatcherChangeKind.Modified,
			WatcherChangeTypes.Renamed => WatcherChangeKind.Renamed,
			_ => WatcherChangeKind.Modified
		};
		
		string? oldPath = e is RenamedEventArgs re ? re.OldFullPath : null;
		
		bool isDirectory = false;
		try
		{
			if (e.ChangeType != WatcherChangeTypes.Deleted)
			{
				isDirectory = Directory.Exists(e.FullPath);
			}
			else if (oldPath != null)
			{
				// For rename, check the new path
				isDirectory = Directory.Exists(e.FullPath);
			}
		}
		catch { }

		_watcherLog?.LogEvent(DateTimeOffset.UtcNow, kind, e.FullPath, oldPath, isDirectory);

		// Cache invalidation and event logging are unconditional; gate only the UI broadcast
		// by view depth and system churn to prevent permanent refresh loops on drive roots.
		string? root;
		lock (_radarLock)
		{
			root = _radarTargetPath;
		}

		if (!string.IsNullOrEmpty(root) && !IsHighChurnPath(e.FullPath) && IsWithinViewDepth(root, e.FullPath))
		{
			ScheduleRadarBroadcast(sender as FileSystemWatcher);
		}
	}

	private static bool IsWithinViewDepth(string watchedRoot, string fullPath)
	{
		try
		{
			var rel = Path.GetRelativePath(watchedRoot, fullPath);
			if (rel.StartsWith("..", StringComparison.Ordinal)) return false;
			if (rel == ".") return true;
			var depth = rel.Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries).Length;
			return depth <= MaxRadarViewDepth;
		}
		catch
		{
			return false;
		}
	}

	private static bool IsHighChurnPath(string fullPath)
	{
		var norm = fullPath.Replace('/', '\\');
		if (!norm.EndsWith('\\')) norm += '\\';
		foreach (var segment in _highChurnSegments)
		{
			if (norm.Contains(segment, StringComparison.OrdinalIgnoreCase))
				return true;
		}
		return false;
	}

	// Broadcasts the watched ROOT, not the changed folder: the Flutter consumer compares the
	// payload to the open directory by exact equality, so a nested path would never match.
	private void ScheduleRadarBroadcast(FileSystemWatcher? watcher)
	{
		if (watcher == null) return;

		CancellationTokenSource? retired;
		CancellationTokenSource mine;
		DateTime burstDeadline;

		lock (_radarLock)
		{
			if (_disposed || !ReferenceEquals(watcher, _liveRader) || string.IsNullOrEmpty(_radarTargetPath)) return;

			// Cooldown rate-limits broadcasts for the same watched root to at most once per 5s.
			if (_radarDebounceCts == null && (DateTime.UtcNow - _lastRadarBroadcastUtc) < _radarCooldown)
			{
				return;
			}

			if (_radarDebounceCts == null) _radarBurstStartedUtc = DateTime.UtcNow;

			retired = _radarDebounceCts;
			mine = new CancellationTokenSource();
			_radarDebounceCts = mine;
			burstDeadline = _radarBurstStartedUtc + _radarBurstCap;
		}

		retired?.Cancel();

		_ = BroadcastRadarAsync(watcher, mine, burstDeadline);
	}

	private async Task BroadcastRadarAsync(FileSystemWatcher watcher, CancellationTokenSource cts, DateTime burstDeadline)
	{
		try
		{
			// Trailing debounce, but never wait past the burst cap - a continuous event
			// stream would otherwise reset the timer forever and never broadcast at all.
			var wait = _radarDebounce;
			var remaining = burstDeadline - DateTime.UtcNow;
			if (remaining < wait) wait = remaining;
			if (wait > TimeSpan.Zero) await Task.Delay(wait, cts.Token);

			string watchedRoot;
			lock (_radarLock)
			{
				if (_disposed || !ReferenceEquals(cts, _radarDebounceCts) ||
					!ReferenceEquals(watcher, _liveRader) || string.IsNullOrEmpty(_radarTargetPath)) return;

				_radarDebounceCts = null;
				_radarBurstStartedUtc = DateTime.MinValue;
				_lastRadarBroadcastUtc = DateTime.UtcNow;
				watchedRoot = _radarTargetPath.Replace("\\", "/");
			}

			await _hub.Clients.All.SendAsync("SectorChanged", watchedRoot);
		}
		catch (OperationCanceledException) { }
		catch (Exception ex)
		{
			_logger.LogDebug(ex, "Failed to broadcast SectorChanged for the watched sector");
		}
		finally
		{
			cts.Dispose();
		}
	}

	private void OnRadarError(object sender, ErrorEventArgs e)
	{
		string? watchedRoot;
		lock (_radarLock)
		{
			watchedRoot = ReferenceEquals(sender, _liveRader) ? _radarTargetPath : null;
		}

		if (string.IsNullOrEmpty(watchedRoot)) return;

		_logger.LogWarning(e.GetException(), "Live Radar encountered an error. Buffer may have overflowed.");
		_watcherLog?.LogOverflow(watchedRoot);

		// Dropped events cannot be recovered, so resync the whole subtree. Not InvalidatePaths:
		// that one also calls SaveMemoryToDisk, whose write is itself inside the watched tree.
		_cacheService?.HandleWatcherOverflow(watchedRoot);

		ScheduleRadarBroadcast(sender as FileSystemWatcher);
	}

	// Fix: Apply same lock pattern scan path got(To prevent concurrency race)
	public CancellationToken NukeToken()
	{
		_nukeCts?.Cancel();
		_nukeCts = new CancellationTokenSource();
		return _nukeCts.Token;
	}

	public void TriggerNukeAbort()
	{
		_nukeCts?.Cancel();
	}

	public Guid BeginScanSession(Guid? scanId = null)
	{
		var id = scanId ?? Guid.NewGuid();

		if (_activeSessions.TryRemove(id, out var existingSession))
		{
			existingSession.Dispose();
		}

		var newSession = new ScanSession(id);
		_activeSessions[id] = newSession;

		return id;
	}

	public CancellationToken GetScanToken(Guid scanId)
	{
		return _activeSessions.TryGetValue(scanId, out var session) ? session.Cts.Token : CancellationToken.None;
	}

	public void EndScanSession(Guid scanId)
	{
		if (_activeSessions.TryRemove(scanId, out var session))
		{
			session.Dispose();
		}
	}

	public void TriggerScanAbort(Guid? scanId = null)
	{
		if (scanId.HasValue)
		{
			if (_activeSessions.TryGetValue(scanId.Value, out var session))
			{
				session.Cts.Cancel();
				_logger.LogInformation("Scan abort signal received for specific scanId: {ScanId}", scanId.Value);
			}
		}
		else
		{
			foreach (var session in _activeSessions.Values)
			{
				session.Cts.Cancel();
			}
			_logger.LogInformation("Global scan abort signal received, all active scans canceled");
		}
	}

	public void PruneStaleCacheEntries()
	{
		var config = _settings.Current.Cache;
		var cutoff = DateTime.UtcNow.AddMinutes(-config.ScanCacheTtlMinutes);

		// Expire by WHEN WE SCANNED the folder (CachedAtUtc), not by the folder's own
		// last-write time. Using LastUpdated here was the bug that wiped the whole
		// cache on every restart, because folders are rarely modified within the TTL.
		var stale = DirectorySizeCache
			.Where(kvp => kvp.Value.CachedAtUtc < cutoff)
			.Select(kvp => kvp.Key)
			.ToList();

		foreach (var key in stale)
			DirectorySizeCache.TryRemove(key, out _);

		_logger.LogDebug("Cache pruned: {Count} stale entries removed (TTL = {TtlMinutes} min)", stale.Count, config.ScanCacheTtlMinutes);
	}

	// Enforces CacheSettingDto.MaxCacheScans by keeping only the N most-recently
	// scanned top-level roots (drive / browsed folder), evicting ALL folder entries
	// that belong to older scans. This is "5 most-recent scans", not "5 folders".
	// Previously MaxCacheScans was declared in settings but never read, so it did
	// nothing.
	public void EnforceMaxCacheScans()
	{
		var maxScans = _settings.Current.Cache.MaxCacheScans;
		if (maxScans <= 0) return;

		var rootsByRecency = DirectorySizeCache
			.Where(kvp => !string.IsNullOrEmpty(kvp.Value.ScanRoot))
			.GroupBy(kvp => kvp.Value.ScanRoot!, StringComparer.OrdinalIgnoreCase)
			.Select(g => new { Root = g.Key, LastScan = g.Max(kvp => kvp.Value.CachedAtUtc) })
			.OrderByDescending(x => x.LastScan)
			.ToList();

		if (rootsByRecency.Count <= maxScans) return;

		var rootsToEvict = rootsByRecency
			.Skip(maxScans)
			.Select(x => x.Root)
			.ToHashSet(StringComparer.OrdinalIgnoreCase);

		var keysToRemove = DirectorySizeCache
			.Where(kvp => kvp.Value.ScanRoot != null && rootsToEvict.Contains(kvp.Value.ScanRoot))
			.Select(kvp => kvp.Key)
			.ToList();

		foreach (var key in keysToRemove)
			DirectorySizeCache.TryRemove(key, out _);

		_logger.LogInformation(
			"Cache trimmed to {MaxScans} most-recent scan roots: evicted {RootCount} older root(s), {EntryCount} folder entries",
			maxScans, rootsToEvict.Count, keysToRemove.Count);
	}

	public void ClearCache()
	{
		DirectorySizeCache.Clear();
		_cacheService?.Clear();

		// Without this the analyzer snapshots sit in the shared IMemoryCache for their full
		// 15-minute TTL, still holding the extension dictionaries — the "never returns to idle" bug.
		ResetAnalyzerSnapshots();

		lock (_fileWriteLock)
		{
			try
			{
				if (File.Exists(_cacheFilePath))
					File.Delete(_cacheFilePath);
			}
			catch (Exception ex)
			{
				_logger.LogWarning(ex, "Failed to delete cache file");
			}
		}

		// CompactOnce because the freed extension dictionaries and JSON buffers sit on the LOH,
		// which is never compacted by default. The only forced collection here — keep it off scan paths.
		GCSettings.LargeObjectHeapCompactionMode = GCLargeObjectHeapCompactionMode.CompactOnce;
		GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);
		GC.WaitForPendingFinalizers();
		GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);

		_logger.LogInformation(
			"Cache cleared — memory wiped, analyzer snapshots evicted, scanner_memory.json deleted, LOH compacted");
	}

	public void InvalidatePaths(IEnumerable<string> paths)
	{
		var nukedSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
		var parentsToRemove = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
		var subtreePrefixes = new List<string>();

		foreach (var path in paths)
		{
			var normalizedPath = Path.GetFullPath(path);
			nukedSet.Add(normalizedPath);

			subtreePrefixes.Add(
				normalizedPath.EndsWith(Path.DirectorySeparatorChar.ToString())
					? normalizedPath
					: normalizedPath + Path.DirectorySeparatorChar);

			var parent = Path.GetDirectoryName(normalizedPath);
			while (!string.IsNullOrEmpty(parent))
			{
				parentsToRemove.Add(parent);
				parent = Path.GetDirectoryName(parent);
			}
		}

		if (nukedSet.Count == 0) return;

		var keysToRemove = DirectorySizeCache.Keys
			.Where(k =>
				nukedSet.Contains(k) ||
				parentsToRemove.Contains(k) ||
				subtreePrefixes.Any(prefix => k.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)))
			.ToList();

		foreach (var key in keysToRemove)
		{
			DirectorySizeCache.TryRemove(key, out _);
		}

		_cacheService?.InvalidatePaths(paths);
		SaveMemoryToDisk();
	}
}

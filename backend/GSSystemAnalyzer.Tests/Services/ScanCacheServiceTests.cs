using System.IO;
using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services;

// Isolated because ClearCache() forces a collection, which corrupts the process-wide heap
// reading in Soak/LeakTests.cs when the two run in parallel. See P-9 for its separate thread flake.
[CollectionDefinition("ForcedGarbageCollection", DisableParallelization = true)]
public class ForcedGarbageCollectionCollection { }

[Collection("ForcedGarbageCollection")]
public class ScanCacheServiceTests
{
	private readonly Mock<ISettingService> _mockSettings;
	private readonly AppSettingDto _currentSettings;

	public ScanCacheServiceTests()
	{
		_currentSettings = new AppSettingDto
		{
			Cache = new CacheSettingDto
			{
				ScanCacheTtlMinutes = 15,
				MaxCacheScans = 5,
				MaxCachedNodes = 50000
			},
			Scan = new ScanSettingDto
			{
				Depth = 5
			}
		};

		_mockSettings = new Mock<ISettingService>();
		_mockSettings.Setup(s => s.Current).Returns(_currentSettings);
	}

	private ScanCacheService CreateService()
	{
		return new ScanCacheService(_mockSettings.Object, NullLogger<ScanCacheService>.Instance);
	}

	[Fact]
	public void SetAndGetNode_ReturnsCachedNode()
	{
		using var service = CreateService();

		var file1 = new CachedFileEntry("test.txt", ".txt", 1024, DateTime.UtcNow);
		var node = new CachedDirNode(
			Path: @"C:\Data\Folder1",
			ChildDirectoryPaths: new List<string>(),
			Files: new List<CachedFileEntry> { file1 },
			OwnBytes: 1024,
			RecursiveBytes: 1024,
			CachedAt: DateTimeOffset.UtcNow,
			RecursiveBytesStale: false
		);

		service.SetNode(node, @"C:\");

		var retrieved = service.GetNode(@"C:\Data\Folder1");
		Assert.NotNull(retrieved);
		Assert.Equal(@"C:\Data\Folder1", retrieved.Path);
		Assert.Equal(1024, retrieved.RecursiveBytes);
		Assert.Single(retrieved.Files);
		Assert.Equal("test.txt", retrieved.Files[0].Name);
	}

	[Fact]
	public void HasScanRoot_ReturnsTrueForScannedDrive_AndFalseForUnscanned()
	{
		using var service = CreateService();

		var meta = new ScanRootMeta(
			DriveRoot: @"C:\",
			Depth: 5,
			ScannedAt: DateTimeOffset.UtcNow,
			TotalBytes: 500000,
			TotalFiles: 100,
			RootNodeKey: @"C:"
		);

		Assert.False(service.HasScanRoot(@"C:\"));
		service.SetScanRoot(meta);

		Assert.True(service.HasScanRoot(@"C:\"));
		Assert.True(service.HasScanRoot(@"C:"));
		Assert.False(service.HasScanRoot(@"D:\"));

		var fetched = service.GetScanRoot(@"C:\");
		Assert.NotNull(fetched);
		Assert.Equal(500000, fetched.TotalBytes);
	}

	[Fact]
	public void LazyRecursiveBytesRollUp_RecomputesCorrectlyWhenStale()
	{
		using var service = CreateService();

		var rootPath = @"C:\Data";
		var childPath = @"C:\Data\Child";

		var childFile = new CachedFileEntry("c.bin", ".bin", 200, DateTime.UtcNow);
		var childNode = new CachedDirNode(
			Path: childPath,
			ChildDirectoryPaths: Array.Empty<string>(),
			Files: new List<CachedFileEntry> { childFile },
			OwnBytes: 200,
			RecursiveBytes: 200,
			CachedAt: DateTimeOffset.UtcNow,
			RecursiveBytesStale: false
		);

		var rootFile = new CachedFileEntry("r.txt", ".txt", 100, DateTime.UtcNow);
		var rootNode = new CachedDirNode(
			Path: rootPath,
			ChildDirectoryPaths: new List<string> { childPath },
			Files: new List<CachedFileEntry> { rootFile },
			OwnBytes: 100,
			RecursiveBytes: 300,
			CachedAt: DateTimeOffset.UtcNow,
			RecursiveBytesStale: false
		);

		service.SetNode(rootNode, @"C:\");
		service.SetNode(childNode, @"C:\");

		// Initial size is clean
		Assert.Equal(300, service.GetOrRecomputeRecursiveBytes(rootPath));

		// Mark child modified -> ancestor becomes stale
		service.MarkAncestorsStale(childPath);

		var staleRoot = service.GetNode(rootPath);
		Assert.NotNull(staleRoot);
		Assert.True(staleRoot.RecursiveBytesStale);

		// Update child with new file size (500)
		var newChildFile = new CachedFileEntry("c.bin", ".bin", 500, DateTime.UtcNow);
		var updatedChild = childNode with
		{
			Files = new List<CachedFileEntry> { newChildFile },
			OwnBytes = 500,
			RecursiveBytes = 500
		};
		service.SetNode(updatedChild, @"C:\");

		// Roll up recomputation
		var recomputed = service.GetOrRecomputeRecursiveBytes(rootPath);
		Assert.Equal(600, recomputed); // 100 own + 500 child

		var cleanedRoot = service.GetNode(rootPath);
		Assert.NotNull(cleanedRoot);
		Assert.False(cleanedRoot.RecursiveBytesStale);
		Assert.Equal(600, cleanedRoot.RecursiveBytes);
	}

	[Fact]
	public void InvalidatePrefix_RemovesDirectoryAndAllDescendants()
	{
		using var service = CreateService();

		var dirA = @"C:\Folder";
		var dirB = @"C:\Folder\Sub1";
		var dirC = @"C:\Folder\Sub1\Sub2";

		service.SetNode(new CachedDirNode(dirA, new[] { dirB }, Array.Empty<CachedFileEntry>(), 0, 0, DateTimeOffset.UtcNow, false), @"C:\");
		service.SetNode(new CachedDirNode(dirB, new[] { dirC }, Array.Empty<CachedFileEntry>(), 0, 0, DateTimeOffset.UtcNow, false), @"C:\");
		service.SetNode(new CachedDirNode(dirC, Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 0, 0, DateTimeOffset.UtcNow, false), @"C:\");

		Assert.NotNull(service.GetNode(dirA));
		Assert.NotNull(service.GetNode(dirB));
		Assert.NotNull(service.GetNode(dirC));

		service.InvalidatePrefix(dirB);

		Assert.NotNull(service.GetNode(dirA)); // Parent remains (though marked stale / updated)
		Assert.Null(service.GetNode(dirB));    // Evicted
		Assert.Null(service.GetNode(dirC));    // Descendant evicted
	}

	[Fact]
	public void InvalidatePath_ForFile_EvictsParentAndMarksAncestorsStale()
	{
		using var service = CreateService();

		var grandparent = @"C:\Root";
		var parent = @"C:\Root\Parent";
		var filePath = @"C:\Root\Parent\doc.txt";

		service.SetNode(new CachedDirNode(grandparent, new[] { parent }, Array.Empty<CachedFileEntry>(), 0, 0, DateTimeOffset.UtcNow, false), @"C:\");
		service.SetNode(new CachedDirNode(parent, Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 0, 0, DateTimeOffset.UtcNow, false), @"C:\");

		service.InvalidatePath(filePath, isDirectory: false);

		Assert.Null(service.GetNode(parent)); // Parent removed
		var gpNode = service.GetNode(grandparent);
		Assert.NotNull(gpNode);
		Assert.True(gpNode.RecursiveBytesStale); // Grandparent marked stale
	}

	[Fact]
	public async Task GetOrAddNodeAsync_StampedeProtection_ExecutesFactoryOnlyOnce()
	{
		using var service = CreateService();
		int factoryCallCount = 0;

		Task<CachedDirNode> Factory(string p, CancellationToken ct)
		{
			Interlocked.Increment(ref factoryCallCount);
			Thread.Sleep(50); // Simulate disk I/O
			return Task.FromResult(new CachedDirNode(p, Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 100, 100, DateTimeOffset.UtcNow, false));
		}

		var tasks = Enumerable.Range(0, 10)
			.Select(_ => service.GetOrAddNodeAsync(@"C:\ConcurrentTest", Factory, @"C:\"))
			.ToList();

		var results = await Task.WhenAll(tasks);

		Assert.Equal(1, factoryCallCount);
		Assert.All(results, r => Assert.NotNull(r));
	}

	[Fact]
	public void CacheStats_TracksHitsMissesAndNodesAccurately()
	{
		using var service = CreateService();

		var node = new CachedDirNode(@"C:\StatsDir", Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 500, 500, DateTimeOffset.UtcNow, false);
		service.SetNode(node, @"C:\");

		// 1 hit
		var hit = service.GetNode(@"C:\StatsDir");
		Assert.NotNull(hit);

		// 1 miss
		var miss = service.GetNode(@"C:\NonExistent");
		Assert.Null(miss);

		var stats = service.GetStats();
		Assert.Equal(1, stats.NodeCount);
		Assert.Equal(1, stats.HitCount);
		Assert.Equal(1, stats.MissCount);
		Assert.Equal(0.5, stats.HitMissRatio);
		Assert.Equal(500, stats.ApproximateBytes);
	}

	[Fact]
	public void Controller_StatsAndEvictionEndpoints_WorkAsExpected()
	{
		using var service = CreateService();
		var mockScanner = new Mock<IDiskScannerEngine>();

		var controller = new CacheController(service, mockScanner.Object);

		service.SetScanRoot(new ScanRootMeta(@"C:\", 5, DateTimeOffset.UtcNow, 1000, 10, "C:"));
		service.SetNode(new CachedDirNode(@"C:\Test", Array.Empty<string>(), Array.Empty<CachedFileEntry>(), 1000, 1000, DateTimeOffset.UtcNow, false), @"C:\");

		var statsResult = controller.GetStats() as OkObjectResult;
		Assert.NotNull(statsResult);

		// Evict specific root
		var evictRootResult = controller.EvictCache("C:\\") as OkObjectResult;
		Assert.NotNull(evictRootResult);
		Assert.False(service.HasScanRoot("C:\\"));
		Assert.Null(service.GetNode(@"C:\Test"));

		// Evict all
		var clearResult = controller.EvictCache(null) as OkObjectResult;
		Assert.NotNull(clearResult);
		mockScanner.Verify(s => s.ClearCache(), Times.Once);
	}

	[Fact]
	public void HydrateScanCacheService_FromDictionary_PopulatesNodesAndStats()
	{
		using var service = CreateService();
		var mockHub = new Mock<Microsoft.AspNetCore.SignalR.IHubContext<GSSystemAnalyzer.Hubs.SystemHub>>();
		var scanner = new DiskScannerEngine(mockHub.Object, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance, service);

		// Clear anything loaded from host's local AppData
		service.Clear();
		scanner.DirectorySizeCache.Clear();

		var savedMemory = new Dictionary<string, CacheEntry>
		{
			[@"C:\Root"] = new CacheEntry { Size = 5000, ScanRoot = @"C:\", CachedAtUtc = DateTime.UtcNow, LastUpdated = DateTime.UtcNow },
			[@"C:\Root\Sub1"] = new CacheEntry { Size = 2000, ScanRoot = @"C:\", CachedAtUtc = DateTime.UtcNow, LastUpdated = DateTime.UtcNow },
			[@"C:\Root\Sub2"] = new CacheEntry { Size = 3000, ScanRoot = @"C:\", CachedAtUtc = DateTime.UtcNow, LastUpdated = DateTime.UtcNow }
		};

		scanner.HydrateScanCacheService(savedMemory);

		var stats = service.GetStats();
		Assert.Equal(3, stats.NodeCount);
		Assert.Equal(10000, stats.ApproximateBytes);
		Assert.True(service.HasScanRoot(@"C:\"));

		var rootNode = service.GetNode(@"C:\Root");
		Assert.NotNull(rootNode);
		Assert.Contains(@"C:\Root\Sub1", rootNode.ChildDirectoryPaths);
		Assert.Contains(@"C:\Root\Sub2", rootNode.ChildDirectoryPaths);
	}

	[Fact]
	public void DiskScannerEngine_ClearCache_ResetsBothDirectorySizeCacheAndScanCacheService()
	{
		using var service = CreateService();
		var mockHub = new Mock<Microsoft.AspNetCore.SignalR.IHubContext<GSSystemAnalyzer.Hubs.SystemHub>>();
		var scanner = new DiskScannerEngine(mockHub.Object, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance, service);

		// Clear anything loaded from host's local AppData
		service.Clear();
		scanner.DirectorySizeCache.Clear();

		var savedMemory = new Dictionary<string, CacheEntry>
		{
			[@"C:\FolderA"] = new CacheEntry { Size = 1000, ScanRoot = @"C:\", CachedAtUtc = DateTime.UtcNow, LastUpdated = DateTime.UtcNow }
		};

		scanner.HydrateScanCacheService(savedMemory);
		Assert.Equal(1, service.GetStats().NodeCount);

		scanner.ClearCache();
		Assert.Equal(0, service.GetStats().NodeCount);
		Assert.Empty(scanner.DirectorySizeCache);
	}

	// --- Issue #141: ClearCache must also evict the analyzer snapshots, and the streamed
	// --- SaveMemoryToDisk must keep scanner_memory.json in its existing format.

	[Fact]
	public void ClearCache_EvictsAnalyzerSnapshots_ViaSnapshotResetToken()
	{
		using var memoryCache = new MemoryCache(new MemoryCacheOptions());
		var mockHub = new Mock<Microsoft.AspNetCore.SignalR.IHubContext<GSSystemAnalyzer.Hubs.SystemHub>>();
		var scanner = new DiskScannerEngine(mockHub.Object, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance);
		scanner.DirectorySizeCache.Clear();

		// Stand in for what FileTypeScanner / AgeHeatmapEngine do at their _cache.Set calls.
		memoryCache.Set("filetypes:c:\\", "snapshot", new MemoryCacheEntryOptions()
			.SetAbsoluteExpiration(TimeSpan.FromMinutes(15))
			.AddExpirationToken(scanner.SnapshotResetToken));

		Assert.True(memoryCache.TryGetValue("filetypes:c:\\", out _));

		scanner.ClearCache();

		Assert.False(memoryCache.TryGetValue("filetypes:c:\\", out _));
	}

	[Fact]
	public void SnapshotResetToken_AfterClearCache_IsFreshSoLaterSnapshotsSurvive()
	{
		using var memoryCache = new MemoryCache(new MemoryCacheOptions());
		var mockHub = new Mock<Microsoft.AspNetCore.SignalR.IHubContext<GSSystemAnalyzer.Hubs.SystemHub>>();
		var scanner = new DiskScannerEngine(mockHub.Object, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance);
		scanner.DirectorySizeCache.Clear();

		scanner.ClearCache();

		// A snapshot cached AFTER the reset must survive the already-spent source.
		// Otherwise every later analyzer read misses the cache for the process's life.
		memoryCache.Set("filetypes:d:\\", "fresh", new MemoryCacheEntryOptions()
			.SetAbsoluteExpiration(TimeSpan.FromMinutes(15))
			.AddExpirationToken(scanner.SnapshotResetToken));

		Assert.True(memoryCache.TryGetValue("filetypes:d:\\", out var value));
		Assert.Equal("fresh", value);
	}

	[Fact]
	public void SaveMemoryToDisk_StreamedOutput_MatchesTheStringSerializedFormatExactly()
	{
		var mockHub = new Mock<Microsoft.AspNetCore.SignalR.IHubContext<GSSystemAnalyzer.Hubs.SystemHub>>();
		var scanner = new DiskScannerEngine(mockHub.Object, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance);
		scanner.DirectorySizeCache.Clear();

		var stamp = new DateTime(2026, 9, 18, 12, 0, 0, DateTimeKind.Utc);
		scanner.DirectorySizeCache[@"C:\Alpha"] = new CacheEntry
		{
			Size = 4096,
			LastUpdated = stamp,
			CachedAtUtc = stamp,
			ScanRoot = @"C:\",
			Extensions = new Dictionary<string, FileTypeEntry>
			{
				[".txt"] = new FileTypeEntry { Count = 2, Bytes = 2048, LargestFileBytes = 1024, LargestFilePath = @"C:\Alpha\a.txt" }
			}
		};
		scanner.DirectorySizeCache[@"C:\Beta"] = new CacheEntry
		{
			Size = 0,
			LastUpdated = stamp,
			CachedAtUtc = stamp,
			ScanRoot = @"C:\",
			Extensions = null
		};

		// What the pre-#141 code produced: one contiguous string from a full Dictionary copy.
		var expected = System.Text.Json.JsonSerializer.Serialize(
			new Dictionary<string, CacheEntry>(scanner.DirectorySizeCache));

		scanner.SaveMemoryToDisk();

		var cacheFilePath = Path.Combine(
			Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
			"GSAnalyzer", "scanner_memory.json");
		var actual = File.ReadAllText(cacheFilePath);

		Assert.Equal(expected, actual);

		// And it must still round-trip through the loader's own deserialization.
		var reloaded = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(actual);
		Assert.NotNull(reloaded);
		Assert.Equal(2, reloaded!.Count);
		Assert.Equal(4096, reloaded[@"C:\Alpha"].Size);
		Assert.Equal(@"C:\Alpha\a.txt", reloaded[@"C:\Alpha"].Extensions![".txt"].LargestFilePath);
		Assert.Null(reloaded[@"C:\Beta"].Extensions);
	}
}


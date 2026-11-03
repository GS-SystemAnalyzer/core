using System.IO;
using System.Text.Json;
using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services;

// Isolated because ClearCache() forces a collection, which corrupts the process-wide heap
// reading in Soak/LeakTests.cs when the two run in parallel.
[CollectionDefinition("ForcedGarbageCollection", DisableParallelization = true)]
public class ForcedGarbageCollectionCollection { }

[Collection("ForcedGarbageCollection")]
public class ScanCacheServiceTests : IDisposable
{
	private readonly Mock<ISettingService> _mockSettings;
	private readonly AppSettingDto _currentSettings;
	private readonly ScannerCacheTestScope _cacheScope = new();

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

	private ScanCacheService CreateService(ILogger<ScanCacheService>? logger = null)
	{
		return new ScanCacheService(_mockSettings.Object, logger ?? NullLogger<ScanCacheService>.Instance);
	}

	private DiskScannerEngine CreateScanner(IScanCacheService? service = null, string? cacheFilePath = null) =>
		new(new Mock<Microsoft.AspNetCore.SignalR.IHubContext<SystemHub>>().Object,
			_mockSettings.Object, NullLogger<DiskScannerEngine>.Instance, service,
			cacheFilePath: cacheFilePath ?? _cacheScope.CreateCachePath());

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
	public void ConstructorCacheIsolation_IsEstablishedBeforeLoading()
	{
		var constructor = Assert.Single(typeof(DiskScannerEngine).GetConstructors());
		Assert.True(constructor.GetParameters().Any(p =>
			p.Name == "cacheFilePath" && p.ParameterType == typeof(string) && p.IsOptional),
			"An explicit cache path must be available before invoking the scanner constructor.");

		var firstCache = _cacheScope.CreateCachePath();
		var secondCache = _cacheScope.CreateCachePath();
		var firstPath = Path.Combine(Path.GetDirectoryName(firstCache)!, "work", "first");
		var secondPath = Path.Combine(Path.GetDirectoryName(secondCache)!, "work", "second");
		var stamp = DateTime.UtcNow;
		var firstJson = JsonSerializer.Serialize(new Dictionary<string, CacheEntry>
		{
			[firstPath] = new() { Size = 123, ScanRoot = firstPath, CachedAtUtc = stamp, LastUpdated = stamp }
		});
		var secondJson = JsonSerializer.Serialize(new Dictionary<string, CacheEntry>
		{
			[secondPath] = new() { Size = 456, ScanRoot = secondPath, CachedAtUtc = stamp, LastUpdated = stamp }
		});
		Directory.CreateDirectory(Path.GetDirectoryName(firstCache)!);
		Directory.CreateDirectory(Path.GetDirectoryName(secondCache)!);
		File.WriteAllText(firstCache, firstJson);
		File.WriteAllText(secondCache, secondJson);

		using var firstService = CreateService();
		using var secondService = CreateService();
		var hub = new Mock<Microsoft.AspNetCore.SignalR.IHubContext<SystemHub>>().Object;
		using var first = (DiskScannerEngine)constructor.Invoke(new object?[]
		{
			hub, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance, firstService, null, firstCache
		});
		using var second = (DiskScannerEngine)constructor.Invoke(new object?[]
		{
			hub, _mockSettings.Object, NullLogger<DiskScannerEngine>.Instance, secondService, null, secondCache
		});

		Assert.Equal(123, Assert.Single(first.DirectorySizeCache).Value.Size);
		Assert.Equal(456, Assert.Single(second.DirectorySizeCache).Value.Size);
		Assert.Equal(123, firstService.GetNode(firstPath)!.RecursiveBytes);
		Assert.Null(firstService.GetNode(secondPath));
		Assert.Equal(456, secondService.GetNode(secondPath)!.RecursiveBytes);
		Assert.Null(secondService.GetNode(firstPath));
		Assert.Equal(firstJson, File.ReadAllText(firstCache));
		Assert.Equal(secondJson, File.ReadAllText(secondCache));

		first.ClearCache();
		Assert.False(File.Exists(firstCache));
		Assert.Equal(secondJson, File.ReadAllText(secondCache));
		Assert.Equal(456, secondService.GetNode(secondPath)!.RecursiveBytes);
	}

	[Fact]
	public void Constructor_MalformedOwnedCache_DoesNotDeletePeerCache()
	{
		var cacheFilePath = _cacheScope.CreateCachePath();
		var peerPath = _cacheScope.CreateCachePath();
		Directory.CreateDirectory(Path.GetDirectoryName(cacheFilePath)!);
		Directory.CreateDirectory(Path.GetDirectoryName(peerPath)!);
		File.WriteAllText(cacheFilePath, "{ malformed cache");
		File.WriteAllText(peerPath, "owned peer sentinel");

		using var scanner = CreateScanner(cacheFilePath: cacheFilePath);

		Assert.Empty(scanner.DirectorySizeCache);
		Assert.False(File.Exists(cacheFilePath));
		Assert.Equal("owned peer sentinel", File.ReadAllText(peerPath));
	}

	[Fact]
	public void SaveClearAndInvalidation_PreserveAnotherScannerCache()
	{
		var firstCache = _cacheScope.CreateCachePath();
		var secondCache = _cacheScope.CreateCachePath();
		var firstRoot = Path.Combine(Path.GetDirectoryName(firstCache)!, "work");
		var secondRoot = Path.Combine(Path.GetDirectoryName(secondCache)!, "work");
		using var first = CreateScanner(cacheFilePath: firstCache);
		using var second = CreateScanner(cacheFilePath: secondCache);
		first.DirectorySizeCache[firstRoot] = new CacheEntry { Size = 123 };
		second.DirectorySizeCache[secondRoot] = new CacheEntry { Size = 456 };

		first.SaveMemoryToDisk();
		second.SaveMemoryToDisk();
		var peerBytes = File.ReadAllBytes(secondCache);

		first.InvalidatePaths(new[] { firstRoot });
		Assert.Empty(JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(firstCache))!);
		Assert.Equal(peerBytes, File.ReadAllBytes(secondCache));
		Assert.Equal(456, second.DirectorySizeCache[secondRoot].Size);

		first.ClearCache();
		Assert.False(File.Exists(firstCache));
		Assert.Equal(peerBytes, File.ReadAllBytes(secondCache));
		Assert.Equal(456, second.DirectorySizeCache[secondRoot].Size);
	}

	[Fact]
	public void CacheScope_CleansNestedAndTemporaryFiles_WithoutDeletingPeer()
	{
		using var first = new ScannerCacheTestScope(Path.TrimEndingDirectorySeparator(Path.GetTempPath()));
		using var peer = new ScannerCacheTestScope();
		var firstPath = first.CreateCachePath();
		var peerPath = peer.CreateCachePath();
		var firstRoot = Path.GetDirectoryName(firstPath)!;
		var nested = Directory.CreateDirectory(Path.Combine(firstRoot, "nested"));
		Directory.CreateDirectory(Path.GetDirectoryName(peerPath)!);
		File.WriteAllText(firstPath, "cache");
		File.WriteAllText(firstPath + ".tmp", "unfinished swap");
		File.WriteAllText(Path.Combine(nested.FullName, "extra.tmp"), "owned nested file");
		File.WriteAllText(peerPath, "peer sentinel");

		first.Dispose();
		first.Dispose();

		Assert.False(Directory.Exists(firstRoot));
		Assert.Equal("peer sentinel", File.ReadAllText(peerPath));
	}

	[Fact]
	public void CacheScope_ContainmentHandlesRootsEscapesAndPrefixSiblings()
	{
		var root = Path.GetPathRoot(Path.GetFullPath(Path.GetTempPath()))!;
		var parent = Path.Combine(Path.GetTempPath(), "gs_scanner_scope_parent");
		Assert.True(ScannerCacheTestScope.IsUnder(root, Path.Combine(root, "owned-child")));
		Assert.False(ScannerCacheTestScope.IsUnder(root, root));
		Assert.False(ScannerCacheTestScope.IsUnder(parent, parent));
		Assert.False(ScannerCacheTestScope.IsUnder(parent, Path.Combine(parent, "..", "escape")));
		Assert.False(ScannerCacheTestScope.IsUnder(parent, parent + "-sibling"));
	}

	[Fact]
	public void Cache_RoundTripsUnderUnicodeAndSpacePaths()
	{
		var basePath = Path.Combine(Path.GetTempPath(), "gs cache sc\u00e8ne \u4e2d\u6587 " + Guid.NewGuid().ToString("N"));
		try
		{
			using var scope = new ScannerCacheTestScope(basePath);
			var cacheFilePath = scope.CreateCachePath();
			var nodePath = Path.Combine(basePath, "work", "payload");
			var stamp = DateTime.UtcNow;
			using (var scanner = CreateScanner(cacheFilePath: cacheFilePath))
			{
				scanner.DirectorySizeCache[nodePath] = new CacheEntry
				{
					Size = 789, ScanRoot = nodePath, CachedAtUtc = stamp, LastUpdated = stamp
				};
				scanner.SaveMemoryToDisk();
			}
			using var reloaded = CreateScanner(cacheFilePath: cacheFilePath);
			Assert.Equal(789, reloaded.DirectorySizeCache[nodePath].Size);
			Assert.True(File.Exists(cacheFilePath));
		}
		finally
		{
			if (Directory.Exists(basePath)) Directory.Delete(basePath, recursive: true);
		}
	}

	[Fact]
	public void ServiceRegistration_ResolvesSingleConstructor_WithOwnedCache()
	{
		var cacheFilePath = _cacheScope.CreateCachePath();
		var services = new ServiceCollection();
		services.AddSingleton(new Mock<Microsoft.AspNetCore.SignalR.IHubContext<SystemHub>>().Object);
		services.AddSingleton(_mockSettings.Object);
		services.AddSingleton<ILogger<DiskScannerEngine>>(NullLogger<DiskScannerEngine>.Instance);
		services.AddSingleton(cacheFilePath);
		services.AddSingleton<DiskScannerEngine>();
		using var provider = services.BuildServiceProvider(new ServiceProviderOptions { ValidateOnBuild = true });
		var scanner = provider.GetRequiredService<DiskScannerEngine>();
		scanner.DirectorySizeCache["owned model key"] = new CacheEntry { Size = 123 };
		scanner.SaveMemoryToDisk();
		Assert.Equal(123, JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(cacheFilePath))!["owned model key"].Size);
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
		using var scanner = CreateScanner(service);
		Assert.Empty(scanner.DirectorySizeCache);

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
		using var scanner = CreateScanner(service);
		Assert.Empty(scanner.DirectorySizeCache);

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

	// ClearCache must also evict the analyzer snapshots, and the streamed
	// SaveMemoryToDisk must keep scanner_memory.json in its existing format.

	[Fact]
	public void ClearCache_EvictsAnalyzerSnapshots_ViaSnapshotResetToken()
	{
		using var memoryCache = new MemoryCache(new MemoryCacheOptions());
		using var scanner = CreateScanner();

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
		using var scanner = CreateScanner();

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
		var cacheFilePath = _cacheScope.CreateCachePath();
		using var scanner = CreateScanner(cacheFilePath: cacheFilePath);

		var stamp = new DateTime(2026, 9, 18, 12, 0, 0, DateTimeKind.Utc);
		scanner.DirectorySizeCache[@"C:\Alpha"] = new CacheEntry
		{
			Size = 4096,
			LastUpdated = stamp,
			CachedAtUtc = stamp,
			ScanRoot = @"C:\",
			Extensions = new Dictionary<string, FileTypeEntry>
			{
				[".txt"] = new FileTypeEntry { Count = 2, Bytes = 2048, LargestFileBytes = 1024, LargestFileName = "a.txt" }
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

		// Baseline: the full-dictionary serialization the streamed writer must reproduce exactly.
		var expected = System.Text.Json.JsonSerializer.Serialize(
			new Dictionary<string, CacheEntry>(scanner.DirectorySizeCache));

		scanner.SaveMemoryToDisk();

		var actual = File.ReadAllText(cacheFilePath);

		Assert.Equal(expected, actual);

		// And it must still round-trip through the loader's own deserialization.
		var reloaded = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(actual);
		Assert.NotNull(reloaded);
		Assert.Equal(2, reloaded!.Count);
		Assert.Equal(4096, reloaded[@"C:\Alpha"].Size);
		Assert.Equal("a.txt", reloaded[@"C:\Alpha"].Extensions![".txt"].LargestFileName);
		Assert.Equal(string.Empty, reloaded[@"C:\Alpha"].Extensions![".txt"].LargestFilePath);
		Assert.Null(reloaded[@"C:\Beta"].Extensions);
	}

	[Fact]
	public async Task HandleWatcherEvent_RapidRepeatedEvents_NoDisposeException_InvalidatesTarget()
	{
		var mockLogger = new Mock<ILogger<ScanCacheService>>();
		using var service = CreateService(mockLogger.Object);

		var dir = @"C:\Data\Folder1";
		var file = @"C:\Data\Folder1\file.txt";
		var node = new CachedDirNode(dir, Array.Empty<string>(), new[] { new CachedFileEntry("file.txt", ".txt", 100, DateTime.UtcNow) }, 100, 100, DateTimeOffset.UtcNow, false);
		service.SetNode(node, @"C:\");

		Assert.NotNull(service.GetNode(dir));

		for (var i = 0; i < 50; i++)
		{
			service.HandleWatcherEvent(file, WatcherChangeTypes.Changed);
		}

		await Task.Delay(800);

		mockLogger.Verify(
			l => l.Log(
				LogLevel.Warning,
				It.IsAny<EventId>(),
				It.IsAny<It.IsAnyType>(),
				It.IsAny<Exception>(),
				It.IsAny<Func<It.IsAnyType, Exception?, string>>()),
			Times.Never);

		Assert.Null(service.GetNode(dir));
	}

	public void Dispose() => _cacheScope.Dispose();
}

internal sealed class ScannerCacheTestScope : IDisposable
{
	private readonly string _tempParent = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
	private readonly string _basePath;
	private readonly List<string> _roots = new();
	private readonly HashSet<string> _deferred = new(
		OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);

	internal ScannerCacheTestScope(string? basePath = null)
	{
		_basePath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(basePath ?? _tempParent));
		if (!string.Equals(_basePath, _tempParent, PathComparison) && !IsUnder(_tempParent, _basePath))
			throw new ArgumentException("Cache fixtures must be within the temporary directory.", nameof(basePath));
	}

	internal string CreateCachePath()
	{
		var root = Path.Combine(_basePath, "gs_scanner_cache_" + Guid.NewGuid().ToString("N"));
		_roots.Add(root);
		return Path.Combine(root, "scanner_memory.json");
	}

	internal void DeferCleanup(string cacheFilePath)
	{
		var root = Path.GetDirectoryName(Path.GetFullPath(cacheFilePath))!;
		if (!_roots.Any(owned => string.Equals(owned, root, PathComparison)))
			throw new ArgumentException("Only an owned cache root can defer cleanup.", nameof(cacheFilePath));
		_deferred.Add(root);
	}

	internal static bool IsUnder(string parent, string path)
	{
		var relative = Path.GetRelativePath(parent, path);
		return !Path.IsPathRooted(relative) && relative != "." && relative != ".." &&
			!relative.StartsWith(".." + Path.DirectorySeparatorChar, PathComparison);
	}

	private static StringComparison PathComparison =>
		OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

	public void Dispose()
	{
		foreach (var root in _roots)
		{
			if (_deferred.Contains(root)) continue;
			if (!IsUnder(_tempParent, root) || !Path.GetFileName(root).StartsWith("gs_scanner_cache_", StringComparison.Ordinal))
				throw new InvalidOperationException("Cache cleanup must target an owned temporary root.");
			if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
		}
	}
}

using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace GSSystemAnalyzer.Tests.Services;

public class ScanDiffServiceTests : IDisposable
{
	private readonly string _tempDir;
	private readonly ScannerCacheTestScope _cacheScope = new();
	private readonly List<DiskScannerEngine> _engines = new();
	private readonly List<IMemoryCache> _caches = new();

	public ScanDiffServiceTests()
	{
		_tempDir = Path.Combine(Path.GetTempPath(), "gsdiff_" + Guid.NewGuid().ToString("N"));
		Directory.CreateDirectory(_tempDir);
	}

	public void Dispose()
	{
		foreach (var cache in _caches) cache.Dispose();
		foreach (var engine in _engines) engine.Dispose();
		_cacheScope.Dispose();
		try { Directory.Delete(_tempDir, recursive: true); } catch { /* best effort */ }
	}

	// A drive root that exists on the running platform, so Path.GetFullPath stays stable.
	private static string Root => OperatingSystem.IsWindows() ? @"C:\" : "/";
	private static string Sub(string rel) =>
		OperatingSystem.IsWindows() ? $@"C:\{rel.Replace('/', '\\')}" : "/" + rel;

	private DiskScannerEngine CreateEngine()
	{
		var mockClients = new Mock<IHubClients>();
		mockClients.Setup(c => c.All).Returns(new Mock<IClientProxy>().Object);
		var mockHub = new Mock<IHubContext<SystemHub>>();
		mockHub.Setup(h => h.Clients).Returns(mockClients.Object);

		var mockSettings = new Mock<ISettingService>();
		mockSettings.Setup(s => s.Current).Returns(new AppSettingDto());

		var engine = new DiskScannerEngine(mockHub.Object, mockSettings.Object, NullLogger<DiskScannerEngine>.Instance,
			cacheFilePath: _cacheScope.CreateCachePath());
		_engines.Add(engine);
		return engine;
	}

	private ScanDiffService CreateService(DiskScannerEngine engine, IMemoryCache? cache = null)
	{
		var store = new ScanSnapshotStore(testDir: _tempDir);
		var settings = new Mock<ISettingService>();
		settings.Setup(s => s.Current).Returns(new AppSettingDto());
		cache ??= new MemoryCache(new MemoryCacheOptions());
		if (!_caches.Contains(cache)) _caches.Add(cache);
		return new ScanDiffService(
			engine,
			store,
			settings.Object,
			cache,
			NullLogger<ScanDiffService>.Instance);
	}

	private static void Seed(DiskScannerEngine engine, string path, long size)
	{
		engine.DirectorySizeCache[path] = new CacheEntry
		{
			Size = size,
			LastUpdated = DateTime.UtcNow,
			CachedAtUtc = DateTime.UtcNow
		};
	}

	[Fact]
	public void FirstScan_ReturnsNoBaseline_AndPromotes()
	{
		var engine = CreateEngine();
		Seed(engine, Root, 1000);
		var svc = CreateService(engine);

		var diff = svc.ComputeAndPromote(Root);

		Assert.False(diff.HasBaseline);
		Assert.Empty(diff.Added);
		Assert.Empty(diff.Removed);
		Assert.Empty(diff.Grown);
		Assert.Empty(diff.Shrunk);

		// A baseline file must now exist so the next scan has something to diff against.
		Assert.NotEmpty(Directory.GetFiles(_tempDir, "*.json"));
	}

	[Fact]
	public void SecondScan_DetectsAddedRemovedGrownShrunk()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());

		// First scan establishes the baseline.
		var engine1 = CreateEngine();
		Seed(engine1, Root, 3000);
		Seed(engine1, Sub("keep"), 1000);   // will grow
		Seed(engine1, Sub("shrinkme"), 1000); // will shrink
		Seed(engine1, Sub("gone"), 1000);   // will be removed
		CreateService(engine1, cache).ComputeAndPromote(Root);

		// Second scan with changes.
		var engine2 = CreateEngine();
		Seed(engine2, Root, 5200);
		Seed(engine2, Sub("keep"), 1500);       // +500 grown
		Seed(engine2, Sub("shrinkme"), 200);    // -800 shrunk
		Seed(engine2, Sub("brandnew"), 2000);   // added
		var diff = CreateService(engine2, cache).ComputeAndPromote(Root);

		Assert.True(diff.HasBaseline);
		Assert.Contains(diff.Added, e => e.Path.EndsWith("brandnew"));
		Assert.Contains(diff.Removed, e => e.Path.EndsWith("gone"));
		Assert.Contains(diff.Grown, e => e.Path.EndsWith("keep") && e.DeltaBytes == 500);
		Assert.Contains(diff.Shrunk, e => e.Path.EndsWith("shrinkme") && e.DeltaBytes == -800);
	}

	[Fact]
	public void NeverEmits_ZeroDelta()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());
		var e1 = CreateEngine();
		Seed(e1, Root, 1000);
		Seed(e1, Sub("static"), 500);
		CreateService(e1, cache).ComputeAndPromote(Root);

		var e2 = CreateEngine();
		Seed(e2, Root, 1000);
		Seed(e2, Sub("static"), 500); // unchanged
		var diff = CreateService(e2, cache).ComputeAndPromote(Root);

		Assert.DoesNotContain(diff.Grown, x => x.Path.EndsWith("static"));
		Assert.DoesNotContain(diff.Shrunk, x => x.Path.EndsWith("static"));
	}

	[Fact]
	public void AddedDirectory_IsCollapsed_WithChildCount()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());
		var e1 = CreateEngine();
		Seed(e1, Root, 1000);
		CreateService(e1, cache).ComputeAndPromote(Root);

		// Whole new subtree appears: parent + two descendants.
		var e2 = CreateEngine();
		Seed(e2, Root, 4000);
		Seed(e2, Sub("newtree"), 3000);
		Seed(e2, Sub("newtree/child1"), 2000);
		Seed(e2, Sub("newtree/child2"), 1000);
		var diff = CreateService(e2, cache).ComputeAndPromote(Root);

		// Only the top-most new directory is listed, with its descendants counted.
		var added = Assert.Single(diff.Added, e => e.Path.EndsWith("newtree"));
		Assert.Equal(2, added.ChildCount);
		Assert.DoesNotContain(diff.Added, e => e.Path.EndsWith("child1"));
		Assert.DoesNotContain(diff.Added, e => e.Path.EndsWith("child2"));
	}

	[Fact]
	public void RemovedDirectory_IsCollapsed_WithChildCount()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());
		var e1 = CreateEngine();
		Seed(e1, Root, 4000);
		Seed(e1, Sub("oldtree"), 3000);
		Seed(e1, Sub("oldtree/a"), 2000);
		Seed(e1, Sub("oldtree/b"), 1000);
		CreateService(e1, cache).ComputeAndPromote(Root);

		var e2 = CreateEngine();
		Seed(e2, Root, 1000); // oldtree gone entirely
		var diff = CreateService(e2, cache).ComputeAndPromote(Root);

		var removed = Assert.Single(diff.Removed, e => e.Path.EndsWith("oldtree"));
		Assert.Equal(2, removed.ChildCount);
		Assert.DoesNotContain(diff.Removed, e => e.Path.EndsWith("oldtree/a"));
	}

	[Fact]
	public void NetDelta_MatchesRootRecursiveChange()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());
		var e1 = CreateEngine();
		Seed(e1, Root, 1000);
		CreateService(e1, cache).ComputeAndPromote(Root);

		var e2 = CreateEngine();
		Seed(e2, Root, 6000); // +5000 overall
		var diff = CreateService(e2, cache).ComputeAndPromote(Root);

		Assert.Equal(5000, diff.Summary.NetDeltaBytes);
	}

	[Fact]
	public void MinDeltaBytes_FiltersSmallMovers_ButKeepsSummary()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());
		var e1 = CreateEngine();
		Seed(e1, Root, 3000);
		Seed(e1, Sub("big"), 1000);
		Seed(e1, Sub("small"), 1000);
		CreateService(e1, cache).ComputeAndPromote(Root);

		var e2 = CreateEngine();
		Seed(e2, Root, 4100);
		Seed(e2, Sub("big"), 2000);   // +1000
		Seed(e2, Sub("small"), 1100); // +100
		var svc = CreateService(e2, cache);
		svc.ComputeAndPromote(Root);

		var filtered = svc.GetCachedDiff(Root, minDeltaBytes: 500);

		Assert.NotNull(filtered);
		Assert.Contains(filtered!.Grown, e => e.Path.EndsWith("big"));
		Assert.DoesNotContain(filtered.Grown, e => e.Path.EndsWith("small"));
		// Summary counts remain accurate (both movers counted).
		Assert.Equal(2, filtered.Summary.GrownCount);
	}

	[Fact]
	public void GetCachedDiff_ReturnsNull_WhenNoScanComputed()
	{
		var svc = CreateService(CreateEngine());
		Assert.Null(svc.GetCachedDiff(Root));
	}

	[Fact]
	public void ClearBaseline_CausesNextScanToReportNoBaseline()
	{
		var cache = new MemoryCache(new MemoryCacheOptions());
		var e1 = CreateEngine();
		Seed(e1, Root, 1000);
		var svc1 = CreateService(e1, cache);
		svc1.ComputeAndPromote(Root);
		svc1.ClearBaseline(Root);

		var e2 = CreateEngine();
		Seed(e2, Root, 2000);
		var diff = CreateService(e2, cache).ComputeAndPromote(Root);

		Assert.False(diff.HasBaseline);
	}

	[Fact]
	public void Baseline_SurvivesNewServiceInstance()
	{
		// Simulates an app/backend restart: baseline persists on disk across instances.
		var e1 = CreateEngine();
		Seed(e1, Root, 1000);
		CreateService(e1, new MemoryCache(new MemoryCacheOptions())).ComputeAndPromote(Root);

		var e2 = CreateEngine();
		Seed(e2, Root, 2000);
		var diff = CreateService(e2, new MemoryCache(new MemoryCacheOptions())).ComputeAndPromote(Root);

		Assert.True(diff.HasBaseline);
		Assert.Equal(1000, diff.Summary.NetDeltaBytes);
	}
}

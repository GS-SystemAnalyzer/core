using System.Collections.Concurrent;
using System.Reflection;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace GSSystemAnalyzer.Tests.Engine;

/// <summary>Regression cover for issue #170 - nested changes and burst coalescing.</summary>
public sealed class DiskScannerEngineWatcherTests : IDisposable
{
	// The engine debounces for 1000ms and caps a burst at 1000ms, so a broadcast lands
	// ~1s after a burst's first event. Waits below are that plus slack for CI.
	private static readonly TimeSpan BroadcastWait = TimeSpan.FromSeconds(10);
	private const int SettleMs = 1600;

	private readonly string _tempRoot = Path.Combine(
		Path.GetTempPath(),
		$"gs-radar-{Guid.NewGuid():N}");
	private readonly List<Harness> _harnesses = new();

	public DiskScannerEngineWatcherTests() => Directory.CreateDirectory(_tempRoot);

	// --- Step 2: the visible tree is watched, and no extra notify filter was added ---------

	[Fact]
	public void MoveRadarToSector_WatchesSubdirectories_WithoutLastWriteNoise()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);

		var watcher = GetWatcher(harness.Engine);

		Assert.True(watcher.IncludeSubdirectories);
		Assert.Equal(65536, watcher.InternalBufferSize);
		// LastWrite fires on every content flush; Size already covers grow/shrink (plan O-3).
		Assert.False(watcher.NotifyFilter.HasFlag(NotifyFilters.LastWrite));
		Assert.Equal(
			NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.Size,
			watcher.NotifyFilter);
	}

	/// <summary>The reported bug, driven through the real OS watcher rather than a mock.</summary>
	[Fact]
	public async Task NestedFileChange_ReachesTheHub_ThroughTheRealWatcher()
	{
		var nested = Directory.CreateDirectory(Path.Combine(_tempRoot, "a", "b", "c"));
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);

		await File.WriteAllTextAsync(Path.Combine(nested.FullName, "deep.txt"), "payload");

		var sector = await harness.FirstBroadcast.Task.WaitAsync(BroadcastWait);
		Assert.Equal(Normalize(_tempRoot), sector);
	}

	// --- Step 3: the payload is the watched root, because the Dart side compares by equality -

	[Fact]
	public async Task NestedChange_BroadcastsWatchedRoot_NotTheChangedFolder()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		var nestedFile = Path.Combine(_tempRoot, "one", "two", "leaf.txt");
		RaiseChanged(harness.Engine, watcher, nestedFile);

		var sector = await harness.FirstBroadcast.Task.WaitAsync(BroadcastWait);

		Assert.Equal(Normalize(_tempRoot), sector);
		Assert.DoesNotContain("one/two", sector);
		Assert.DoesNotContain("\\", sector);
	}

	// --- Step 1 + 5: bursts coalesce, and nothing is dropped on the way to the cache --------

	[Fact]
	public async Task RapidBurst_BroadcastsOnce_ButNoEventIsDroppedFromTheCache()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		for (var i = 0; i < 12; i++)
		{
			RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, $"burst-{i}.txt"));
		}

		await harness.FirstBroadcast.Task.WaitAsync(BroadcastWait);
		await Task.Delay(SettleMs);

		// Coalescing, not an exact count: under full-suite load the 12 injected calls can
		// themselves span more than the 1000ms cap, which correctly forces a second burst.
		Assert.InRange(harness.Broadcasts.Count, 1, 2);

		// The removed leading-edge gate used to return before HandleWatcherEvent, so
		// suppressed events never reached the cache's own debounce and it drifted.
		harness.Cache.Verify(
			c => c.HandleWatcherEvent(It.IsAny<string>(), It.IsAny<WatcherChangeTypes>()),
			Times.Exactly(12));
	}

	/// <summary>A reset-on-every-event debounce would never fire here (plan O-1).</summary>
	[Fact]
	public async Task SustainedStream_KeepsBroadcasting_AndDoesNotStarve()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		for (var i = 0; i < 26; i++)
		{
			RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, $"stream-{i}.txt"));
			await Task.Delay(100);
		}

		await Task.Delay(SettleMs);

		Assert.True(
			harness.Broadcasts.Count >= 2,
			$"expected the burst cap to force repeated broadcasts, saw {harness.Broadcasts.Count}");
	}

	// --- Step 6: overflow resyncs the subtree through the purpose-built path -----------------

	[Fact]
	public async Task WatcherError_InvalidatesSubtree_AndSchedulesRefresh()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		RaiseWatcherError(watcher);

		harness.Cache.Verify(c => c.HandleWatcherOverflow(_tempRoot), Times.Once);
		harness.WatcherLog.Verify(l => l.LogOverflow(_tempRoot), Times.Once);

		var sector = await harness.FirstBroadcast.Task.WaitAsync(BroadcastWait);
		Assert.Equal(Normalize(_tempRoot), sector);
	}

	// --- Step 4: the app's own writes never re-trigger a scan --------------------------------

	[Theory]
	[InlineData("scanner_memory.json")]
	[InlineData("scanner_memory.json.tmp")]
	[InlineData("appsettings.user.json")]
	[InlineData("scheduled_scans.json")]
	[InlineData("anything.tmp")]
	public async Task AppInternalWrite_ProducesNoBroadcast_NoLog_NoInvalidation(string fileName)
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, fileName));
		await Task.Delay(SettleMs);

		Assert.Empty(harness.Broadcasts);
		harness.Cache.Verify(
			c => c.HandleWatcherEvent(It.IsAny<string>(), It.IsAny<WatcherChangeTypes>()),
			Times.Never);
		harness.WatcherLog.Verify(
			l => l.LogEvent(
				It.IsAny<DateTimeOffset>(), It.IsAny<WatcherChangeKind>(),
				It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<bool>()),
			Times.Never);
	}

	[Theory]
	[InlineData("scan_snapshots")]
	[InlineData(".git")]
	public async Task AppInternalDirectoryWrite_ProducesNoBroadcast(string directoryName)
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, directoryName, "entry.dat"));
		await Task.Delay(SettleMs);

		Assert.Empty(harness.Broadcasts);
	}

	[Fact]
	public async Task ExternalWriteAfterAppInternalWrites_StillBroadcastsOnce()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		for (var i = 0; i < 50; i++)
		{
			RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, "scanner_memory.json"));
			RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, "scanner_memory.json.tmp"));
		}

		RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, "real.txt"));

		var sector = await harness.FirstBroadcast.Task.WaitAsync(BroadcastWait);
		await Task.Delay(SettleMs);

		Assert.Equal(Normalize(_tempRoot), sector);
		Assert.Single(harness.Broadcasts);
	}

	// --- Step 7: disposal actually stops the radar -------------------------------------------

	[Fact]
	public async Task Dispose_StopsFurtherBroadcasts()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		var watcher = GetQuietWatcher(harness.Engine);

		harness.Engine.Dispose();
		RaiseChanged(harness.Engine, watcher, Path.Combine(_tempRoot, "after-dispose.txt"));
		await Task.Delay(SettleMs);

		Assert.Empty(harness.Broadcasts);
	}

	[Fact]
	public void Dispose_ThenMoveRadar_DoesNotReArmTheWatcher()
	{
		var harness = CreateHarness();
		harness.Engine.MoveRadarToSector(_tempRoot);
		GetQuietWatcher(harness.Engine);

		harness.Engine.Dispose();
		Assert.Null(GetWatcherOrNull(harness.Engine));

		// A singleton engine outlives nothing here, but LoadDirectoryItems re-arms the radar on
		// every browse; after shutdown that must not resurrect a watcher.
		harness.Engine.MoveRadarToSector(_tempRoot);
		Assert.Null(GetWatcherOrNull(harness.Engine));
	}

	[Fact]
	public async Task MovingTheRadar_CancelsAPendingBroadcastForTheOldSector()
	{
		var second = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), $"gs-radar-2nd-{Guid.NewGuid():N}"));
		try
		{
			var harness = CreateHarness();
			harness.Engine.MoveRadarToSector(_tempRoot);
			var firstWatcher = GetQuietWatcher(harness.Engine);

			RaiseChanged(harness.Engine, firstWatcher, Path.Combine(_tempRoot, "pending.txt"));
			// Asserted directly rather than inferred from silence: a pending broadcast exists,
			// and moving the radar cancels it. No wall-clock dependency either way.
			Assert.NotNull(GetDebounceCts(harness.Engine));

			harness.Engine.MoveRadarToSector(second.FullName);
			GetQuietWatcher(harness.Engine);
			Assert.Null(GetDebounceCts(harness.Engine));

			await Task.Delay(SettleMs);
			Assert.Empty(harness.Broadcasts);
		}
		finally
		{
			try { Directory.Delete(second.FullName, recursive: true); } catch (IOException) { }
		}
	}

	// --- harness ------------------------------------------------------------------------------

	private Harness CreateHarness()
	{
		var proxy = new Mock<IClientProxy>();
		var clients = new Mock<IHubClients>();
		clients.SetupGet(c => c.All).Returns(proxy.Object);

		var hub = new Mock<IHubContext<SystemHub>>();
		hub.SetupGet(h => h.Clients).Returns(clients.Object);

		var cache = new Mock<IScanCacheService>();
		var watcherLog = new Mock<IWatcherEventLogService>();
		var settings = new Mock<ISettingService>();

		var harness = new Harness(
			new DiskScannerEngine(
				hub.Object,
				settings.Object,
				NullLogger<DiskScannerEngine>.Instance,
				cache.Object,
				watcherLog.Object),
			cache,
			watcherLog);

		// SendAsync is an extension method; SendCoreAsync is the virtual one Moq can intercept.
		proxy
			.Setup(p => p.SendCoreAsync(
				"SectorChanged", It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Callback<string, object?[], CancellationToken>((_, args, _) =>
			{
				var path = Assert.IsType<string>(args[0]);
				harness.Broadcasts.Enqueue(path);
				harness.FirstBroadcast.TrySetResult(path);
			})
			.Returns(Task.CompletedTask);

		_harnesses.Add(harness);
		return harness;
	}

	private static string Normalize(string path) => path.Replace("\\", "/");

	private static FileSystemWatcher GetWatcher(DiskScannerEngine engine) =>
		Assert.IsType<FileSystemWatcher>(GetWatcherOrNull(engine));

	private static FileSystemWatcher? GetWatcherOrNull(DiskScannerEngine engine)
	{
		// Accepts either spelling: issue #152 renames _liveRader to _liveRadar.
		var field =
			typeof(DiskScannerEngine).GetField("_liveRader", BindingFlags.Instance | BindingFlags.NonPublic) ??
			typeof(DiskScannerEngine).GetField("_liveRadar", BindingFlags.Instance | BindingFlags.NonPublic);

		Assert.NotNull(field);
		return (FileSystemWatcher?)field.GetValue(engine);
	}

	/// <summary>
	/// The engine's real watcher, muted. Tests that inject events by reflection assert on
	/// exact broadcast counts, and a live watcher on a temp directory also picks up ambient
	/// OS writes (indexer, AV), which made those counts flaky under full-suite load.
	/// </summary>
	private static FileSystemWatcher GetQuietWatcher(DiskScannerEngine engine)
	{
		var watcher = GetWatcher(engine);
		watcher.EnableRaisingEvents = false;
		return watcher;
	}

	/// <summary>The pending-broadcast token, or null when no broadcast is scheduled.</summary>
	private static CancellationTokenSource? GetDebounceCts(DiskScannerEngine engine)
	{
		var field = typeof(DiskScannerEngine)
			.GetField("_radarDebounceCts", BindingFlags.Instance | BindingFlags.NonPublic);
		Assert.NotNull(field);
		return (CancellationTokenSource?)field.GetValue(engine);
	}

	/// <summary>
	/// Drives the engine's handler directly. Real OS event timing is not reproducible in CI,
	/// so only <see cref="NestedFileChange_ReachesTheHub_ThroughTheRealWatcher"/> relies on it.
	/// </summary>
	private static void RaiseChanged(DiskScannerEngine engine, FileSystemWatcher watcher, string fullPath)
	{
		var handler = typeof(DiskScannerEngine)
			.GetMethod("OnRadarTriggered", BindingFlags.Instance | BindingFlags.NonPublic);
		Assert.NotNull(handler);

		handler.Invoke(engine, new object[]
		{
			watcher,
			new FileSystemEventArgs(
				WatcherChangeTypes.Changed,
				Path.GetDirectoryName(fullPath)!,
				Path.GetFileName(fullPath)),
		});
	}

	private static void RaiseWatcherError(FileSystemWatcher watcher)
	{
		var onError = typeof(FileSystemWatcher)
			.GetMethod("OnError", BindingFlags.Instance | BindingFlags.NonPublic);
		Assert.NotNull(onError);

		onError.Invoke(watcher, new object[]
		{
			new ErrorEventArgs(new InternalBufferOverflowException()),
		});
	}

	public void Dispose()
	{
		foreach (var harness in _harnesses)
		{
			harness.Engine.Dispose();
		}

		try
		{
			Directory.Delete(_tempRoot, recursive: true);
		}
		catch (DirectoryNotFoundException) { }
		catch (IOException) { }
	}

	private sealed class Harness
	{
		public Harness(
			DiskScannerEngine engine,
			Mock<IScanCacheService> cache,
			Mock<IWatcherEventLogService> watcherLog)
		{
			Engine = engine;
			Cache = cache;
			WatcherLog = watcherLog;
		}

		public DiskScannerEngine Engine { get; }
		public Mock<IScanCacheService> Cache { get; }
		public Mock<IWatcherEventLogService> WatcherLog { get; }
		public ConcurrentQueue<string> Broadcasts { get; } = new();
		public TaskCompletionSource<string> FirstBroadcast { get; } =
			new(TaskCreationOptions.RunContinuationsAsynchronously);
	}
}

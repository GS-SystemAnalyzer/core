using System.Text.Json;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Tests.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.DependencyInjection;
using Moq;

namespace GSSystemAnalyzer.Tests.Engine;

public class BenchmarkObservationTests
{
	private static readonly string RunId = new('a', 32);
	private static TaskCompletionSource Gate() => new(TaskCreationOptions.RunContinuationsAsynchronously);
	private static BenchmarkEvent[] Read(StringWriter writer) => writer.ToString().Split('\n', StringSplitOptions.RemoveEmptyEntries)
		.Select(line => JsonSerializer.Deserialize<BenchmarkEvent>(line, BenchmarkTrace.Json)!).ToArray();
	private static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value, BenchmarkTrace.Json);
	private static (IHubContext<SystemHub> Hub, IClientProxy Proxy) Hub(Func<string, object?[], Task> send)
	{
		var hub = new Mock<IHubContext<SystemHub>>();
		var clients = new Mock<IHubClients>();
		var proxy = new Mock<IClientProxy>();
		hub.Setup(h => h.Clients).Returns(clients.Object);
		clients.Setup(c => c.All).Returns(proxy.Object);
		proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Returns((string method, object?[] args, CancellationToken _) => send(method, args));
		return (hub.Object, proxy.Object);
	}
	private static ISettingService Settings()
	{
		var mock = new Mock<ISettingService>();
		mock.Setup(s => s.Current).Returns(AppSettingDto.GetFactoryDefaults());
		return mock.Object;
	}
	private static void Settled(BenchmarkEvent[] records)
	{
		Assert.Equal("drained", records[^1].Outcome);
		Assert.Equal(0, records[^1].Counts!["outstanding"]);
		Assert.Equal(0, records[^1].Counts!["dropped"]);
		foreach (var start in records.Where(e => e.Stage.EndsWith(".start") && e.OperationId != null))
		{
			var end = Assert.Single(records.Where(e => e.OperationId == start.OperationId && e.Stage == start.Stage[..^6] + ".end"));
			Assert.True(long.Parse(end.LocalTicks) >= long.Parse(start.LocalTicks));
			Assert.Equal(start.BenchmarkTrace, end.BenchmarkTrace);
		}
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public async Task SendingPreservesPayloadAndOriginalTask(bool enabled)
	{
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(enabled ? trace : null, "ram");
		var release = Gate();
		object? sent = null;
		var (_, proxy) = Hub((_, args) => { sent = args[0]; return release.Task; });
		var original = new { Global = new { ActiveGb = 2.0 }, Processes = new[] { new { Name = "private-name", WorkingSetBytes = 41 } } };
		var task = BenchmarkTrace.Send(proxy, "RamUpdate", original);
		try
		{
			Assert.Same(release.Task, task);
			if (!enabled) Assert.Same(original, sent);
			var body = Payload(sent!);
			Assert.Equal(Payload(original).GetProperty("global").ToString(), body.GetProperty("global").ToString());
			Assert.Equal(Payload(original).GetProperty("processes").ToString(), body.GetProperty("processes").ToString());
			Assert.Equal(enabled, body.TryGetProperty("benchmarkTrace", out _));
			Assert.Equal(enabled ? 1 : 0, trace.Outstanding);
		}
		finally { release.TrySetResult(); await task; }
		await trace.DisposeAsync();
		Assert.DoesNotContain("private-name", writer.ToString());
		Settled(Read(writer));
	}

	[Fact]
	public async Task TraceLossAndOutstandingWorkCannotProduceSuccessfulFooter()
	{
		var writer = new HeldWriter();
		await using var trace = new BenchmarkTrace(RunId, writer, capacity: 1);
		await writer.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
		using var pending = trace.Begin("held");
		for (int i = 0; i < 20; i++) trace.Emit("overflow");
		Assert.True(trace.Dropped > 0);
		writer.Release.TrySetResult();
		await trace.DisposeAsync();
		var footer = Read(writer)[^1];
		Assert.Equal("incomplete", footer.Outcome);
		Assert.Equal(1, footer.Counts!["outstanding"]);
		Assert.True(footer.Counts["dropped"] > 0);
	}

	[Fact]
	public async Task WriterFailureDoesNotThrowThroughProducer()
	{
		await using var trace = new BenchmarkTrace(RunId, new FailedWriter());
		using (var work = trace.Begin("example")) trace.Emit("example.event");
		await trace.DisposeAsync();
		Assert.True(trace.WriteFailed);
	}

	[Fact]
	public async Task SequenceIsPerStreamAndRestartHasANewEpoch()
	{
		await using var a = new BenchmarkTrace(RunId, new StringWriter());
		await using var b = new BenchmarkTrace(RunId, new StringWriter());
		Assert.Equal("1", a.Metadata("ram").Sequence);
		Assert.Equal("2", a.Metadata("ram").Sequence);
		Assert.Equal("1", a.Metadata("scan").Sequence);
		Assert.NotEqual(a.Epoch, b.Metadata("ram").ProducerEpoch);
		var marker = a.Metadata("ram", 9007199254740993, 9007199254740995);
		Assert.Equal("9007199254740993", Payload(marker).GetProperty("acquisitionStartTicks").GetString());
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public async Task FlushOrCloseFailureCannotClaimSuccessfulEvidence(bool close)
	{
		var writer = new FinalizationFailureWriter(close);
		bool finalized = false;
		await using var trace = new BenchmarkTrace(RunId, writer, finalizeOutput: () => finalized = true);
		await trace.DisposeAsync();
		Assert.True(trace.WriteFailed);
		Assert.False(finalized);
		Assert.DoesNotContain(Read(writer), e => e.Stage == "trace.end" && e.Outcome == "succeeded");
	}

	[Fact]
	public async Task OwnedOutputIsPublishedOnlyAfterClose()
	{
		using var files = new ScannerCacheTestScope();
		var root = Directory.CreateDirectory(Path.GetDirectoryName(files.CreateCachePath())!).FullName;
		File.WriteAllText(Path.Combine(root, "owner.json"), JsonSerializer.Serialize(new { runId = RunId, schemaVersion = 1, detail = "minimal" }));
		await using var trace = BenchmarkTrace.CreateOwned(RunId, root);
		Assert.Empty(Directory.GetFiles(root, "*.jsonl"));
		Assert.Single(Directory.GetFiles(root, "*.partial"));
		await trace.DisposeAsync();
		Assert.False(trace.WriteFailed);
		Assert.Empty(Directory.GetFiles(root, "*.partial"));
		using var stream = File.Open(Assert.Single(Directory.GetFiles(root, "*.jsonl")), FileMode.Open, FileAccess.Read, FileShare.None);
		using var reader = new StreamReader(stream);
		Assert.Contains("\"outcome\":\"drained\"", await reader.ReadToEndAsync());
	}

	[Fact]
	public async Task RegisteredEvictionCallbackLeavesQueueQuiescenceUnknown()
	{
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace);
		using var cache = new ScanCacheService(Settings(), NullLogger<ScanCacheService>.Instance);
		cache.SetNode(new CachedDirNode(Path.Combine(Path.GetTempPath(), "observer-node"), [], [], 0, 0, DateTimeOffset.UtcNow, false));
		await trace.DisposeAsync();
		Assert.Contains(Read(writer), e => e.Stage == "cache.eviction_queue" && e.Outcome == "unknown");
	}

	[Fact]
	public void CachedEntryDoesNotRetainDisposedObserver()
	{
		using var cache = new ScanCacheService(Settings(), NullLogger<ScanCacheService>.Instance);
		var reference = RegisterDisposedTrace(cache);
		GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
		Assert.False(reference.IsAlive);
		GC.KeepAlive(cache);
	}

	[System.Runtime.CompilerServices.MethodImpl(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)]
	private static WeakReference RegisterDisposedTrace(ScanCacheService cache)
	{
		var trace = new BenchmarkTrace(RunId, new StringWriter());
		using (BenchmarkTrace.Use(trace))
			cache.SetNode(new CachedDirNode(Path.Combine(Path.GetTempPath(), "retained-node"), [], [], 0, 0, DateTimeOffset.UtcNow, false));
		trace.DisposeAsync().AsTask().GetAwaiter().GetResult();
		return new WeakReference(trace);
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public async Task CoalescerTracksDeliveredAndAbandonedItemsWithoutChangingCancellation(bool cancel)
	{
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace, "scan");
		using var cts = new CancellationTokenSource();
		var entered = Gate(); var release = Gate();
		var output = new List<int>();
		var channel = new CoalescingStreamChannel<int>(async batch =>
		{
			entered.TrySetResult();
			await release.Task;
			output.AddRange(batch);
		}, maxBatchSize: 1, cancellationToken: cts.Token);
		Task? drain = null;
		try
		{
			Assert.True(channel.TryWrite(1));
			await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
			Assert.True(channel.TryWrite(2));
			if (cancel) cts.Cancel();
			channel.Complete();
			drain = channel.DisposeAsync().AsTask();
			Assert.False(drain.IsCompleted);
			Assert.True(trace.Outstanding >= 2);
		}
		finally { release.TrySetResult(); await (drain ?? channel.DisposeAsync().AsTask()); }
		await trace.DisposeAsync();
		var records = Read(writer);
		var summary = Assert.Single(records.Where(e => e.Stage == "coalescer.summary"));
		Assert.Equal(2, summary.Counts!["accepted"]);
		Assert.Equal(cancel ? 1 : 2, summary.Counts["delivered"]);
		Assert.Equal(cancel ? 1 : 0, summary.Counts["abandoned"]);
		Assert.Equal(cancel ? new[] { 1 } : new[] { 1, 2 }, output);
		Settled(records);
	}

	[Fact]
	public async Task CoalescerSuppressedCallbackFailureRemainsVisible()
	{
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace);
		var channel = new CoalescingStreamChannel<int>(_ => Task.FromException(new IOException()), maxBatchSize: 1);
		channel.TryWrite(7);
		channel.Complete();
		await channel.DisposeAsync();
		await trace.DisposeAsync();
		var records = Read(writer);
		Assert.Contains(records, e => e.Stage == "coalescer.consumer.end" && e.Outcome == "failed");
		Assert.Equal(1, Assert.Single(records.Where(e => e.Stage == "coalescer.summary")).Counts!["abandoned"]);
		Settled(records);
	}

	[Fact]
	public async Task SessionRemovalDoesNotSettleDetachedSend()
	{
		using var files = new ScannerCacheTestScope();
		var cache = files.CreateCachePath();
		var data = Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(cache)!, "data"));
		var child = data.CreateSubdirectory("child");
		File.WriteAllBytes(Path.Combine(child.FullName, "file.bin"), [1, 2, 3]);
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace);
		var release = Gate();
		var hub = Hub((method, args) => method == "ScanProgress" && Payload(args[0]!).GetProperty("status").GetString() == "SCANNING"
			? release.Task : Task.CompletedTask).Hub;
		using var engine = new DiskScannerEngine(hub, Settings(), NullLogger<DiskScannerEngine>.Instance, cacheFilePath: cache);
		var id = engine.BeginScanSession();
		try
		{
			await engine.CalculateMissingSizesAsync([child], id);
			engine.EndScanSession(id);
			Assert.False(engine.IsScanning);
			Assert.Equal(1, trace.Outstanding);
		}
		finally { release.TrySetResult(); await release.Task; }
		await trace.DisposeAsync();
		var records = Read(writer);
		var removed = Assert.Single(records.Where(e => e.Stage == "scan.session.end"));
		var sendEnd = records.Last(e => e.Stage == "send.ScanProgress.end");
		Assert.True(long.Parse(sendEnd.LocalTicks) >= long.Parse(removed.LocalTicks));
		Assert.Equal(3, engine.DirectorySizeCache[child.FullName].Size);
		Settled(records);
	}

	[Fact]
	public async Task CancelledQueuedRequestIsObservedUntilItActuallyExits()
	{
		using var files = new ScannerCacheTestScope();
		var cache = files.CreateCachePath();
		var child = Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(cache)!, "child"));
		var release = Gate(); var entered = Gate();
		int initializations = 0;
		var hub = Hub((method, args) =>
		{
			if (method == "ScanProgress" && Payload(args[0]!).GetProperty("status").GetString() == "INITIALIZING" &&
				Interlocked.Increment(ref initializations) == 1) { entered.TrySetResult(); return release.Task; }
			return Task.CompletedTask;
		}).Hub;
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace);
		using var engine = new DiskScannerEngine(hub, Settings(), NullLogger<DiskScannerEngine>.Instance, cacheFilePath: cache);
		var firstId = engine.BeginScanSession(); var oldId = engine.BeginScanSession();
		var first = engine.CalculateMissingSizesAsync([child], firstId);
		Task? queued = null;
		try
		{
			await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
			queued = engine.CalculateMissingSizesAsync([child], oldId);
			engine.TriggerScanAbort(oldId);
			Assert.False(queued.IsCompleted);
		}
		finally
		{
			release.TrySetResult();
			await first;
			if (queued != null) { try { await queued; } catch (OperationCanceledException) { } }
			engine.EndScanSession(firstId); engine.EndScanSession(oldId);
		}
		await trace.DisposeAsync();
		var records = Read(writer);
		var abort = Assert.Single(records.Where(e => e.Stage == "scan.abort.signalled"));
		var acquire = Assert.Single(records.Where(e => e.Stage == "scan.lock_queue.end" && e.BenchmarkTrace.StreamId == oldId.ToString("N")));
		Assert.True(long.Parse(acquire.LocalTicks) >= long.Parse(abort.LocalTicks));
		Settled(records);
	}

	[Fact]
	public async Task SaveErrorIsRecordedDespiteNormalProductReturn()
	{
		using var files = new ScannerCacheTestScope();
		var cache = files.CreateCachePath();
		Directory.CreateDirectory(cache);
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace);
		using var engine = new DiskScannerEngine(Hub((_, _) => Task.CompletedTask).Hub, Settings(),
			NullLogger<DiskScannerEngine>.Instance, cacheFilePath: cache);
		engine.SaveMemoryToDisk();
		await trace.DisposeAsync();
		Assert.Contains(Read(writer), e => e.Stage == "scan.save.end" && e.Outcome == "failed");
		Settled(Read(writer));
	}

	[Fact]
	public async Task ControllerCompletionAfterErrorIsObservedWithoutRepairingIt()
	{
		using var files = new ScannerCacheTestScope();
		var cache = files.CreateCachePath();
		var data = Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(cache)!, "data"));
		var id = Guid.NewGuid();
		var service = new Mock<IDiskOperationService>();
		service.Setup(s => s.BeginScan(id)).Returns(id);
		service.Setup(s => s.StreamDirectoryAsync(data.FullName, id, It.IsAny<Func<IReadOnlyList<StorageNode>, Task>>(), It.IsAny<CancellationToken>()))
			.ThrowsAsync(new IOException("private-error"));
		var drives = new Mock<IDriveDetectionService>();
		drives.Setup(d => d.GetReadyDrives()).Returns([new DriveMetric { Name = Path.GetPathRoot(data.FullName)! }]);
		using var provider = new ServiceCollection().AddSingleton(service.Object).BuildServiceProvider();
		var settled = Gate();
		var writer = new SignallingWriter(e => { if (e.Stage == "stream.controller_task.end") settled.TrySetResult(); });
		await using var trace = new BenchmarkTrace(RunId, writer);
		var request = new string('b', 32);
		using var scope = BenchmarkTrace.Use(trace, "http-" + request);
		var sent = new List<string>();
		var hub = Hub((method, _) => { sent.Add(method); return Task.CompletedTask; }).Hub;
		var controller = new StorageController(service.Object, new Mock<IDuplicateFileDetector>().Object, provider.GetRequiredService<IServiceScopeFactory>());
		controller.StreamDirectorySection(hub, drives.Object, data.FullName, id);
		await settled.Task.WaitAsync(TimeSpan.FromSeconds(5));
		await trace.DisposeAsync();
		Assert.Equal(new[] { "DirectoryStreamError", "DirectoryStreamComplete" }, sent);
		var records = Read(writer);
		var binding = Assert.Single(records.Where(e => e.Stage == "stream.request"));
		Assert.Equal(request, binding.OperationId);
		Assert.Equal(id.ToString("N"), binding.BenchmarkTrace.StreamId);
		Assert.Equal(trace.Key(data.FullName.Replace('\\', '/').TrimEnd('/').ToUpperInvariant()), binding.Key);
		Assert.Contains(records, e => e.Stage == "stream.terminal" && e.Outcome == "failed" && e.Counts!["has_summary"] == 0);
		Assert.DoesNotContain("private-error", writer.ToString());
		Settled(records);
	}

	[Fact]
	public async Task AbortReceiptRetainsTheOriginatingHttpRequest()
	{
		var service = new Mock<IDiskOperationService>();
		using var provider = new ServiceCollection().BuildServiceProvider();
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		var request = new string('b', 32);
		var scan = Guid.NewGuid();
		using var scope = BenchmarkTrace.Use(trace, "http-" + request);
		var controller = new StorageController(service.Object, new Mock<IDuplicateFileDetector>().Object,
			provider.GetRequiredService<IServiceScopeFactory>());
		controller.AbortScan(scan);
		await trace.DisposeAsync();
		var receipt = Assert.Single(Read(writer).Where(e => e.Stage == "scan.abort.controller_received"));
		Assert.Equal(request, receipt.OperationId);
		Assert.Equal(scan.ToString("N"), receipt.BenchmarkTrace.StreamId);
		service.Verify(s => s.TriggerScanAbort(scan), Times.Once);
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public async Task StreamObserverPreservesKnownTreeResultsAndFinalSave(bool enabled)
	{
		using var files = new ScannerCacheTestScope();
		var cache = files.CreateCachePath();
		var data = Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(cache)!, "data"));
		File.WriteAllBytes(Path.Combine(data.FullName, "direct.bin"), [1, 2]);
		File.WriteAllBytes(Path.Combine(data.CreateSubdirectory("child").FullName, "nested.bin"), [3, 4, 5]);
		var hub = Hub((_, _) => Task.CompletedTask).Hub;
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(enabled ? trace : null);
		using var engine = new DiskScannerEngine(hub, Settings(), NullLogger<DiskScannerEngine>.Instance, cacheFilePath: cache);
		var service = new DiskOperationsService(engine, hub, NullLogger<DiskOperationsService>.Instance, new Mock<IScanDiffService>().Object);
		var output = new List<StorageNode>();
		var id = engine.BeginScanSession();
		var summary = await service.StreamDirectoryAsync(data.FullName, id, chunk => { output.AddRange(chunk); return Task.CompletedTask; });
		Assert.Equal(2, summary.OwnBytes);
		Assert.Equal(5, summary.RecursiveBytes);
		Assert.Equal(new long[] { 2, 3 }, output.Select(n => n.SizeBytes).Order());
		Assert.True(File.Exists(cache));
		var persisted = JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(cache))!;
		Assert.Equal(5, persisted[data.FullName].Size);
		await trace.DisposeAsync();
		var records = Read(writer);
		Assert.Equal(enabled, records.Any(e => e.Stage == "stream.final_save.end"));
		Assert.DoesNotContain(data.FullName, writer.ToString());
		Settled(records);
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public async Task RichCacheLookupObservationDoesNotChangePublicStats(bool rich)
	{
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer, rich: rich);
		using var scope = BenchmarkTrace.Use(trace);
		using var cache = new ScanCacheService(Settings(), NullLogger<ScanCacheService>.Instance);
		Assert.False(cache.TryGetNode(Path.Combine(Path.GetTempPath(), "private-cache-name"), out _));
		var stats = cache.GetStats();
		Assert.Equal(1, stats.MissCount);
		Assert.Equal(0, stats.HitCount);
		await trace.DisposeAsync();
		Assert.Equal(rich, Read(writer).Any(e => e.Stage == "cache.lookup" && e.Outcome == "miss"));
		Assert.DoesNotContain("private-cache-name", writer.ToString());
		Settled(Read(writer));
	}

	[Fact]
	public async Task SuppressedFileTypesFailureIsRecordedWithNormalStreamReturn()
	{
		using var files = new ScannerCacheTestScope();
		var cache = files.CreateCachePath();
		var data = Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(cache)!, "data"));
		var hub = Hub((_, _) => Task.CompletedTask).Hub;
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(trace);
		using var engine = new DiskScannerEngine(hub, Settings(), NullLogger<DiskScannerEngine>.Instance, cacheFilePath: cache);
		var types = new Mock<IFileTypeScanner>();
		types.Setup(t => t.Invalidate(data.FullName)).Throws(new IOException("private-failure"));
		var service = new DiskOperationsService(engine, hub, NullLogger<DiskOperationsService>.Instance,
			new Mock<IScanDiffService>().Object, fileTypeScanner: types.Object);
		var result = await service.StreamDirectoryAsync(data.FullName, engine.BeginScanSession(), _ => Task.CompletedTask);
		Assert.Equal(0, result.RecursiveBytes);
		await trace.DisposeAsync();
		Assert.Contains(Read(writer), e => e.Stage == "stream.file_types_invalidation" && e.Outcome == "failed");
		Assert.DoesNotContain("private-failure", writer.ToString());
	}

	[Theory]
	[InlineData(false)]
	[InlineData(true)]
	public async Task RamAcquisitionMetadataIsOptionalAndDoesNotChangeValues(bool enabled)
	{
		var received = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
		var writer = new StringWriter();
		await using var trace = new BenchmarkTrace(RunId, writer);
		using var scope = BenchmarkTrace.Use(enabled ? trace : null);
		var hub = Hub((method, args) => { if (method == "RamUpdate") received.TrySetResult(args[0]!); return Task.CompletedTask; }).Hub;
		await using var engine = new RamMonitoringEngine(hub, Settings(), new Mock<IProcessOwnerResolver>().Object,
			new Mock<ITelemetryHistoryBuffer>().Object, NullLogger<RamMonitoringEngine>.Instance,
			() => [new ProcessMemorySample(7, "private-app", 1, 10, 123, 45, 678)], () => null, new ManualRamTimeProvider());
		engine.StartRadar();
		var body = Payload(await received.Task.WaitAsync(TimeSpan.FromSeconds(5)));
		engine.StopRadar();
		await engine.DisposeAsync();
		await trace.DisposeAsync();
		Assert.Equal(123, body.GetProperty("processes")[0].GetProperty("workingSetBytes").GetInt64());
		Assert.Equal(enabled, body.TryGetProperty("benchmarkTrace", out var marker));
		if (enabled)
		{
			Assert.True(long.Parse(marker.GetProperty("acquisitionEndTicks").GetString()!) >= long.Parse(marker.GetProperty("acquisitionStartTicks").GetString()!));
			Assert.Contains(Read(writer), e => e.Stage == "ram.acquired" && e.Outcome == "global_unavailable");
		}
		Assert.DoesNotContain("private-app", writer.ToString());
		Settled(Read(writer));
	}

	[Fact]
	public async Task EqualWorkObservationModesRetainPayloadAndReportIsolatedOverhead()
	{
		const int count = 256;
		var original = new { Processes = Enumerable.Range(1, 10).Select(i => new { Pid = i, WorkingSetBytes = i * 123L }).ToArray() };
		string expected = Payload(original).GetProperty("processes").GetRawText();
		string[] modes = ["disabled", "minimal", "rich"];
		for (int trial = 0; trial < 3; trial++)
		foreach (string mode in modes.Skip(trial).Concat(modes.Take(trial)))
		{
			var writer = new StringWriter();
			await using var trace = mode == "disabled" ? null : new BenchmarkTrace(RunId, writer, rich: mode == "rich");
			using var scope = BenchmarkTrace.Use(trace, "ram");
			using var cache = new ScanCacheService(Settings(), NullLogger<ScanCacheService>.Instance);
			var outputs = new List<JsonElement>();
			var (_, proxy) = Hub((_, args) => { outputs.Add(Payload(args[0]!)); return Task.CompletedTask; });
			string path = Path.Combine(Path.GetTempPath(), "gs-observer-uncreated");
			long allocated = GC.GetAllocatedBytesForCurrentThread();
			var clock = System.Diagnostics.Stopwatch.StartNew();
			for (int i = 0; i < count; i++)
			{
				Assert.False(cache.TryGetNode(path, out _));
				BenchmarkTrace.Send(proxy, "RamUpdate", original).GetAwaiter().GetResult();
			}
			long hotTicks = clock.ElapsedTicks;
			allocated = GC.GetAllocatedBytesForCurrentThread() - allocated;
			if (trace != null) await trace.DisposeAsync();
			long drainedTicks = clock.ElapsedTicks;
			Assert.Equal(count, outputs.Count);
			Assert.All(outputs, body => {
				Assert.Equal(expected, body.GetProperty("processes").GetRawText());
				Assert.Equal(mode != "disabled", body.TryGetProperty("benchmarkTrace", out _));
			});
			Assert.Equal(count, cache.GetStats().MissCount);
			if (trace != null)
			{
				var records = Read(writer); Settled(records);
				Assert.Equal(count, records.Count(e => e.Stage == "send.RamUpdate.end" && e.Outcome == "succeeded"));
				Assert.Equal(mode == "rich" ? count : 0, records.Count(e => e.Stage == "cache.lookup"));
			}
			Console.WriteLine(JsonSerializer.Serialize(new { observation_control = mode, trial, iterations = count,
				hot_path_ms = hotTicks * 1000.0 / System.Diagnostics.Stopwatch.Frequency,
				through_sink_drain_ms = drainedTicks * 1000.0 / System.Diagnostics.Stopwatch.Frequency,
				foreground_thread_allocated_bytes = allocated, sink = "in-memory", qualification = "isolated-test-host-only" }));
		}
	}

	private sealed class HeldWriter : StringWriter
	{
		public TaskCompletionSource Entered { get; } = Gate();
		public TaskCompletionSource Release { get; } = Gate();
		public override async Task WriteLineAsync(string? value)
		{
			Entered.TrySetResult(); await Release.Task; await base.WriteLineAsync(value);
		}
	}
	private sealed class FailedWriter : StringWriter
	{
		public override Task WriteLineAsync(string? value) => Task.FromException(new IOException("controlled"));
	}
	private sealed class FinalizationFailureWriter(bool close) : StringWriter
	{
		public override Task FlushAsync() => close ? Task.CompletedTask : Task.FromException(new IOException("flush"));
		public override ValueTask DisposeAsync() => close ? ValueTask.FromException(new IOException("close")) : ValueTask.CompletedTask;
	}
	private sealed class SignallingWriter(Action<BenchmarkEvent> observed) : StringWriter
	{
		public override async Task WriteLineAsync(string? value)
		{
			await base.WriteLineAsync(value);
			observed(JsonSerializer.Deserialize<BenchmarkEvent>(value!, BenchmarkTrace.Json)!);
		}
	}
}

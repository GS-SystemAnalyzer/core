using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using System.Threading.Channels;

namespace GSSystemAnalyzer.Tests.Engine;

public class RamMonitoringEngineTests : IAsyncLifetime
{
	private readonly List<RamMonitoringEngine> _engines = new();
	public Task InitializeAsync() => Task.CompletedTask;
	public async Task DisposeAsync()
	{
		foreach (var engine in _engines) await engine.DisposeAsync();
	}
	[Fact]
	public void StartRadar_WhileFirstSendIsBlocked_RemainsIdempotent()
	{
		var (engine, sendCount, release) = CreateBlockedSendEngine();
		try
		{
			engine.StartRadar();
			Assert.Equal(1, sendCount());
			engine.StartRadar();
			Assert.Equal(1, sendCount());
		}
		finally
		{
			engine.StopRadar();
			release.TrySetResult();
		}
	}

	[Fact]
	public void StopAndRestart_WaitsForThePreviousBlockedSend()
	{
		var (engine, sendCount, release) = CreateBlockedSendEngine();
		try
		{
			engine.StartRadar();
			Assert.Equal(1, sendCount());
			engine.StopRadar();
			engine.StartRadar();
			Assert.Equal(1, sendCount());
		}
		finally
		{
			engine.StopRadar();
			release.TrySetResult();
		}
	}

	private (RamMonitoringEngine Engine, Func<int> SendCount, TaskCompletionSource Release) CreateBlockedSendEngine()
	{
		var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
		var sends = 0;
		var proxy = new Mock<IClientProxy>();
		proxy.Setup(p => p.SendCoreAsync("RamUpdate", It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Returns(() => Interlocked.Increment(ref sends) == 1 ? release.Task : Task.CompletedTask);
		var clients = new Mock<IHubClients>();
		clients.SetupGet(c => c.All).Returns(proxy.Object);
		var hub = new Mock<IHubContext<SystemHub>>();
		hub.SetupGet(h => h.Clients).Returns(clients.Object);
		var settings = new Mock<ISettingService>();
		settings.SetupGet(s => s.Current).Returns(AppSettingDto.GetFactoryDefaults());
		var resolver = new Mock<IProcessOwnerResolver>();
		resolver.Setup(r => r.Resolve(It.IsAny<int>())).Returns("SYSTEM");
		var engine = new RamMonitoringEngine(hub.Object, settings.Object, resolver.Object,
			new Mock<ITelemetryHistoryBuffer>().Object, NullLogger<RamMonitoringEngine>.Instance,
			() => new[] { new ProcessMemorySample(42, "sample", 1, 0, 123, 100, 200) },
			() => new SystemMemoryMetrics.GlobalMemoryMetrics { TotalGb = 8, ActiveGb = 2, CacheGb = 6 },
			TimeProvider.System);
		_engines.Add(engine);
		return (engine, () => Volatile.Read(ref sends), release);
	}

	private RamMonitoringEngine CreateEngine(Func<IReadOnlyList<ProcessMemorySample>>? reader = null, ManualRamTimeProvider? clock = null)
	{
		var mockHub = new Mock<IHubContext<SystemHub>>();
		var mockClients = new Mock<IHubClients>();
		var mockClient = new Mock<IClientProxy>();
		mockHub.Setup(h => h.Clients).Returns(mockClients.Object);
		mockClients.Setup(c => c.All).Returns(mockClient.Object);
		mockClient.Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Returns(Task.CompletedTask);

		var mockSettings = new Mock<ISettingService>();
		mockSettings.Setup(s => s.Current).Returns(new AppSettingDto
		{
			Monitoring = new MonitoringSettingDto { RamPollIntervalMs = 2000 }
		});

		var mockResolver = new Mock<IProcessOwnerResolver>();
		mockResolver.Setup(r => r.Resolve(It.IsAny<int>())).Returns("SYSTEM");

		var mockHistoryBuffer = new Mock<ITelemetryHistoryBuffer>();

		var engine = new RamMonitoringEngine(mockHub.Object, mockSettings.Object, mockResolver.Object,
			mockHistoryBuffer.Object, NullLogger<RamMonitoringEngine>.Instance,
			reader ?? (() => new[] { new ProcessMemorySample(42, "sample", 1, 0, 123, 100, 200) }),
			() => new SystemMemoryMetrics.GlobalMemoryMetrics { TotalGb = 8, ActiveGb = 2, CacheGb = 6 },
			clock ?? new ManualRamTimeProvider());
		_engines.Add(engine);
		return engine;
	}

	[Fact]
	public void CompletePopulation_RetainsLowCpuMemoryOutliersBeyondTheFormerCap()
	{
		var samples = Enumerable.Range(1, 250)
			.Select(pid => new ProcessMemorySample(pid, pid == 250 ? "memory-outlier" : "group", pid, 0,
				pid, pid == 250 ? 9000000000 : pid, pid * 2L)).ToArray();
		var result = CreateEngine(() => samples).CaptureProcessSnapshot();
		Assert.Equal(250, result.Count);
		Assert.Equal(9000000000, Assert.Single(result, p => p.ProcessId == 250).PrivateWorkingSetBytes);
		Assert.Equal(249, result.Count(p => p.Name == "group"));
	}

	[Fact]
	public void CpuDelta_UsesMonotonicTime_AndResetsForPidReuseOrCounterReset()
	{
		var clock = new ManualRamTimeProvider();
		var sample = new ProcessMemorySample(42, "sample", 1, 0, 123, 100, 200);
		var engine = CreateEngine(() => new[] { sample }, clock);
		Assert.Equal(0, Assert.Single(engine.CaptureProcessSnapshot()).CpuPercent);
		clock.Advance(TimeSpan.FromSeconds(1));
		sample = sample with { CpuTimeTicks = Environment.ProcessorCount * TimeSpan.TicksPerSecond / 4 };
		Assert.Equal(25, Assert.Single(engine.CaptureProcessSnapshot()).CpuPercent);
		clock.JumpUtc(TimeSpan.FromDays(-1));
		clock.Advance(TimeSpan.FromSeconds(1));
		sample = sample with { CreationTimeTicks = 2 };
		Assert.Equal(0, Assert.Single(engine.CaptureProcessSnapshot()).CpuPercent);
		clock.Advance(TimeSpan.FromSeconds(1));
		sample = sample with { CpuTimeTicks = 0 };
		Assert.Equal(0, Assert.Single(engine.CaptureProcessSnapshot()).CpuPercent);
	}

	[Fact]
	public void FailedBatch_DoesNotPruneCpuBaseline_AndSuccessfulEmptyBatchDoes()
	{
		var clock = new ManualRamTimeProvider();
		var fail = false;
		var samples = new[] { new ProcessMemorySample(42, "sample", 1, 0, 123, 100, 200) };
		var engine = CreateEngine(() => fail ? throw new IOException("sample failed") : samples, clock);
		engine.CaptureProcessSnapshot();
		clock.Advance(TimeSpan.FromSeconds(1));
		fail = true;
		Assert.Throws<IOException>(() => engine.CaptureProcessSnapshot());
		fail = false;
		clock.Advance(TimeSpan.FromSeconds(1));
		samples = new[] { samples[0] with { CpuTimeTicks = Environment.ProcessorCount * TimeSpan.TicksPerSecond / 2 } };
		Assert.Equal(25, Assert.Single(engine.CaptureProcessSnapshot()).CpuPercent);
		samples = Array.Empty<ProcessMemorySample>();
		Assert.Empty(engine.CaptureProcessSnapshot());
		clock.Advance(TimeSpan.FromSeconds(1));
		samples = new[] { new ProcessMemorySample(42, "sample", 1, TimeSpan.TicksPerSecond, 123, 100, 200) };
		Assert.Equal(0, Assert.Single(engine.CaptureProcessSnapshot()).CpuPercent);
	}

	[Fact]
	public async Task BlockedSend_DoesNotQualifyPressureOrRecordTransportTimeAsHistory()
	{
		var clock = new ManualRamTimeProvider();
		var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
		var historyCalls = 0;
		var alerts = 0;
		var proxy = new Mock<IClientProxy>();
		proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Returns<string, object?[], CancellationToken>((method, _, _) =>
			{
				if (method == "RamAlert") Interlocked.Increment(ref alerts);
				return method == "RamUpdate" ? release.Task : Task.CompletedTask;
			});
		var clients = new Mock<IHubClients>();
		clients.SetupGet(c => c.All).Returns(proxy.Object);
		var hub = new Mock<IHubContext<SystemHub>>();
		hub.SetupGet(h => h.Clients).Returns(clients.Object);
		var settings = new Mock<ISettingService>();
		var configured = AppSettingDto.GetFactoryDefaults();
		configured.Monitoring.RamPollIntervalMs = 250;
		settings.SetupGet(s => s.Current).Returns(configured);
		var history = new Mock<ITelemetryHistoryBuffer>();
		history.Setup(h => h.Record(It.IsAny<string>(), It.IsAny<double>())).Callback(() => Interlocked.Increment(ref historyCalls));
		var engine = new RamMonitoringEngine(hub.Object, settings.Object, new Mock<IProcessOwnerResolver>().Object,
			history.Object, NullLogger<RamMonitoringEngine>.Instance, () => Array.Empty<ProcessMemorySample>(),
			() => new SystemMemoryMetrics.GlobalMemoryMetrics { TotalGb = 8, ActiveGb = 7.2, CacheGb = 0.8 }, clock);
		_engines.Add(engine);
		try
		{
			engine.StartRadar();
			Assert.Equal(2, Volatile.Read(ref historyCalls));
			clock.Advance(TimeSpan.FromSeconds(11));
			Assert.Equal(0, Volatile.Read(ref alerts));
			Assert.Equal(2, Volatile.Read(ref historyCalls));
		}
		finally
		{
			engine.StopRadar();
			release.TrySetResult();
			await engine.DisposeAsync();
		}
	}


	[Theory]
	[InlineData(200, 2)]
	[InlineData(1000, 6)]
	[InlineData(5000, 11)]
	public async Task ConfiguredPolling_ControlsPublicationAndRecordsOnlyObservedHistory(int period, int historyPoints)
	{
		var (engine, clock, _, _, frames, recordedPoints) = CreateScheduledEngine(period);
		try
		{
			engine.StartRadar();
			Assert.Equal(0, await frames.ReadAsync());
			for (var i = 1; i <= 10; i++)
			{
				clock.Advance(TimeSpan.FromMilliseconds(period - 1));
				Assert.False(frames.TryRead(out _));
				clock.Advance(TimeSpan.FromMilliseconds(1));
				var timestamp = await frames.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
				Assert.Equal((double)(i * period), clock.GetElapsedTime(0, timestamp).TotalMilliseconds);
			}
			Assert.Equal(historyPoints, recordedPoints());
		}
		finally
		{
			engine.StopRadar();
			await engine.DisposeAsync();
		}
	}

	[Fact]
	public async Task PollingChange_AppliesAtTheNextSchedulingBoundaryWithoutRestart()
	{
		var (engine, clock, settings, configured, frames, _) = CreateScheduledEngine(1000);
		try
		{
			engine.StartRadar();
			Assert.Equal(0, await frames.ReadAsync());
			configured.Monitoring.RamPollIntervalMs = 5000;
			settings.Raise(s => s.OnSettingsChanged += null, settings.Object, configured);
			clock.Advance(TimeSpan.FromMilliseconds(1000));
			Assert.Equal(1000, clock.GetElapsedTime(0, await frames.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5))).TotalMilliseconds);
			clock.Advance(TimeSpan.FromMilliseconds(4999));
			Assert.False(frames.TryRead(out _));
			clock.Advance(TimeSpan.FromMilliseconds(1));
			Assert.Equal(6000, clock.GetElapsedTime(0, await frames.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5))).TotalMilliseconds);
		}
		finally
		{
			engine.StopRadar();
			await engine.DisposeAsync();
		}
	}

	private (RamMonitoringEngine Engine, ManualRamTimeProvider Clock, Mock<ISettingService> Settings,
		AppSettingDto Configured, ChannelReader<long> Frames, Func<int> HistoryPoints) CreateScheduledEngine(int period)
	{
		var clock = new ManualRamTimeProvider();
		var frames = Channel.CreateUnbounded<long>();
		var proxy = new Mock<IClientProxy>();
		proxy.Setup(p => p.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Returns<string, object?[], CancellationToken>((method, _, _) =>
			{
				if (method == "RamUpdate") frames.Writer.TryWrite(clock.GetTimestamp());
				return Task.CompletedTask;
			});
		var clients = new Mock<IHubClients>();
		clients.SetupGet(c => c.All).Returns(proxy.Object);
		var hub = new Mock<IHubContext<SystemHub>>();
		hub.SetupGet(h => h.Clients).Returns(clients.Object);
		var configured = AppSettingDto.GetFactoryDefaults();
		configured.Monitoring.RamPollIntervalMs = period;
		var settings = new Mock<ISettingService>();
		settings.SetupGet(s => s.Current).Returns(configured);
		var records = 0;
		var history = new Mock<ITelemetryHistoryBuffer>();
		history.Setup(h => h.Record(It.IsAny<string>(), It.IsAny<double>())).Callback(() => Interlocked.Increment(ref records));
		var engine = new RamMonitoringEngine(hub.Object, settings.Object, new Mock<IProcessOwnerResolver>().Object,
			history.Object, NullLogger<RamMonitoringEngine>.Instance, () => Array.Empty<ProcessMemorySample>(),
			() => new SystemMemoryMetrics.GlobalMemoryMetrics { TotalGb = 8, ActiveGb = 2, CacheGb = 6 }, clock);
		_engines.Add(engine);
		return (engine, clock, settings, configured, frames.Reader, () => Volatile.Read(ref records) / 2);
	}

	[Fact]
	public void ExecuteOrder66_EmptyList_ReturnsZero()
	{
		var engine = CreateEngine();
		var killed = engine.ExecuteOrder66(new List<int>());
		Assert.Equal(0, killed);
	}

	[Fact]
	public void ExecuteOrder66_AllInvalidPids_ReturnsZero()
	{
		var engine = CreateEngine();
		var killed = engine.ExecuteOrder66(new List<int> { -1, int.MinValue, -99 });
		Assert.Equal(0, killed);
	}

	[Fact]
	public void ExecuteOrder66_DoesNotThrowOnAnyInput()
	{
		var engine = CreateEngine();
		var ex = Record.Exception(() =>
			engine.ExecuteOrder66(new List<int> { -1, -99, int.MinValue }));
		Assert.Null(ex);
	}

	[Fact]
	public void ExecuteOrder66_NullList_ThrowsArgumentNullException()
	{
		var engine = CreateEngine();
		Assert.Throws<NullReferenceException>(() => engine.ExecuteOrder66(null!));
	}


	[Fact]
	public void StartRadar_CanBeCalledMultipleTimes_WithoutThrowing()
	{
		var engine = CreateEngine();
		var ex = Record.Exception(() =>
		{
			engine.StartRadar();
			engine.StartRadar(); // second call is a no-op (guard inside)
		});
		engine.StopRadar();
		Assert.Null(ex);
	}

	[Fact]
	public void StopRadar_BeforeStart_DoesNotThrow()
	{
		var engine = CreateEngine();
		var ex = Record.Exception(() => engine.StopRadar());
		Assert.Null(ex);
	}
}

internal sealed class ManualRamTimeProvider : TimeProvider
{
	private readonly object _lock = new();
	private readonly List<ManualTimer> _timers = new();
	private long _timestamp;
	private DateTimeOffset _utc = new(2026, 11, 2, 12, 0, 0, TimeSpan.Zero);
	public override long TimestampFrequency => TimeSpan.TicksPerSecond;
	public override long GetTimestamp() { lock (_lock) return _timestamp; }
	public override DateTimeOffset GetUtcNow() { lock (_lock) return _utc; }
	internal void JumpUtc(TimeSpan duration) { lock (_lock) _utc += duration; }
	internal void Advance(TimeSpan duration)
	{
		List<ManualTimer> due;
		lock (_lock)
		{
			_timestamp += duration.Ticks;
			_utc += duration;
			due = _timers.Where(t => !t.Disposed && t.Due <= _timestamp).ToList();
			foreach (var timer in due) timer.Due = timer.Period > 0 ? _timestamp + timer.Period : long.MaxValue;
		}
		foreach (var timer in due) timer.Callback(timer.State);
	}
	public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
	{
		var timer = new ManualTimer(this, callback, state);
		lock (_lock) _timers.Add(timer);
		timer.Change(dueTime, period);
		return timer;
	}
	private sealed class ManualTimer(ManualRamTimeProvider owner, TimerCallback callback, object? state) : ITimer
	{
		internal readonly TimerCallback Callback = callback;
		internal readonly object? State = state;
		internal long Due;
		internal long Period;
		internal bool Disposed;
		public bool Change(TimeSpan dueTime, TimeSpan period)
		{
			lock (owner._lock)
			{
				if (Disposed) return false;
				Due = dueTime == Timeout.InfiniteTimeSpan ? long.MaxValue : owner._timestamp + dueTime.Ticks;
				Period = period == Timeout.InfiniteTimeSpan ? -1 : period.Ticks;
				return true;
			}
		}
		public void Dispose() { lock (owner._lock) { Disposed = true; owner._timers.Remove(this); } }
		public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
	}
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Tests.Engine;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services
{
	public class RamAlertIntegrationTests : IAsyncLifetime
	{
		private readonly List<TestContext> _contexts = new();
		public Task InitializeAsync() => Task.CompletedTask;
		public async Task DisposeAsync()
		{
			foreach (var context in _contexts) await context.Engine.DisposeAsync();
		}
		private class TestContext
		{
			public RamMonitoringEngine Engine { get; set; } = null!;
			public ThresholdAlertTracker Tracker { get; set; } = null!;
			public Mock<ISettingService> SettingsMock { get; set; } = null!;
			public AppSettingDto AppSettings { get; set; } = null!;
			public List<(string Method, object? Payload)> Broadcasts { get; set; } = new();
			public ManualRamTimeProvider Clock { get; } = new();
			public DateTimeOffset CurrentTime => Clock.GetUtcNow();

			public void AdvanceTime(TimeSpan duration) => Clock.Advance(duration);
			public async Task ObserveForTenSecondsAsync(SystemMemoryMetrics.GlobalMemoryMetrics metrics, List<ProcessTelemetry> processes)
			{
				for (var i = 0; i <= 40; i++)
				{
					await Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
					if (i < 40) AdvanceTime(TimeSpan.FromMilliseconds(250));
				}
			}
		}

		private TestContext CreateContext(
			int ramThresholdPercent = 85,
			int ramMinimumFreeMb = 1024)
		{
			var hubMock = new Mock<IHubContext<SystemHub>>();
			var clientsMock = new Mock<IHubClients>();
			var clientProxyMock = new Mock<IClientProxy>();

			hubMock.Setup(h => h.Clients).Returns(clientsMock.Object);
			clientsMock.Setup(c => c.All).Returns(clientProxyMock.Object);

			var broadcasts = new List<(string Method, object? Payload)>();
			clientProxyMock
				.Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
				.Callback<string, object?[], CancellationToken>((method, args, _) =>
				{
					broadcasts.Add((method, args?.FirstOrDefault()));
				})
				.Returns(Task.CompletedTask);

			var appSettings = new AppSettingDto
			{
				Monitoring = new MonitoringSettingDto { RamPollIntervalMs = 250 },
				Alerts = new AlertSettingDto
				{
					RamThresholdPercent = ramThresholdPercent,
					RamMinimumFreeMb = ramMinimumFreeMb
				}
			};

			var settingsMock = new Mock<ISettingService>();
			settingsMock.Setup(s => s.Current).Returns(appSettings);

			var ownerResolver = new Mock<IProcessOwnerResolver>();
			ownerResolver.Setup(r => r.Resolve(It.IsAny<int>())).Returns("SYSTEM");

			var historyBuffer = new Mock<ITelemetryHistoryBuffer>();

			var tracker = new ThresholdAlertTracker(
				requiredConsecutive: 1,
				hysteresisBand: 5.0,
				reAlertIncrease: 5.0,
				cooldownInterval: TimeSpan.FromMinutes(60));

			var ctx = new TestContext
			{
				SettingsMock = settingsMock,
				AppSettings = appSettings,
				Broadcasts = broadcasts,
				Tracker = tracker
			};

			ctx.Engine = new RamMonitoringEngine(
				hubMock.Object,
				settingsMock.Object,
				ownerResolver.Object,
				historyBuffer.Object,
				NullLogger<RamMonitoringEngine>.Instance,
				() => Array.Empty<ProcessMemorySample>(),
				() => null,
				ctx.Clock,
				() => ctx.CurrentTime,
				tracker);

			_contexts.Add(ctx);
			return ctx;
		}

		private static SystemMemoryMetrics.GlobalMemoryMetrics MakeMetrics(
			double totalGb, double activeGb)
		{
			return new SystemMemoryMetrics.GlobalMemoryMetrics
			{
				TotalGb = totalGb,
				ActiveGb = activeGb,
				CacheGb = totalGb - activeGb, // CacheGb = available physical RAM
				SwapGb = 0,
				TotalSwapGb = totalGb
			};
		}

		private static List<ProcessTelemetry> MakeProcesses(params (int pid, string name, long workingSetBytes)[] procs)
		{
			return procs.Select(p => new ProcessTelemetry
			{
				ProcessId = p.pid,
				Name = p.name,
				WorkingSetBytes = p.workingSetBytes,
				CpuPercent = 0,
				Status = "RUNNING",
				User = "SYSTEM"
			}).ToList();
		}

		// ── Dual condition tests ────────────────────────────────────────

		[Fact]
		public async Task DualCondition_PercentOnlyBreached_DoesNotAlert()
		{
			// 64 GB total, 54.4 GB active = 85% used, but 9.6 GB free > 1024 MB floor
			var ctx = CreateContext(ramThresholdPercent: 85, ramMinimumFreeMb: 1024);
			var metrics = MakeMetrics(totalGb: 64.0, activeGb: 54.4);
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			await ctx.Engine.EvaluateRamPressureAsync(metrics, procs, CancellationToken.None);

			Assert.Empty(ctx.Broadcasts);
			Assert.False(ctx.Engine.IsRamAlerting);
		}

		[Fact]
		public async Task DualCondition_AbsoluteOnlyBreached_DoesNotAlert()
		{
			// 80% used with 0.8 GB free breaches only the absolute floor.
			var ctx = CreateContext(ramThresholdPercent: 85, ramMinimumFreeMb: 1024);
			var metrics = MakeMetrics(totalGb: 4.0, activeGb: 3.2);
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			await ctx.Engine.EvaluateRamPressureAsync(metrics, procs, CancellationToken.None);

			Assert.Empty(ctx.Broadcasts);
		}

		[Fact]
		public async Task DualCondition_BothBreached_AlertsAfterDebounce()
		{
			// 8 GB total, 7.2 GB active = 90% used, 0.8 GB free < 1024 MB floor
			var ctx = CreateContext(ramThresholdPercent: 85, ramMinimumFreeMb: 1024);
			var metrics = MakeMetrics(totalGb: 8.0, activeGb: 7.2);
			var procs = MakeProcesses(
				(4812, "chrome", 3_400_000_000),
				(1120, "dotnet", 1_200_000_000),
				(9044, "Code", 1_000_000_000),
				(5555, "explorer", 200_000_000));

			for (int i = 0; i < 40; i++)
			{
				await ctx.Engine.EvaluateRamPressureAsync(metrics, procs, CancellationToken.None);
				ctx.AdvanceTime(TimeSpan.FromMilliseconds(250));
			}
			Assert.Empty(ctx.Broadcasts);

			// Ten observed seconds, not five fast samples, qualify the alert.
			await ctx.Engine.EvaluateRamPressureAsync(metrics, procs, CancellationToken.None);

			Assert.Single(ctx.Broadcasts);
			Assert.Equal("RamAlert", ctx.Broadcasts[0].Method);
			Assert.True(ctx.Engine.IsRamAlerting);
		}

		[Fact]
		public async Task SingleSpike_DoesNotAlert_WithDebounce()
		{
			var ctx = CreateContext();
			var highMetrics = MakeMetrics(totalGb: 8.0, activeGb: 7.2);
			var lowMetrics = MakeMetrics(totalGb: 8.0, activeGb: 4.0);
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			// 1 tick above
			await ctx.Engine.EvaluateRamPressureAsync(highMetrics, procs, CancellationToken.None);
			ctx.AdvanceTime(TimeSpan.FromMilliseconds(250));

			// 1 tick below — resets counter
			await ctx.Engine.EvaluateRamPressureAsync(lowMetrics, procs, CancellationToken.None);

			Assert.Empty(ctx.Broadcasts);
			Assert.False(ctx.Engine.IsRamAlerting);
		}

		// ── Top consumers ───────────────────────────────────────────────

		[Fact]
		public async Task TopConsumers_ContainsTop3ByWorkingSet()
		{
			var ctx = CreateContext();
			var metrics = MakeMetrics(totalGb: 8.0, activeGb: 7.2);
			var procs = MakeProcesses(
				(100, "small", 100_000_000),
				(200, "chrome", 3_400_000_000),
				(300, "dotnet", 1_200_000_000),
				(400, "Code", 1_000_000_000),
				(500, "explorer", 200_000_000));

			procs[0].PrivateWorkingSetBytes = 9000000000;
			procs[4].CommitBytes = 12000000000;
			await ctx.ObserveForTenSecondsAsync(metrics, procs);

			Assert.Single(ctx.Broadcasts);
			var payload = ctx.Broadcasts[0].Payload as RamAlertPayload;
			Assert.NotNull(payload);
			Assert.Equal(3, payload!.TopConsumers.Count);

			// Verify sorted by working set descending
			Assert.Equal("chrome", payload.TopConsumers[0].Name);
			Assert.Equal(200, payload.TopConsumers[0].Pid);
			Assert.Equal("dotnet", payload.TopConsumers[1].Name);
			Assert.Equal("Code", payload.TopConsumers[2].Name);
		}

		// ── Severity escalation ─────────────────────────────────────────

		[Fact]
		public async Task Severity_Below256MB_EmitsCritical()
		{
			var ctx = CreateContext(ramMinimumFreeMb: 1024);
			// 8 GB total, 7.8 GB active = 0.2 GB (200 MB) free — below 256 MB critical threshold
			var metrics = MakeMetrics(totalGb: 8.0, activeGb: 7.8);
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			await ctx.ObserveForTenSecondsAsync(metrics, procs);

			Assert.Single(ctx.Broadcasts);
			var payload = ctx.Broadcasts[0].Payload as RamAlertPayload;
			Assert.NotNull(payload);
			Assert.Equal("critical", payload!.Severity);
		}

		[Fact]
		public async Task Severity_Above256MB_EmitsWarning()
		{
			var ctx = CreateContext(ramMinimumFreeMb: 1024);
			// 8 GB total, 7.2 GB active = 0.8 GB (800 MB) free — above 256 MB, below 1024 MB floor
			var metrics = MakeMetrics(totalGb: 8.0, activeGb: 7.2);
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			await ctx.ObserveForTenSecondsAsync(metrics, procs);

			Assert.Single(ctx.Broadcasts);
			var payload = ctx.Broadcasts[0].Payload as RamAlertPayload;
			Assert.NotNull(payload);
			Assert.Equal("warning", payload!.Severity);
		}

		// ── Alert cleared ───────────────────────────────────────────────

		[Fact]
		public async Task AlertCleared_EmitsRamAlertCleared()
		{
			var ctx = CreateContext();
			var highMetrics = MakeMetrics(totalGb: 8.0, activeGb: 7.2);
			var recoveredMetrics = MakeMetrics(totalGb: 8.0, activeGb: 5.0); // 62.5% — well below 85 - 5 = 80%
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			// Fire
			await ctx.ObserveForTenSecondsAsync(highMetrics, procs);
			Assert.Single(ctx.Broadcasts);
			Assert.True(ctx.Engine.IsRamAlerting);

			ctx.AdvanceTime(TimeSpan.FromSeconds(30));

			// Recover
			await ctx.Engine.EvaluateRamPressureAsync(recoveredMetrics, procs, CancellationToken.None);
			Assert.Equal(2, ctx.Broadcasts.Count);
			Assert.Equal("RamAlertCleared", ctx.Broadcasts[1].Method);
			Assert.False(ctx.Engine.IsRamAlerting);
		}

		// ── Payload fields ──────────────────────────────────────────────

		[Fact]
		public async Task Payload_ContainsAllExpectedFields()
		{
			var ctx = CreateContext(ramThresholdPercent: 85, ramMinimumFreeMb: 1024);
			var metrics = MakeMetrics(totalGb: 8.0, activeGb: 7.2);
			var procs = MakeProcesses(
				(4812, "chrome", 3_400_000_000),
				(1120, "dotnet", 1_200_000_000),
				(9044, "Code", 1_000_000_000));

			await ctx.ObserveForTenSecondsAsync(metrics, procs);

			var payload = ctx.Broadcasts[0].Payload as RamAlertPayload;
			Assert.NotNull(payload);
			Assert.Equal(90.0, payload!.UsedPercent);
			Assert.True(payload.AvailablePhysicalBytes > 0);
			Assert.False(string.IsNullOrEmpty(payload.AvailableFormatted));
			Assert.Equal(85.0, payload.ThresholdPercent);
			Assert.Equal(1024, payload.MinimumFreeMb);
			Assert.Equal("warning", payload.Severity);
			Assert.Equal(10, payload.SustainedForSeconds);
			Assert.Equal(3, payload.TopConsumers.Count);
		}

		// ── Settings change ─────────────────────────────────────────────

		[Fact]
		public async Task SettingsChange_NewThreshold_AffectsAlertEvaluation()
		{
			var ctx = CreateContext(ramThresholdPercent: 85, ramMinimumFreeMb: 1024);
			// 8 GB total, 6.8 GB active = 85% used, 1.2 GB free > 1024 MB → percent exactly at threshold
			// but 1.2 GB free is above 1024 MB floor → no alert
			var metrics = MakeMetrics(totalGb: 8.0, activeGb: 6.8);
			var procs = MakeProcesses((1, "chrome", 1_000_000_000));

			await ctx.Engine.EvaluateRamPressureAsync(metrics, procs, CancellationToken.None);
			Assert.Empty(ctx.Broadcasts);

			// Lower the free MB threshold so the absolute floor is now breached
			ctx.AppSettings.Alerts.RamMinimumFreeMb = 2048; // 2 GB — now 1.2 GB free < 2048 MB
			ctx.SettingsMock.Raise(s => s.OnSettingsChanged += null, ctx.SettingsMock.Object, ctx.AppSettings);

			await ctx.ObserveForTenSecondsAsync(metrics, procs);
			Assert.Single(ctx.Broadcasts);
			Assert.Equal("RamAlert", ctx.Broadcasts[0].Method);
		}

		[Theory]
		[InlineData(200)]
		[InlineData(1000)]
		[InlineData(5000)]
		public async Task Qualification_FiresAtTenObservedSeconds_NotAtNinePointNineNineNine(int period)
		{
			var ctx = CreateContext();
			ctx.AppSettings.Monitoring.RamPollIntervalMs = period;
			ctx.SettingsMock.Raise(s => s.OnSettingsChanged += null, ctx.SettingsMock.Object, ctx.AppSettings);
			var metrics = MakeMetrics(8, 7.2);
			var processes = MakeProcesses((42, "sample", 123));
			var elapsed = 0;
			while (elapsed < 9999)
			{
				await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
				var step = Math.Min(period, 9999 - elapsed);
				ctx.AdvanceTime(TimeSpan.FromMilliseconds(step));
				elapsed += step;
			}
			await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
			Assert.Empty(ctx.Broadcasts);
			ctx.Clock.JumpUtc(TimeSpan.FromDays(-1));
			ctx.AdvanceTime(TimeSpan.FromMilliseconds(1));
			await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
			Assert.Equal(10, Assert.IsType<RamAlertPayload>(Assert.Single(ctx.Broadcasts).Payload).SustainedForSeconds);
		}

		[Fact]
		public async Task ExcessiveObservationGap_BreaksPendingQualification()
		{
			var ctx = CreateContext();
			var metrics = MakeMetrics(8, 7.2);
			var processes = MakeProcesses((42, "sample", 123));
			await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
			ctx.AdvanceTime(TimeSpan.FromSeconds(11));
			await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
			Assert.Empty(ctx.Broadcasts);
			await ctx.ObserveForTenSecondsAsync(metrics, processes);
			Assert.Single(ctx.Broadcasts);
		}

		[Fact]
		public async Task CadenceOnlyChange_PreservesElapsedPressureQualification()
		{
			var ctx = CreateContext();
			ctx.AppSettings.Monitoring.RamPollIntervalMs = 1000;
			ctx.SettingsMock.Raise(s => s.OnSettingsChanged += null, ctx.SettingsMock.Object, ctx.AppSettings);
			var metrics = MakeMetrics(8, 7.2);
			var processes = MakeProcesses((42, "sample", 123));
			for (var i = 0; i < 5; i++)
			{
				await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
				ctx.AdvanceTime(TimeSpan.FromMilliseconds(1000));
			}
			ctx.AppSettings.Monitoring.RamPollIntervalMs = 200;
			ctx.SettingsMock.Raise(s => s.OnSettingsChanged += null, ctx.SettingsMock.Object, ctx.AppSettings);
			for (var i = 0; i < 25; i++)
			{
				await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
				ctx.AdvanceTime(TimeSpan.FromMilliseconds(200));
			}
			Assert.Empty(ctx.Broadcasts);
			await ctx.Engine.EvaluateRamPressureAsync(metrics, processes, CancellationToken.None);
			Assert.Equal(10, Assert.IsType<RamAlertPayload>(Assert.Single(ctx.Broadcasts).Payload).SustainedForSeconds);
		}
	}
}

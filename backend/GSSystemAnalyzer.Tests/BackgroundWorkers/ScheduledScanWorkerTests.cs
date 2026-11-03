using GSSystemAnalyzer.BackgroundWorkers;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Tests.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.BackgroundWorkers;

public class ScheduledScanWorkerTests : IDisposable
{
	private readonly ScannerCacheTestScope _cacheScope = new();
	private readonly List<DiskScannerEngine> _scanners = new();

	private DiskScannerEngine BuildScanner(bool isScanning = false)
	{
		var hubMock = new Mock<IHubContext<SystemHub>>();
		var settingsMock = new Mock<ISettingService>();
		settingsMock.Setup(s => s.Current).Returns(new AppSettingDto());

		var scanner = new DiskScannerEngine(hubMock.Object, settingsMock.Object, NullLogger<DiskScannerEngine>.Instance,
			cacheFilePath: _cacheScope.CreateCachePath());
		_scanners.Add(scanner);

		// To simulate IsScanning, we'd need to acquire the semaphore.
		// For tests where isScanning = true, we acquire it before the test.
		return scanner;
	}

	public void Dispose()
	{
		foreach (var scanner in _scanners) scanner.Dispose();
		_cacheScope.Dispose();
	}

	private static Mock<ISettingService> BuildSettingsMock(bool enabled = true, int interval = 15)
	{
		var mock = new Mock<ISettingService>();
		var settings = new AppSettingDto();
		settings.Monitoring.EnableScheduledScans = enabled;
		settings.Monitoring.ScheduledScanIntervalMinutes = interval;
		mock.Setup(s => s.Current).Returns(settings);
		return mock;
	}

	private static Mock<IHubContext<SystemHub>> BuildHubMock()
	{
		var mock = new Mock<IHubContext<SystemHub>>();
		var clientsMock = new Mock<IHubClients>();
		var clientProxyMock = new Mock<IClientProxy>();
		clientsMock.Setup(c => c.All).Returns(clientProxyMock.Object);
		mock.Setup(h => h.Clients).Returns(clientsMock.Object);
		return mock;
	}

	private static Mock<IServiceScopeFactory> BuildScopeFactory(Mock<IDiskOperationService>? diskServiceMock = null)
	{
		diskServiceMock ??= new Mock<IDiskOperationService>();
		diskServiceMock.Setup(d => d.BeginScan(It.IsAny<Guid?>())).Returns(Guid.NewGuid());

		var serviceProviderMock = new Mock<IServiceProvider>();
		serviceProviderMock
			.Setup(sp => sp.GetService(typeof(IDiskOperationService)))
			.Returns(diskServiceMock.Object);
		// The worker reads back the cached diff after a scan; a stub returning null is enough.
		serviceProviderMock
			.Setup(sp => sp.GetService(typeof(IScanDiffService)))
			.Returns(new Mock<IScanDiffService>().Object);

		var scopeMock = new Mock<IServiceScope>();
		scopeMock.Setup(s => s.ServiceProvider).Returns(serviceProviderMock.Object);

		var factoryMock = new Mock<IServiceScopeFactory>();
		factoryMock.Setup(f => f.CreateScope()).Returns(scopeMock.Object);

		return factoryMock;
	}

	[Fact]
	public async Task Worker_RespectsGlobalToggle_WhenDisabled()
	{
		var settingsMock = BuildSettingsMock(enabled: false);
		var scheduleMock = new Mock<IScheduleService>();

		using var worker = new ScheduledScanWorker(
			scheduleMock.Object,
			settingsMock.Object,
			BuildScanner(),
			BuildScopeFactory().Object,
			BuildHubMock().Object,
			NullLogger<ScheduledScanWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		// Should never call GetDueSchedules when disabled
		scheduleMock.Verify(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()), Times.Never);
	}

	[Fact]
	public async Task Worker_ExecutesDueScan()
	{
		var settingsMock = BuildSettingsMock(enabled: true);
		var scheduleMock = new Mock<IScheduleService>();

		var dueSchedule = new ScheduledScan
		{
			Id = Guid.NewGuid(),
			Type = ScanType.Directory,
			Path = "C:/",
			Kind = ScheduleKind.Interval,
			IntervalMinutes = 1,
			Enabled = true,
			NextRun = DateTimeOffset.UtcNow.AddMinutes(-1) // Past due
		};

		// First call returns empty (for EnsureDefaultSchedule check), subsequent calls return due
		scheduleMock.Setup(s => s.GetAll()).Returns(new List<ScheduledScan> { dueSchedule });
		scheduleMock
			.Setup(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<ScheduledScan> { dueSchedule });

		var diskServiceMock = new Mock<IDiskOperationService>();
		diskServiceMock.Setup(d => d.BeginScan(It.IsAny<Guid?>())).Returns(Guid.NewGuid());
		diskServiceMock
			.Setup(d => d.ScanDirectory(It.IsAny<string>(), It.IsAny<Guid>()))
			.Returns(new List<StorageNode>());

		using var worker = new ScheduledScanWorker(
			scheduleMock.Object,
			settingsMock.Object,
			BuildScanner(),
			BuildScopeFactory(diskServiceMock).Object,
			BuildHubMock().Object,
			NullLogger<ScheduledScanWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		// Verify ScanDirectory was called with the correct path
		diskServiceMock.Verify(
			d => d.ScanDirectory("C:/", It.IsAny<Guid>()),
			Times.Once);

		// Verify MarkCompleted was called
		scheduleMock.Verify(
			s => s.MarkCompleted(dueSchedule.Id, It.IsAny<DateTimeOffset>()),
			Times.Once);
	}

	[Fact]
	public async Task Worker_SkipsWhenScanIsRunning()
	{
		var settingsMock = BuildSettingsMock(enabled: true);
		var scheduleMock = new Mock<IScheduleService>();

		var dueSchedule = new ScheduledScan
		{
			Id = Guid.NewGuid(),
			Type = ScanType.Directory,
			Path = "C:/",
			Kind = ScheduleKind.Interval,
			IntervalMinutes = 1,
			Enabled = true,
			NextRun = DateTimeOffset.UtcNow.AddMinutes(-1)
		};

		scheduleMock.Setup(s => s.GetAll()).Returns(new List<ScheduledScan> { dueSchedule });
		scheduleMock
			.Setup(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<ScheduledScan> { dueSchedule });

		var diskServiceMock = new Mock<IDiskOperationService>();
		var scanner = BuildScanner();

		// Simulate a scan in progress by acquiring the semaphore
		// We need to use reflection or a different approach since _scanLock is private
		// Instead, we'll use the CalculateMissingSizesAsync path won't work here.
		// The cleanest approach: the worker checks engine.IsScanning, which checks
		// _scanLock.CurrentCount == 0. We can make the semaphore busy by doing:
		var lockField = typeof(DiskScannerEngine)
			.GetField("_scanLock", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!;
		var semaphore = (SemaphoreSlim)lockField.GetValue(scanner)!;
		semaphore.Wait(); // Acquire → IsScanning == true

		try
		{
			using var worker = new ScheduledScanWorker(
				scheduleMock.Object,
				settingsMock.Object,
				scanner,
				BuildScopeFactory(diskServiceMock).Object,
				BuildHubMock().Object,
				NullLogger<ScheduledScanWorker>.Instance);

			await worker.TickAsync(CancellationToken.None);

			// Scan should have been skipped — ScanDirectory never called
			diskServiceMock.Verify(
				d => d.ScanDirectory(It.IsAny<string>(), It.IsAny<Guid>()),
				Times.Never);
		}
		finally
		{
			semaphore.Release();
		}
	}

	[Fact]
	public async Task Worker_BroadcastsAutoScanComplete()
	{
		var settingsMock = BuildSettingsMock(enabled: true);
		var scheduleMock = new Mock<IScheduleService>();

		var dueSchedule = new ScheduledScan
		{
			Id = Guid.NewGuid(),
			Type = ScanType.Directory,
			Path = "C:/",
			Kind = ScheduleKind.Interval,
			IntervalMinutes = 1,
			Enabled = true,
			NextRun = DateTimeOffset.UtcNow.AddMinutes(-1)
		};

		scheduleMock.Setup(s => s.GetAll()).Returns(new List<ScheduledScan> { dueSchedule });
		scheduleMock
			.Setup(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<ScheduledScan> { dueSchedule });

		var diskServiceMock = new Mock<IDiskOperationService>();
		diskServiceMock.Setup(d => d.BeginScan(It.IsAny<Guid?>())).Returns(Guid.NewGuid());
		diskServiceMock
			.Setup(d => d.ScanDirectory(It.IsAny<string>(), It.IsAny<Guid>()))
			.Returns(new List<StorageNode>());

		var hubMock = BuildHubMock();
		var clientProxyMock = new Mock<IClientProxy>();
		hubMock.Setup(h => h.Clients.All).Returns(clientProxyMock.Object);

		using var worker = new ScheduledScanWorker(
			scheduleMock.Object,
			settingsMock.Object,
			BuildScanner(),
			BuildScopeFactory(diskServiceMock).Object,
			hubMock.Object,
			NullLogger<ScheduledScanWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		// Verify AutoScanComplete was broadcast
		clientProxyMock.Verify(
			c => c.SendCoreAsync(
				"AutoScanComplete",
				It.IsAny<object?[]>(),
				It.IsAny<CancellationToken>()),
			Times.Once);
	}

	[Fact]
	public async Task Worker_SeedsDefaultSchedule_WhenNoneExists()
	{
		var settingsMock = BuildSettingsMock(enabled: true, interval: 30);
		var scheduleMock = new Mock<IScheduleService>();

		// No existing schedules
		scheduleMock.Setup(s => s.GetAll()).Returns(new List<ScheduledScan>());
		scheduleMock
			.Setup(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<ScheduledScan>());
		scheduleMock
			.Setup(s => s.Create(It.IsAny<CreateScheduleRequest>()))
			.Returns(new ScheduledScan { Id = Guid.NewGuid(), Path = "C:/" });

		using var worker = new ScheduledScanWorker(
			scheduleMock.Object,
			settingsMock.Object,
			BuildScanner(),
			BuildScopeFactory().Object,
			BuildHubMock().Object,
			NullLogger<ScheduledScanWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		// Should have created a default schedule
		scheduleMock.Verify(
			s => s.Create(It.Is<CreateScheduleRequest>(r =>
				r.Kind == ScheduleKind.Interval &&
				r.IntervalMinutes == 30 &&
				r.Type == ScanType.Directory &&
				r.Enabled == true)),
			Times.Once);
	}

	[Fact]
	public async Task Worker_DoesNotSeedDefault_WhenOneAlreadyExists()
	{
		var settingsMock = BuildSettingsMock(enabled: true, interval: 15);
		var scheduleMock = new Mock<IScheduleService>();

		var systemDrive = Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\";
		var normalizedDrive = systemDrive.Replace("\\", "/");

		// Already has an interval schedule for the system drive
		scheduleMock.Setup(s => s.GetAll()).Returns(new List<ScheduledScan>
		{
			new()
			{
				Id = Guid.NewGuid(),
				Path = normalizedDrive,
				Kind = ScheduleKind.Interval,
				IntervalMinutes = 15,
				Enabled = true
			}
		});

		scheduleMock
			.Setup(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<ScheduledScan>());

		using var worker = new ScheduledScanWorker(
			scheduleMock.Object,
			settingsMock.Object,
			BuildScanner(),
			BuildScopeFactory().Object,
			BuildHubMock().Object,
			NullLogger<ScheduledScanWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		// Should NOT create another default
		scheduleMock.Verify(
			s => s.Create(It.IsAny<CreateScheduleRequest>()),
			Times.Never);
	}

	[Fact]
	public async Task Worker_HandlesErrorGracefully()
	{
		var settingsMock = BuildSettingsMock(enabled: true);
		var scheduleMock = new Mock<IScheduleService>();

		var dueSchedule = new ScheduledScan
		{
			Id = Guid.NewGuid(),
			Type = ScanType.Directory,
			Path = "C:/",
			Kind = ScheduleKind.Interval,
			IntervalMinutes = 1,
			Enabled = true,
			NextRun = DateTimeOffset.UtcNow.AddMinutes(-1)
		};

		scheduleMock.Setup(s => s.GetAll()).Returns(new List<ScheduledScan> { dueSchedule });
		scheduleMock
			.Setup(s => s.GetDueSchedules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<ScheduledScan> { dueSchedule });

		var diskServiceMock = new Mock<IDiskOperationService>();
		diskServiceMock.Setup(d => d.BeginScan(It.IsAny<Guid?>())).Returns(Guid.NewGuid());
		diskServiceMock
			.Setup(d => d.ScanDirectory(It.IsAny<string>(), It.IsAny<Guid>()))
			.Throws(new IOException("Disk read error"));

		using var worker = new ScheduledScanWorker(
			scheduleMock.Object,
			settingsMock.Object,
			BuildScanner(),
			BuildScopeFactory(diskServiceMock).Object,
			BuildHubMock().Object,
			NullLogger<ScheduledScanWorker>.Instance);

		// Should not throw — error handled gracefully
		await worker.TickAsync(CancellationToken.None);

		// MarkCompleted should still be called (to advance NextRun and avoid infinite retries)
		scheduleMock.Verify(
			s => s.MarkCompleted(dueSchedule.Id, It.IsAny<DateTimeOffset>()),
			Times.Once);
	}
}

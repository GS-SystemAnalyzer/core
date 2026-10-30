using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.DependencyInjection;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Controllers
{
	public class StorageControllerCancellationTests
	{
		// A directory guaranteed to exist so Directory.Exists() passes.
		private static readonly string TempDir = Path.GetTempPath();
		private static string TempRoot => Path.GetPathRoot(TempDir)!;

		private static Mock<IDriveDetectionService> DriveServiceWithReadyRoot()
		{
			var drive = new Mock<IDriveDetectionService>();
			drive.Setup(d => d.GetReadyDrives())
				 .Returns(new List<DriveMetric> { new() { Name = TempRoot, IsReady = true } });
			return drive;
		}

		private static Mock<IServiceScopeFactory> ScopeFactoryFor(IDiskOperationService diskService)
		{
			var provider = new Mock<IServiceProvider>();
			provider.Setup(p => p.GetService(typeof(IDiskOperationService))).Returns(diskService);

			var scope = new Mock<IServiceScope>();
			scope.Setup(s => s.ServiceProvider).Returns(provider.Object);

			var factory = new Mock<IServiceScopeFactory>();
			factory.Setup(f => f.CreateScope()).Returns(scope.Object);
			return factory;
		}

		private static StorageController BuildController(
			IDiskOperationService diskService,
			IServiceScopeFactory? scopeFactory = null,
			IDuplicateFileDetector? duplicateDetector = null)
		{
			return new StorageController(
				diskService,
				duplicateDetector ?? Mock.Of<IDuplicateFileDetector>(),
				scopeFactory ?? ScopeFactoryFor(diskService).Object);
		}

		[Fact]
		public async Task ScanDirectory_ReturnsOk_WhenScanSucceeds()
		{
			var disk = new Mock<IDiskOperationService>();
			var id = Guid.NewGuid();
			disk.Setup(s => s.BeginScan(It.IsAny<Guid?>())).Returns(id);
			disk.Setup(s => s.ScanDirectory(It.IsAny<string>(), id)).Returns(new List<StorageNode>());

			var controller = BuildController(disk.Object);

			var result = await controller.ScanDirectory(
				new ScanRequest { Root = TempDir }, DriveServiceWithReadyRoot().Object);

			Assert.IsType<OkObjectResult>(result);
		}

		[Fact]
		public async Task ScanDirectory_Returns499_WhenScanIsCanceled()
		{
			var disk = new Mock<IDiskOperationService>();
			var id = Guid.NewGuid();
			disk.Setup(s => s.BeginScan(It.IsAny<Guid?>())).Returns(id);
			disk.Setup(s => s.ScanDirectory(It.IsAny<string>(), id))
				.Throws<OperationCanceledException>();

			var controller = BuildController(disk.Object);

			var result = await controller.ScanDirectory(
				new ScanRequest { Root = TempDir }, DriveServiceWithReadyRoot().Object);

			var objectResult = Assert.IsType<ObjectResult>(result);
			Assert.Equal(499, objectResult.StatusCode);
		}

		[Fact]
		public async Task ScanDirectory_EstablishesToken_BeforeScanning()
		{
			// Regression guard for the bug this PR fixes: scan must call BeginScan()
			// BEFORE ScanDirectory, otherwise it runs with a stale/None token.
			var callOrder = new List<string>();
			var id = Guid.NewGuid();

			var disk = new Mock<IDiskOperationService>();
			disk.Setup(s => s.BeginScan(It.IsAny<Guid?>()))
				.Callback(() => callOrder.Add("BeginScan"))
				.Returns(id);
			disk.Setup(s => s.ScanDirectory(It.IsAny<string>(), id))
				.Callback(() => callOrder.Add("ScanDirectory"))
				.Returns(new List<StorageNode>());

			var controller = BuildController(disk.Object);

			await controller.ScanDirectory(
				new ScanRequest { Root = TempDir }, DriveServiceWithReadyRoot().Object);

			Assert.Equal(new[] { "BeginScan", "ScanDirectory" }, callOrder);
		}

		[Fact]
		public async Task ScanDirectory_ReturnsBadRequest_WhenDriveNotReady()
		{
			var disk = new Mock<IDiskOperationService>();
			var drive = new Mock<IDriveDetectionService>();
			drive.Setup(d => d.GetReadyDrives()).Returns(new List<DriveMetric>()); // none ready

			var controller = BuildController(disk.Object);

			var result = await controller.ScanDirectory(
				new ScanRequest { Root = TempDir }, drive.Object);

			Assert.IsType<BadRequestObjectResult>(result);
			disk.Verify(s => s.BeginScan(It.IsAny<Guid?>()), Times.Never); // must not start a scan on bad input
		}

		[Fact]
		public void AbortScan_DelegatesToDiskService()
		{
			var disk = new Mock<IDiskOperationService>();
			var controller = BuildController(disk.Object);

			var result = controller.AbortScan();

			Assert.IsType<OkObjectResult>(result);
			disk.Verify(s => s.TriggerScanAbort(null), Times.Once);
		}

		[Fact]
		public void StreamSector_ReturnsInitiated_AndBeginsScanSynchronously()
		{
			var disk = new Mock<IDiskOperationService>();
			var id = Guid.NewGuid();
			disk.Setup(s => s.BeginScan(It.IsAny<Guid?>())).Returns(id);
			disk.Setup(s => s.ScanDirectory(It.IsAny<string>(), id)).Returns(new List<StorageNode>());

			var controller = BuildController(disk.Object, ScopeFactoryFor(disk.Object).Object);

			var result = controller.StreamDirectorySection(
				Mock.Of<IHubContext<SystemHub>>(),
				DriveServiceWithReadyRoot().Object,
				TempDir,
				null);

			var ok = Assert.IsType<OkObjectResult>(result);
			var payload = Assert.IsType<ApiResponse<object>>(ok.Value);
			Assert.True(payload.Success);
			disk.Verify(s => s.BeginScan(It.IsAny<Guid?>()), Times.Once); // token established before returning
		}

		[Fact]
		public async Task StreamSector_InvokesStreamDirectoryAsync_AndEmitsEvents()
		{
			var disk = new Mock<IDiskOperationService>();
			var id = Guid.NewGuid();
			disk.Setup(s => s.BeginScan(It.IsAny<Guid?>())).Returns(id);

			var hubMock = new Mock<IHubContext<SystemHub>>();
			var clientsMock = new Mock<IHubClients>();
			var proxyMock = new Mock<IClientProxy>();
			hubMock.Setup(h => h.Clients).Returns(clientsMock.Object);
			clientsMock.Setup(c => c.All).Returns(proxyMock.Object);

			var emittedEvents = new List<(string Method, object? Payload)>();
			proxyMock
				.Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
				.Callback<string, object?[], CancellationToken>((method, args, _) =>
				{
					lock (emittedEvents)
					{
						emittedEvents.Add((method, args.Length > 0 ? args[0] : null));
					}
				})
				.Returns(Task.CompletedTask);

			disk.Setup(s => s.StreamDirectoryAsync(It.IsAny<string>(), id, It.IsAny<Func<IReadOnlyList<StorageNode>, Task>>(), It.IsAny<CancellationToken>()))
				.Returns<string, Guid, Func<IReadOnlyList<StorageNode>, Task>, CancellationToken>(async (path, scanId, onChunk, ct) =>
				{
					await onChunk(new List<StorageNode>
					{
						new() { Name = "file.txt", Path = Path.Combine(path, "file.txt"), SizeBytes = 100 }
					});
					return new DirectoryStreamSummary
					{
						Path = path,
						ParentPath = Path.GetDirectoryName(path) ?? string.Empty,
						OwnBytes = 100,
						RecursiveBytes = 100,
						RecursiveBytesFinal = true
					};
				});

			var controller = BuildController(disk.Object, ScopeFactoryFor(disk.Object).Object);

			var result = controller.StreamDirectorySection(
				hubMock.Object,
				DriveServiceWithReadyRoot().Object,
				TempDir,
				id);

			Assert.IsType<OkObjectResult>(result);

			// Give background task a moment to finish
			await Task.Delay(200);

			lock (emittedEvents)
			{
				Assert.Contains(emittedEvents, e => e.Method == "DirectoryChunk");
				Assert.Contains(emittedEvents, e => e.Method == "DirectoryStreamComplete");
			}
		}
	}
}

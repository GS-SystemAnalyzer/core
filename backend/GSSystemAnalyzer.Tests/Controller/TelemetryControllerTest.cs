using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using GSSystemAnalyzer.Tests.Engine;

namespace GSSystemAnalyzer.Tests.Controller;

public class TelemetryControllerTests : IAsyncLifetime
{
	private readonly List<RamMonitoringEngine> _engines = new();
	public Task InitializeAsync() => Task.CompletedTask;
	public async Task DisposeAsync()
	{
		foreach (var engine in _engines) await engine.DisposeAsync();
	}
	private TelemetryController CreateController()
	{
		var mockCpuProvider = new Mock<ICpuMetricsProvider>();
		return new TelemetryController(mockCpuProvider.Object);
	}

	private RamMonitoringEngine CreateEngine()
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
			() => Array.Empty<ProcessMemorySample>(), () => null, new ManualRamTimeProvider());
		_engines.Add(engine);
		return engine;
	}


	[Fact]
	public void KillProcess_NullPids_ReturnsBadRequest()
	{
		var controller = CreateController();
		var result = controller.KillProcess(CreateEngine(), null!);
		Assert.IsType<BadRequestObjectResult>(result);
	}

	[Fact]
	public void KillProcess_EmptyList_ReturnsBadRequest()
	{
		var controller = CreateController();
		var result = controller.KillProcess(CreateEngine(), new List<int>());
		Assert.IsType<BadRequestObjectResult>(result);
	}

	[Fact]
	public void KillProcess_NullPids_BadRequestContainsMessage()
	{
		var controller = CreateController();
		var result = controller.KillProcess(CreateEngine(), null!) as BadRequestObjectResult;
		Assert.NotNull(result?.Value);
		var json = System.Text.Json.JsonSerializer.Serialize(result!.Value);
		Assert.Contains("No PIDs provided", json);
	}

	[Fact]
	public void KillProcess_InvalidPids_ReturnsOkWithZeroCount()
	{
		var controller = CreateController();
		var result = controller.KillProcess(CreateEngine(),
			new List<int> { -1 }) as OkObjectResult;
		Assert.NotNull(result);
		var json = System.Text.Json.JsonSerializer.Serialize(result!.Value);
		Assert.Contains("0 PIDs Terminated", json);
	}

	[Fact]
	public void StartRamRadar_ReturnsOk()
	{
		var controller = CreateController();
		var engine = CreateEngine();
		var result = controller.StartRamRadar(engine);
		engine.StopRadar();
		Assert.IsType<OkObjectResult>(result);
	}

	[Fact]
	public void StopRamRadar_ReturnsOk()
	{
		var controller = CreateController();
		var engine = CreateEngine();
		var result = controller.StopRamRadar(engine);
		Assert.IsType<OkObjectResult>(result);
	}
}

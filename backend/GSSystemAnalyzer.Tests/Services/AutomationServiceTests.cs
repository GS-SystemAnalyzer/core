using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services;

public class AutomationServiceTests : IDisposable
{
	private readonly string _tempDir;
	private readonly string _rulesFile;
	private readonly string _auditFile;

	public AutomationServiceTests()
	{
		_tempDir = Path.Combine(Path.GetTempPath(), "GSAnalyzer_AutoTest_" + Guid.NewGuid().ToString("N"));
		Directory.CreateDirectory(_tempDir);
		_rulesFile = Path.Combine(_tempDir, "test_rules.json");
		_auditFile = Path.Combine(_tempDir, "test_audit.json");
	}

	public void Dispose()
	{
		if (Directory.Exists(_tempDir))
		{
			try { Directory.Delete(_tempDir, recursive: true); } catch { }
		}
	}

	private (AutomationService Service, Mock<INukeProtocolService> NukeMock, Mock<IDiskScannerEngine> ScannerMock) CreateService(
		AppSettingDto? settings = null)
	{
		var ruleStore = new AutomationRuleStore(NullLogger<AutomationRuleStore>.Instance, _rulesFile);
		var auditService = new AutomationAuditService(NullLogger<AutomationAuditService>.Instance, _auditFile);

		var nukeMock = new Mock<INukeProtocolService>();
		nukeMock.Setup(n => n.PreviewNukeAsync(It.IsAny<List<string>>(), It.IsAny<CancellationToken>()))
			.ReturnsAsync((List<string> paths, CancellationToken ct) => new NukePreviewResponse
			{
				TotalFiles = paths.Count,
				TotalBytes = paths.Count * 1024L,
				PlanToken = "test-plan-token"
			});

		nukeMock.Setup(n => n.ObliterateNodeAsync(It.IsAny<List<string>>(), It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()))
			.ReturnsAsync((List<string> paths, string token, bool recycle, CancellationToken ct) => new NukeResultDto
			{
				DeletedFiles = paths.Count,
				FreedBytes = paths.Count * 1024L,
				RecycleBinUsed = recycle,
				Recoverable = recycle
			});

		var scannerMock = new Mock<IDiskScannerEngine>();
		scannerMock.Setup(s => s.IsScanning).Returns(false);

		var settingsMock = new Mock<ISettingService>();
		settings ??= new AppSettingDto();
		settingsMock.Setup(s => s.Current).Returns(settings);

		var hubMock = new Mock<IHubContext<SystemHub>>();
		hubMock.Setup(h => h.Clients).Returns(Mock.Of<IHubClients>());
		hubMock.Setup(h => h.Clients.All).Returns(Mock.Of<IClientProxy>());

		var service = new AutomationService(
			ruleStore,
			auditService,
			nukeMock.Object,
			scannerMock.Object,
			settingsMock.Object,
			hubMock.Object,
			NullLogger<AutomationService>.Instance);

		return (service, nukeMock, scannerMock);
	}

	[Fact]
	public void ValidateRuleRoot_RejectsDriveRoots()
	{
		var (service, _, _) = CreateService();
		Assert.Throws<ArgumentException>(() => service.ValidateRuleRoot("C:\\"));
		Assert.Throws<ArgumentException>(() => service.ValidateRuleRoot("D:/"));
	}

	[Fact]
	public void ValidateRuleRoot_RejectsSystemDirectories()
	{
		var (service, _, _) = CreateService();
		var winDir = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
		if (!string.IsNullOrEmpty(winDir))
		{
			Assert.Throws<ArgumentException>(() => service.ValidateRuleRoot(winDir));
			Assert.Throws<ArgumentException>(() => service.ValidateRuleRoot(Path.Combine(winDir, "System32")));
		}

		var progFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
		if (!string.IsNullOrEmpty(progFiles))
		{
			Assert.Throws<ArgumentException>(() => service.ValidateRuleRoot(progFiles));
		}
	}

	[Fact]
	public void ValidateRuleRoot_RejectsExcludedPaths()
	{
		var customExcluded = Path.Combine(_tempDir, "excluded_vault");
		Directory.CreateDirectory(customExcluded);

		var settings = new AppSettingDto();
		settings.Scan.ExcludedPaths.Add(customExcluded);

		var (service, _, _) = CreateService(settings);
		Assert.Throws<ArgumentException>(() => service.ValidateRuleRoot(customExcluded));
	}

	[Fact]
	public void ValidateRuleRoot_AcceptsTempDirectory()
	{
		var (service, _, _) = CreateService();
		var tempSub = Path.Combine(Path.GetTempPath(), "test_cleanup_folder");
		// Should not throw
		service.ValidateRuleRoot(tempSub);
	}

	[Fact]
	public void CreateRule_InitializesIsArmedFalse_AndPersists()
	{
		var (service, _, _) = CreateService();
		var targetDir = Path.Combine(_tempDir, "temp_target");
		Directory.CreateDirectory(targetDir);

		var rule = service.CreateRule(new CreateAutomationRuleRequest(
			Name: "Daily Temp Cleanup",
			IsEnabled: true,
			Root: targetDir,
			Criteria: new RuleCriteria(OlderThanDays: 7, LargerThanBytes: null, ExtensionAllowlist: null, PathContainsAny: null, RecurseSubdirectories: true),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, IntervalHours: null, TimeOfDay: new TimeOnly(3, 0), DayOfWeek: null)
		));

		Assert.NotNull(rule);
		Assert.False(rule.IsArmed);
		Assert.NotNull(rule.NextRunUtc);

		var loaded = service.GetRule(rule.Id);
		Assert.NotNull(loaded);
		Assert.Equal("Daily Temp Cleanup", loaded!.Name);
		Assert.False(loaded.IsArmed);
	}

	[Fact]
	public async Task ExecuteRule_UnarmedRule_DoesNotExecute()
	{
		var (service, nukeMock, _) = CreateService();
		var targetDir = Path.Combine(_tempDir, "unarmed_target");
		Directory.CreateDirectory(targetDir);
		File.WriteAllText(Path.Combine(targetDir, "old.tmp"), "payload");

		var rule = service.CreateRule(new CreateAutomationRuleRequest(
			Name: "Unarmed",
			IsEnabled: true,
			Root: targetDir,
			Criteria: new RuleCriteria(OlderThanDays: null, LargerThanBytes: null, ExtensionAllowlist: null, PathContainsAny: null, RecurseSubdirectories: true),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null)
		));

		var entry = await service.ExecuteRuleAsync(rule.Id, isManualTrigger: false);
		Assert.Null(entry);
		nukeMock.Verify(n => n.ObliterateNodeAsync(It.IsAny<List<string>>(), It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()), Times.Never);
	}

	[Fact]
	public async Task ExecuteRule_WhenArmed_DeletesWithRecycleBinMode()
	{
		var (service, nukeMock, _) = CreateService();
		var targetDir = Path.Combine(_tempDir, "armed_target");
		Directory.CreateDirectory(targetDir);
		var filePath = Path.Combine(targetDir, "test.tmp");
		File.WriteAllText(filePath, "content");

		var rule = service.CreateRule(new CreateAutomationRuleRequest(
			Name: "Armed Run",
			IsEnabled: true,
			Root: targetDir,
			Criteria: new RuleCriteria(OlderThanDays: null, LargerThanBytes: null, ExtensionAllowlist: null, PathContainsAny: null, RecurseSubdirectories: true),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null)
		));

		service.ArmRule(rule.Id);

		var entry = await service.ExecuteRuleAsync(rule.Id, isManualTrigger: false);
		Assert.NotNull(entry);
		Assert.False(entry!.WasAborted);
		Assert.Equal(1, entry.DeletedCount);

		// Assert useRecycleBin == true is strictly passed
		nukeMock.Verify(n => n.ObliterateNodeAsync(
			It.Is<List<string>>(p => p.Contains(filePath)),
			It.IsAny<string>(),
			true, // MUST be true
			It.IsAny<CancellationToken>()), Times.Once);
	}

	[Fact]
	public async Task ExecuteRule_CapExceeded_AbortsWithoutDeletion()
	{
		var (service, nukeMock, _) = CreateService();
		service.MaxFilesPerRun = 2; // Set cap to 2

		var targetDir = Path.Combine(_tempDir, "cap_target");
		Directory.CreateDirectory(targetDir);
		File.WriteAllText(Path.Combine(targetDir, "f1.tmp"), "1");
		File.WriteAllText(Path.Combine(targetDir, "f2.tmp"), "2");
		File.WriteAllText(Path.Combine(targetDir, "f3.tmp"), "3"); // 3 files exceeds cap of 2

		var rule = service.CreateRule(new CreateAutomationRuleRequest(
			Name: "Cap Rule",
			IsEnabled: true,
			Root: targetDir,
			Criteria: new RuleCriteria(OlderThanDays: null, LargerThanBytes: null, ExtensionAllowlist: null, PathContainsAny: null, RecurseSubdirectories: true),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null)
		));

		service.ArmRule(rule.Id);

		var entry = await service.ExecuteRuleAsync(rule.Id, isManualTrigger: false);
		Assert.NotNull(entry);
		Assert.True(entry!.WasAborted);
		Assert.Equal("CAP_EXCEEDED", entry.AbortReason);
		Assert.Equal(0, entry.DeletedCount);

		nukeMock.Verify(n => n.ObliterateNodeAsync(It.IsAny<List<string>>(), It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()), Times.Never);
	}

	[Fact]
	public async Task ExecuteRule_OverlapGuard_SkipsWhenScanOrNukeActive()
	{
		var (service, nukeMock, scannerMock) = CreateService();
		scannerMock.Setup(s => s.IsScanning).Returns(true); // Active scan!

		var targetDir = Path.Combine(_tempDir, "overlap_target");
		Directory.CreateDirectory(targetDir);

		var rule = service.CreateRule(new CreateAutomationRuleRequest(
			Name: "Overlap Test",
			IsEnabled: true,
			Root: targetDir,
			Criteria: new RuleCriteria(null, null, null, null, true),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null)
		));
		service.ArmRule(rule.Id);

		var entry = await service.ExecuteRuleAsync(rule.Id, isManualTrigger: false);
		Assert.Null(entry);
		nukeMock.Verify(n => n.ObliterateNodeAsync(It.IsAny<List<string>>(), It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<CancellationToken>()), Times.Never);
	}
}

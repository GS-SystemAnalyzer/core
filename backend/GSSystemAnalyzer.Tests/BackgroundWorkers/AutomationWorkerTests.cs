using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.BackgroundWorkers;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.BackgroundWorkers;

public class AutomationWorkerTests
{
	[Fact]
	public async Task TickAsync_WhenScannerIsScanning_SkipsTick()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		var scannerMock = new Mock<IDiskScannerEngine>();
		var nukeMock = new Mock<INukeProtocolService>();

		scannerMock.Setup(s => s.IsScanning).Returns(true);
		nukeMock.Setup(n => n.IsNuking).Returns(false);

		var worker = new AutomationWorker(
			autoServiceMock.Object,
			scannerMock.Object,
			nukeMock.Object,
			NullLogger<AutomationWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		autoServiceMock.Verify(s => s.GetDueRules(It.IsAny<DateTimeOffset>()), Times.Never);
	}

	[Fact]
	public async Task TickAsync_WhenNukeIsActive_SkipsTick()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		var scannerMock = new Mock<IDiskScannerEngine>();
		var nukeMock = new Mock<INukeProtocolService>();

		scannerMock.Setup(s => s.IsScanning).Returns(false);
		nukeMock.Setup(n => n.IsNuking).Returns(true);

		var worker = new AutomationWorker(
			autoServiceMock.Object,
			scannerMock.Object,
			nukeMock.Object,
			NullLogger<AutomationWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		autoServiceMock.Verify(s => s.GetDueRules(It.IsAny<DateTimeOffset>()), Times.Never);
	}

	[Fact]
	public async Task TickAsync_WhenDueRulesExist_ExecutesEachRule()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		var scannerMock = new Mock<IDiskScannerEngine>();
		var nukeMock = new Mock<INukeProtocolService>();

		scannerMock.Setup(s => s.IsScanning).Returns(false);
		nukeMock.Setup(n => n.IsNuking).Returns(false);

		var dueRule = new AutomationRule(
			Id: "rule-due-1",
			Name: "Test Rule",
			IsEnabled: true,
			IsArmed: true,
			Root: "C:/Temp",
			Criteria: new RuleCriteria(null, null, null, null, false),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null),
			LastRunUtc: null,
			NextRunUtc: DateTimeOffset.UtcNow.AddMinutes(-5)
		);

		autoServiceMock.Setup(s => s.GetDueRules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<AutomationRule> { dueRule });

		var worker = new AutomationWorker(
			autoServiceMock.Object,
			scannerMock.Object,
			nukeMock.Object,
			NullLogger<AutomationWorker>.Instance);

		await worker.TickAsync(CancellationToken.None);

		autoServiceMock.Verify(s => s.ExecuteRuleAsync("rule-due-1", false, It.IsAny<CancellationToken>()), Times.Once);
	}

	[Fact]
	public async Task TickAsync_CollapsesMissedWindowsOnWake()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		var scannerMock = new Mock<IDiskScannerEngine>();
		var nukeMock = new Mock<INukeProtocolService>();

		scannerMock.Setup(s => s.IsScanning).Returns(false);
		nukeMock.Setup(n => n.IsNuking).Returns(false);

		// Rule due 3 days ago (machine asleep for 3 scheduled windows)
		var backloggedRule = new AutomationRule(
			Id: "rule-backlogged",
			Name: "Daily Backlogged Rule",
			IsEnabled: true,
			IsArmed: true,
			Root: "C:/Temp",
			Criteria: new RuleCriteria(null, null, null, null, false),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null),
			LastRunUtc: DateTimeOffset.UtcNow.AddDays(-4),
			NextRunUtc: DateTimeOffset.UtcNow.AddDays(-3)
		);

		autoServiceMock.Setup(s => s.GetDueRules(It.IsAny<DateTimeOffset>()))
			.Returns(new List<AutomationRule> { backloggedRule });

		var worker = new AutomationWorker(
			autoServiceMock.Object,
			scannerMock.Object,
			nukeMock.Object,
			NullLogger<AutomationWorker>.Instance);

		// Single tick executes the rule exactly once, not three times
		await worker.TickAsync(CancellationToken.None);

		autoServiceMock.Verify(s => s.ExecuteRuleAsync("rule-backlogged", false, It.IsAny<CancellationToken>()), Times.Once);
	}
}

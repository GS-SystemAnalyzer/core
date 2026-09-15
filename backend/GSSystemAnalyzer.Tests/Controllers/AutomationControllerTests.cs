using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Controllers;

public class AutomationControllerTests
{
	[Fact]
	public void GetRules_ReturnsOkWithList()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		autoServiceMock.Setup(s => s.GetRules()).Returns(new List<AutomationRule>());

		var auditMock = new Mock<IAutomationAuditService>();

		var controller = new AutomationController(
			autoServiceMock.Object,
			auditMock.Object,
			NullLogger<AutomationController>.Instance);

		var result = controller.GetRules();
		var okResult = Assert.IsType<OkObjectResult>(result);
		Assert.NotNull(okResult.Value);
	}

	[Fact]
	public void CreateRule_WhenAllowlistFails_ReturnsBadRequest()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		autoServiceMock.Setup(s => s.CreateRule(It.IsAny<CreateAutomationRuleRequest>()))
			.Throws(new ArgumentException("Drive roots are strictly prohibited."));

		var auditMock = new Mock<IAutomationAuditService>();

		var controller = new AutomationController(
			autoServiceMock.Object,
			auditMock.Object,
			NullLogger<AutomationController>.Instance);

		var result = controller.CreateRule(new CreateAutomationRuleRequest(
			Name: "Bad Rule",
			IsEnabled: true,
			Root: "C:\\",
			Criteria: new RuleCriteria(null, null, null, null, false),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null)
		));

		var badRequest = Assert.IsType<BadRequestObjectResult>(result);
		Assert.NotNull(badRequest.Value);
	}

	[Fact]
	public void ArmRule_WhenFound_ReturnsOkWithArmedRule()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		var armedRule = new AutomationRule(
			Id: "rule-1",
			Name: "Arm Test",
			IsEnabled: true,
			IsArmed: true,
			Root: "C:/Temp",
			Criteria: new RuleCriteria(null, null, null, null, false),
			Schedule: new ScheduleSpec(AutomationScheduleKind.Daily, null, null, null),
			LastRunUtc: null,
			NextRunUtc: null
		);

		autoServiceMock.Setup(s => s.ArmRule("rule-1")).Returns(armedRule);
		var auditMock = new Mock<IAutomationAuditService>();

		var controller = new AutomationController(
			autoServiceMock.Object,
			auditMock.Object,
			NullLogger<AutomationController>.Instance);

		var result = controller.ArmRule("rule-1");
		var okResult = Assert.IsType<OkObjectResult>(result);
		var returned = Assert.IsType<AutomationRule>(okResult.Value);
		Assert.True(returned.IsArmed);
	}

	[Fact]
	public async Task DryRunRule_ReturnsOkWithPreview()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		autoServiceMock.Setup(s => s.DryRunRuleAsync("rule-1", It.IsAny<CancellationToken>()))
			.ReturnsAsync(new NukePreviewResponse { TotalFiles = 5, TotalBytes = 10000 });

		var auditMock = new Mock<IAutomationAuditService>();

		var controller = new AutomationController(
			autoServiceMock.Object,
			auditMock.Object,
			NullLogger<AutomationController>.Instance);

		var result = await controller.DryRunRule("rule-1", CancellationToken.None);
		var okResult = Assert.IsType<OkObjectResult>(result);
		var preview = Assert.IsType<NukePreviewResponse>(okResult.Value);
		Assert.Equal(5, preview.TotalFiles);
	}

	[Fact]
	public async Task GetAudit_ReturnsOkWithEntries()
	{
		var autoServiceMock = new Mock<IAutomationService>();
		var auditMock = new Mock<IAutomationAuditService>();
		auditMock.Setup(a => a.GetEntriesAsync(30))
			.ReturnsAsync(new List<AutomationAuditEntry>());

		var controller = new AutomationController(
			autoServiceMock.Object,
			auditMock.Object,
			NullLogger<AutomationController>.Instance);

		var result = await controller.GetAudit(30);
		var okResult = Assert.IsType<OkObjectResult>(result);
		Assert.NotNull(okResult.Value);
	}
}

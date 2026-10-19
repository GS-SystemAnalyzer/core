using GSSystemAnalyzer.Controllers;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Controllers;

public class ScanExportControllerTests
{
	private readonly Mock<IScanExportService> _mockExportService;
	private readonly Mock<IDriveDetectionService> _mockDriveService;
	private readonly ScanExportController _controller;

	public ScanExportControllerTests()
	{
		_mockExportService = new Mock<IScanExportService>();
		_mockDriveService = new Mock<IDriveDetectionService>();

		_mockDriveService.Setup(d => d.GetReadyDrives()).Returns(new List<DriveMetric>
		{
			new DriveMetric
			{
				Name = @"C:\",
				TotalBytes = 500000000000,
				FreeBytes = 250000000000,
				UsedBytes = 250000000000,
				UsedPercent = 50.0,
				Format = "NTFS",
				Type = "Fixed",
				Label = "OS",
				IsReady = true
			}
		});

		_controller = new ScanExportController(
			_mockExportService.Object,
			_mockDriveService.Object,
			NullLogger<ScanExportController>.Instance);

		var httpContext = new DefaultHttpContext();
		httpContext.Response.Body = new MemoryStream();
		_controller.ControllerContext = new ControllerContext
		{
			HttpContext = httpContext
		};
	}

	[Fact]
	public async Task ExportScan_Returns400_WhenRootIsEmpty()
	{
		var result = await _controller.ExportScan(root: null);
		Assert.IsType<BadRequestObjectResult>(result);
	}

	[Fact]
	public async Task ExportScan_Returns409_WhenNoScanCached()
	{
		_mockExportService.Setup(e => e.HasCachedScan(It.IsAny<string>())).Returns(false);

		var result = await _controller.ExportScan(root: @"C:\");

		var conflict = Assert.IsType<ConflictObjectResult>(result);
		Assert.NotNull(conflict.Value);
	}

	[Fact]
	public async Task ExportScan_Returns400_WhenDriveNotReadyAndDirMissing()
	{
		_mockDriveService.Setup(d => d.GetReadyDrives()).Returns(new List<DriveMetric>());

		var result = await _controller.ExportScan(root: @"Z:\NonExistentDrive");
		Assert.IsType<BadRequestObjectResult>(result);
	}

	[Fact]
	public async Task ExportScan_StreamsAndSetsHeaders_WhenScanCached()
	{
		_mockExportService.Setup(e => e.HasCachedScan(It.IsAny<string>())).Returns(true);
		_mockExportService
			.Setup(e => e.ExportAsync(It.IsAny<string>(), "json", false, It.IsAny<Stream>(), It.IsAny<CancellationToken>()))
			.Returns(Task.CompletedTask);

		var result = await _controller.ExportScan(root: @"C:\", format: "json", redactPaths: false);

		Assert.IsType<EmptyResult>(result);
		var response = _controller.HttpContext.Response;
		Assert.Contains("application/json", response.ContentType);
		Assert.True(response.Headers.ContainsKey("Content-Disposition"));
		Assert.Contains("attachment; filename=\"gs-scan-C-", response.Headers["Content-Disposition"].ToString());
	}

	[Fact]
	public async Task ExportScan_CsvFormat_SetsCsvContentType()
	{
		_mockExportService.Setup(e => e.HasCachedScan(It.IsAny<string>())).Returns(true);
		_mockExportService
			.Setup(e => e.ExportAsync(It.IsAny<string>(), "csv", true, It.IsAny<Stream>(), It.IsAny<CancellationToken>()))
			.Returns(Task.CompletedTask);

		var result = await _controller.ExportScan(root: @"C:\", format: "csv", redactPaths: true);

		Assert.IsType<EmptyResult>(result);
		var response = _controller.HttpContext.Response;
		Assert.Contains("text/csv", response.ContentType);
		Assert.Contains(".csv\"", response.Headers["Content-Disposition"].ToString());
	}

	[Fact]
	public void GetReportSummary_Returns400_WhenRootIsEmpty()
	{
		var result = _controller.GetReportSummary(root: null);
		Assert.IsType<BadRequestObjectResult>(result);
	}

	[Fact]
	public void GetReportSummary_Returns409_WhenNoScanCached()
	{
		_mockExportService.Setup(e => e.HasCachedScan(It.IsAny<string>())).Returns(false);

		var result = _controller.GetReportSummary(root: @"C:\");

		var conflict = Assert.IsType<ConflictObjectResult>(result);
		Assert.NotNull(conflict.Value);
	}

	[Fact]
	public void GetReportSummary_Returns200_WhenScanCached()
	{
		_mockExportService.Setup(e => e.HasCachedScan(It.IsAny<string>())).Returns(true);
		var fakeSummary = new ScanReportSummaryDto(
			@"C:\",
			DateTimeOffset.UtcNow,
			DateTimeOffset.UtcNow,
			1024,
			10,
			2,
			new List<ScanCategorySummaryDto> { new("code", 5, 512) },
			new List<TopDirectorySummaryDto> { new(@"C:\dir", 5, 512, 1024) });

		_mockExportService.Setup(e => e.GetReportSummary(It.IsAny<string>(), false))
			.Returns(fakeSummary);

		var result = _controller.GetReportSummary(root: @"C:\", redactPaths: false);

		var okResult = Assert.IsType<OkObjectResult>(result);
		var summary = Assert.IsType<ScanReportSummaryDto>(okResult.Value);
		Assert.Equal(@"C:\", summary.Root);
		Assert.Equal(1024, summary.TotalBytes);
		Assert.Single(summary.Categories);
		Assert.Single(summary.TopDirectories);
	}

	[Fact]
	public async Task ExportScan_HtmlFormat_Returns400BadRequest()
	{
		_mockExportService.Setup(e => e.HasCachedScan(It.IsAny<string>())).Returns(true);

		var result = await _controller.ExportScan(root: @"C:\", format: "html");

		var badRequest = Assert.IsType<BadRequestObjectResult>(result);
		Assert.NotNull(badRequest.Value);
	}
}



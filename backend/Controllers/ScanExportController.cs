using System.IO;
using GSSystemAnalyzer.Interfaces;
using Microsoft.AspNetCore.Mvc;

namespace GSSystemAnalyzer.Controllers;

[ApiController]
[Route("api/scan/export")]
[Route("api/storage/scan/export")]
public class ScanExportController : ControllerBase
{
	private readonly IScanExportService _exportService;
	private readonly IDriveDetectionService _driveService;
	private readonly ILogger<ScanExportController> _logger;

	public ScanExportController(
		IScanExportService exportService,
		IDriveDetectionService driveService,
		ILogger<ScanExportController> logger)
	{
		_exportService = exportService;
		_driveService = driveService;
		_logger = logger;
	}

	[HttpGet]
	public async Task<IActionResult> ExportScan(
		[FromQuery] string? root,
		[FromQuery] string format = "json",
		[FromQuery] bool redactPaths = false)
	{
		if (string.IsNullOrWhiteSpace(root))
		{
			return BadRequest(new { error = "ROOT_REQUIRED", message = "root query parameter is required." });
		}

		var targetRoot = ResolveTargetPath(root);
		var normalizedRoot = NormalizeRoot(targetRoot);

		var readyDrives = _driveService.GetReadyDrives();
		if (!readyDrives.Any(d => d.Name.Equals(normalizedRoot, StringComparison.OrdinalIgnoreCase)) && !Directory.Exists(targetRoot))
		{
			return BadRequest(new { error = "DRIVE_NOT_READY", message = $"Drive not ready or path not accessible: {normalizedRoot}" });
		}

		if (!_exportService.HasCachedScan(targetRoot) && !_exportService.HasCachedScan(normalizedRoot))
		{
			return Conflict(new
			{
				error = "NO_SCAN_CACHED",
				message = "No scan result found for this root. Run a scan first."
			});
		}

		var effectiveRoot = _exportService.HasCachedScan(targetRoot) ? targetRoot : normalizedRoot;
		var normFormat = (format ?? "json").Trim().ToLowerInvariant();
		var ext = normFormat switch
		{
			"csv" => "csv",
			"html" => "html",
			_ => "json"
		};

		var contentType = normFormat switch
		{
			"csv" => "text/csv; charset=utf-8",
			"html" => "text/html; charset=utf-8",
			_ => "application/json; charset=utf-8"
		};

		var driveLetter = Path.GetPathRoot(effectiveRoot)?.TrimEnd(':', '\\', '/') ?? "root";
		if (string.IsNullOrWhiteSpace(driveLetter)) driveLetter = "scan";
		var timestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHHmmssZ");
		var filename = $"gs-scan-{driveLetter}-{timestamp}.{ext}";

		Response.ContentType = contentType;
		Response.Headers["Content-Disposition"] = $"attachment; filename=\"{filename}\"";

		try
		{
			await _exportService.ExportAsync(effectiveRoot, normFormat, redactPaths, Response.Body, HttpContext.RequestAborted);
			return new EmptyResult();
		}
		catch (OperationCanceledException)
		{
			_logger.LogInformation("Export operation was canceled by the client.");
			return new EmptyResult();
		}
		catch (Exception ex)
		{
			_logger.LogError(ex, "Failed to stream scan export for {Root}", effectiveRoot);
			if (!Response.HasStarted)
			{
				return StatusCode(500, new { error = "EXPORT_FAILED", message = ex.Message });
			}
			return new EmptyResult();
		}
	}

	private static string ResolveTargetPath(string requested)
	{
		return string.IsNullOrWhiteSpace(requested)
			? (Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\")
			: requested;
	}

	private static string NormalizeRoot(string path)
	{
		var normalized = Path.GetPathRoot(path)?.ToUpperInvariant() ?? path.ToUpperInvariant();
		if (!normalized.EndsWith(":\\") && !normalized.EndsWith(":/"))
		{
			normalized = normalized.TrimEnd('\\', '/', ':') + ":\\";
		}
		return normalized;
	}
}

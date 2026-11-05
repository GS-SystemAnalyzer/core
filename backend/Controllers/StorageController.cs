using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.DependencyInjection;

namespace GSSystemAnalyzer.Controllers
{
	[ApiController]
	[Route("api/[controller]")]
	public class StorageController : ControllerBase
	{
		private readonly IDiskOperationService _diskService;
		private readonly IDuplicateFileDetector _duplicateFileDetector;
		private readonly IServiceScopeFactory _scopeFactory;

		public StorageController(IDiskOperationService diskService, IDuplicateFileDetector duplicateFileDetector, IServiceScopeFactory scopeFactory)
		{
			_diskService = diskService;
			_duplicateFileDetector = duplicateFileDetector;
			_scopeFactory = scopeFactory;
		}

		[HttpPost("stream-sector")]
		public IActionResult StreamDirectorySection([FromServices] IHubContext<SystemHub> hubContext, [FromServices] IDriveDetectionService driveService, [FromQuery] string path, [FromQuery] Guid? scanId)
		{
			var validationResult = ValidateDriveAndDirectory(path, driveService);
			if (validationResult != null) return validationResult;

			var requestStream = BenchmarkTrace.Stream;
			var id = _diskService.BeginScan(scanId);
			using var stream = BenchmarkTrace.Enter(id.ToString("N"));
			var trace = BenchmarkTrace.Current;
			trace?.Emit("stream.request", operationId: requestStream.StartsWith("http-", StringComparison.Ordinal) ? requestStream[5..] : null,
				key: trace.Key(Path.GetFullPath(path).Replace('\\', '/').TrimEnd('/').ToUpperInvariant()));
			var queued = trace?.Begin("stream.controller_queue");
			var work = trace?.Begin("stream.controller_task");

			var task = Task.Run(async () =>
			{
				queued?.Dispose();
				using var scope = _scopeFactory.CreateScope();
				var scopedDiskService = scope.ServiceProvider.GetRequiredService<IDiskOperationService>();
				DirectoryStreamSummary? summary = null;
				var outcome = "succeeded";
				try
				{
					summary = await scopedDiskService.StreamDirectoryAsync(path, id, async chunk =>
					{
						var metadata = trace?.Metadata();
						trace?.Emit("stream.chunk", metadata: metadata, counts: new Dictionary<string, long>
							{ ["nodes"] = chunk.Count, ["bytes"] = chunk.Sum(node => node.SizeBytes) });
						await BenchmarkTrace.Send(hubContext.Clients.All, "DirectoryChunk", new
						{
							scanId = id,
							path = path,
							chunk = chunk
						}, metadata: metadata);
					});
				}
				catch (Exception ex)
				{
					outcome = ex is OperationCanceledException ? "cancelled" : "failed";
					trace?.Emit("stream.error", outcome);
					await BenchmarkTrace.Send(hubContext.Clients.All, "DirectoryStreamError",
						new { scanId = id, path = path, error = ex.Message });
				}
				finally
				{
					trace?.Emit("stream.terminal", outcome, counts: new Dictionary<string, long>
						{ ["has_summary"] = summary != null ? 1 : 0, ["recursive_bytes"] = summary?.RecursiveBytes ?? 0 });
					await BenchmarkTrace.Send(hubContext.Clients.All, "DirectoryStreamComplete", new
					{
						scanId = id,
						path = path,
						parentPath = summary?.ParentPath ?? (Path.GetDirectoryName(path) ?? string.Empty),
						ownBytes = summary?.OwnBytes ?? 0,
						recursiveBytes = summary?.RecursiveBytes ?? 0,
						recursiveBytesFinal = true
					});
				}
			});
			if (trace != null && work != null) _ = trace.Observe(task, work);

			return Ok(new ApiResponse<object>
			{
				Success = true,
				Message = "Stream Initiated"
			});
		}

		[HttpPost("scan")]
		public async Task<IActionResult> ScanDirectory(
			[FromBody] ScanRequest request,
			[FromServices] IDriveDetectionService driveService)
		{
			try
			{
				var targetPath = ResolveTargetPath(request?.Root);

				var validationResult = ValidateDriveAndDirectory(targetPath, driveService);
				if (validationResult != null) return validationResult;

				var id = _diskService.BeginScan(request.ScanId);
				var result = await Task.Run(() => _diskService.ScanDirectory(targetPath, id));

				var response = new ApiResponse<IEnumerable<StorageNode>>
				{
					Success = true,
					Message = "Directory scanned successfully.",
					Data = result
				};

				return Ok(response);
			}
			catch (OperationCanceledException)
			{
				return StatusCode(499, new ApiResponse<object>
				{
					Success = false,
					Message = "Directory Scan Aborted by User."
				});
			}
			catch (Exception ex)
			{
				return BadRequest(new ApiResponse<object>
				{
					Success = false,
					Message = $"Scan failed: {ex.Message}"
				});
			}

		}

		[HttpGet("drive-stats")]
		public IActionResult GetDriveStats([FromQuery] string driveLetter, [FromServices] IDriveDetectionService driveService)
		{
			try
			{
				var validationResult = ValidateDriveReady(NormalizeRoot(driveLetter), driveService);
				if (validationResult != null) return validationResult;

				var stats = _diskService.GetDriveTelemetry(driveLetter);

				var response = new ApiResponse<DriveTelemetryDto>
				{
					Success = true,
					Message = "Telemetry retrieved Successfully.",
					Data = stats
				};


				return Ok(response);
			}

			catch (Exception ex)
			{
				return BadRequest(new ApiResponse<object>
				{
					Success = false,
					Message = "Could not read hardware telemetry for drive: " + ex.Message
				});
			}
		}


		[HttpPost("abort-scan")]
		public IActionResult AbortScan([FromQuery] Guid? scanId = null)
		{
			var requestStream = BenchmarkTrace.Stream;
			using var stream = BenchmarkTrace.Enter(scanId?.ToString("N") ?? "system");
			BenchmarkTrace.Current?.Emit("scan.abort.controller_received",
				operationId: requestStream.StartsWith("http-", StringComparison.Ordinal) ? requestStream[5..] : null);
			_diskService.TriggerScanAbort(scanId);
			BenchmarkTrace.Current?.Emit("scan.abort.controller_returned");

			return Ok(new ApiResponse<object>
			{
				Success = true,
				Message = "Abort Signal received. Brakes applied."
			});
		}

		[HttpPost("duplicates")]
		public async Task<IActionResult> ScanForDuplicates(
			[FromBody] ScanRequest request,
			[FromServices] IDriveDetectionService driveService)
		{
			try
			{
				var targetPath = ResolveTargetPath(request?.Root);

				var validationResult = ValidateDriveAndDirectory(targetPath, driveService);
				if (validationResult != null) return validationResult;

				var id = _diskService.BeginScan(request.ScanId);
				var duplicateGroups = await _duplicateFileDetector.FindDuplicatesAsync(targetPath, id);

				return Ok(new ApiResponse<IEnumerable<DuplicateGroup>>
				{
					Success = true,
					Message = "Duplicates scanned successfully.",
					Data = duplicateGroups
				});
			}
			catch (OperationCanceledException)
			{
				return StatusCode(499, new ApiResponse<object>
				{
					Success = false,
					Message = "Duplicate Scan Aborted by User."
				});
			}
			catch (Exception ex)
			{
				return BadRequest(new ApiResponse<object>
				{
					Success = false,
					Message = $"Scan failed: {ex.Message}"
				});
			}
		}

		[HttpGet("scan-largefiles")]
		public async Task<IActionResult> GetLargeFiles(
			[FromServices] ILargeFileHunterService hunter,
			[FromServices] IDriveDetectionService driveService,
			CancellationToken cancellationToken,
			[FromQuery] string? root = null,
			[FromQuery] int top = 20)
		{
			try
			{
				root = ResolveTargetPath(root);

				var validationResult = ValidateDriveAndDirectory(root, driveService);
				if (validationResult != null) return validationResult;

				var result = await hunter.GetTopLargeFilesAsync(root, top, cancellationToken);

				var response = new ApiResponse<IEnumerable<LargeFile>>
				{
					Success = true,
					Message = "Large files scanned successfully.",
					Data = result
				};

				return Ok(response);
			}
			catch (OperationCanceledException)
			{
				return StatusCode(499, new ApiResponse<object>
				{
					Success = false,
					Message = "Client closed request, Scan Aborted"
				});
			}
			catch (Exception ex)
			{
				return BadRequest(new ApiResponse<object>
				{
					Success = false,
					Message = $"Scan failed: {ex.Message}"
				});
			}
		}

		[HttpGet("scan/filetypes")]
		public IActionResult GetFileTypes(
			[FromQuery] string root,
			[FromServices] IFileTypeScanner scanner,
			[FromQuery] bool refresh = false)
		{
			var validationResult = ValidateRootForCachedRead(root);
			if (validationResult != null) return validationResult;

			if (refresh)
			{
				scanner.Invalidate(root);
			}

			var result = scanner.Analyze(root);

			if (result is null)
				return Conflict(new
				{
					error = "NO_SCAN_CACHED",
					message = "No scan result found for this root. Run a Directory scan first."
				});

			return Ok(result);
		}

		[HttpGet("scan/ageheatmap")]
		public IActionResult GetAgeHeatmap(
			[FromQuery] string root,
			[FromServices] IAgeHeatmapEngine heatmap)
		{
			var validationResult = ValidateRootForCachedRead(root);
			if (validationResult != null) return validationResult;

			var result = heatmap.Analyze(root);

			if (result is null)
				return Conflict(new
				{
					error = "NO_SCAN_CACHED",
					message = "No scan result found for this root. Run a Directory scan first."
				});

			return Ok(result);
		}

		[HttpGet("scan/extensions")]
		public IActionResult GetExtensions(
			[FromQuery] string root,
			[FromServices] IFileTypeScanner scanner,
			[FromQuery] bool refresh = false)
		{
			var validationResult = ValidateRootForCachedRead(root);
			if (validationResult != null) return validationResult;

			if (refresh)
			{
				scanner.Invalidate(root);
			}

			var result = scanner.GetExtensionBreakdown(root);

			if (result is null)
				return Conflict(new
				{
					error = "NO_SCAN_CACHED",
					message = "No scan result found for this root. Run a Directory scan first."
				});

			return Ok(result);
		}

		private static ApiResponse<object> Fail(string message) =>
			new() { Success = false, Message = message };

		private static string ResolveTargetPath(string? requested) =>
			string.IsNullOrWhiteSpace(requested)
				? (Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\")
				: requested;

		private static string NormalizeRoot(string path)
		{
			var normalizedRoot = Path.GetPathRoot(path)?.ToUpperInvariant() ?? path.ToUpperInvariant();
			if (!normalizedRoot.EndsWith(":\\"))
			{
				normalizedRoot = normalizedRoot.TrimEnd('\\', ':') + ":\\";
			}
			return normalizedRoot;
		}

		/// <summary>Returns a BadRequest if the drive isn't ready; otherwise null.</summary>
		private IActionResult? ValidateDriveReady(string normalizedRoot, IDriveDetectionService driveService)
		{
			var readyDrives = driveService.GetReadyDrives();
			if (!readyDrives.Any(d => d.Name.ToUpperInvariant() == normalizedRoot))
				return BadRequest(Fail($"Drive not ready or not found: {normalizedRoot}"));

			return null;
		}

		/// <summary>Returns a BadRequest if the drive isn't ready or the directory is missing; otherwise null.</summary>
		private IActionResult? ValidateDriveAndDirectory(string path, IDriveDetectionService driveService)
		{
			var driveError = ValidateDriveReady(NormalizeRoot(path), driveService);
			if (driveError != null) return driveError;

			if (!System.IO.Directory.Exists(path))
				return BadRequest(Fail("Invalid or missing target directory."));

			return null;
		}

		/// <summary>Validation for the cached-read endpoints (filetypes / ageheatmap / extensions).</summary>
		private IActionResult? ValidateRootForCachedRead(string root)
		{
			if (string.IsNullOrWhiteSpace(root))
				return BadRequest(new { error = "ROOT_REQUIRED", message = "root query parameter is required." });

			if (!System.IO.Directory.Exists(root))
				return BadRequest(new { error = "DRIVE_NOT_FOUND", message = $"Root path '{root}' does not exist or is not accessible." });

			return null;
		}
	}
}

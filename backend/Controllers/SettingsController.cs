using System.Configuration;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.Mvc;

namespace GSSystemAnalyzer.Controllers
{
	[ApiController]
	[Route("api/[controller]")]
	public class SettingsController : ControllerBase
	{
		private readonly ISettingService _settingsService;
		private readonly IDiskScannerEngine _scanner;

		public SettingsController(ISettingService settingsService, IDiskScannerEngine scanner)
		{
			_settingsService = settingsService;
			_scanner = scanner;
		}

		[HttpGet]
		public IActionResult GetSettings()
		{
			return Ok(new { success = true, data = _settingsService.Current });
		}

		[HttpGet("defaults")]
		public IActionResult GetDefaults()
		{
			return Ok(new { success = true, data = AppSettingDto.GetFactoryDefaults() });
		}

		[HttpPost]
		public async Task<IActionResult> SaveSettings([FromBody] AppSettingDto settings)
		{
			var snapshot = SettingsServices.Copy(settings);
			var errors = snapshot.Validate();
			if (errors.Any())
			{
				return BadRequest(new { success = false, message = "Validation failed", errors });
			}

			await _settingsService.SaveAsync(snapshot);

			return Ok(new
			{
				success = true,
				message = "Settings saved & hot-reloaded Successfully",
				data = snapshot
			});
		}

		[HttpPost("reset")]
		public async Task<IActionResult> ResetSettings()
		{
			var defaults = AppSettingDto.GetFactoryDefaults();
			await _settingsService.SaveAsync(defaults);

			return Ok(new { success = true, message = "Restored to factory defaults", data = defaults });
		}

		[HttpPatch("partial")]
		public async Task<IActionResult> PatchSettings([FromBody] System.Text.Json.JsonElement partialJson)
		{
			var currentJson = System.Text.Json.JsonSerializer.Serialize(_settingsService.Current);
			var currentDoc = System.Text.Json.Nodes.JsonObject.Parse(currentJson)!.AsObject();

			var incomingDoc = System.Text.Json.Nodes.JsonObject.Parse(partialJson.GetRawText())!.AsObject();

			foreach (var prop in incomingDoc)
			{
				currentDoc[prop.Key] = prop.Value?.DeepClone();
			}

			var mergedSettings = System.Text.Json.JsonSerializer.Deserialize<AppSettingDto>(currentDoc.ToJsonString(), new System.Text.Json.JsonSerializerOptions { PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase });

			var errors = mergedSettings!.Validate();
			if (errors.Any()) return BadRequest(new { success = false, message = "Validation failed.", errors });

			await _settingsService.SaveAsync(mergedSettings);
			return Ok(new { success = true, data = _settingsService.Current });
		}

		[HttpPost("cache/clear")]
		public IActionResult ClearCache()
		{
			_scanner.ClearCache();
			return Ok(new { success = true, message = "Scan cache cleared. Run a new Directory Scan to repopulate." });
		}
	}
}

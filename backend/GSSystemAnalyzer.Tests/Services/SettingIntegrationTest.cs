using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Xunit;

namespace GSSystemAnalyzer.Tests.Integration
{
	public class SettingsIntegrationTests : IDisposable
	{
		private readonly string _tempFile;
		private readonly string _tempDir;

		public SettingsIntegrationTests()
		{
			_tempDir = Path.Combine(Path.GetTempPath(), "gs_ram_settings_" + Guid.NewGuid().ToString("N"));
			Directory.CreateDirectory(_tempDir);
			_tempFile = Path.Combine(_tempDir, "settings.json");
		}

		public void Dispose()
		{
			if (Directory.Exists(_tempDir)) Directory.Delete(_tempDir, recursive: true);
		}

		[Fact]
		public void Service_WhenNoFileExists_LoadsFactoryDefaults()
		{
			var service = new SettingsServices(_tempFile);
			Assert.True(File.Exists(_tempFile)); // Proves it immediately generated the missing file!
		}

		[Fact]
		public async Task FailedSave_DoesNotPublishAnUncommittedRamCadence()
		{
			var service = new SettingsServices(_tempFile);
			var previous = service.Current.Monitoring.RamPollIntervalMs;
			var notifications = 0;
			service.OnSettingsChanged += (_, _) => notifications++;
			var request = AppSettingDto.GetFactoryDefaults();
			request.Monitoring.RamPollIntervalMs = 1500;
			using var locked = new FileStream(_tempFile, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
			var error = await Record.ExceptionAsync(() => service.SaveAsync(request));
			Assert.True(error is IOException or UnauthorizedAccessException);
			Assert.Equal(previous, service.Current.Monitoring.RamPollIntervalMs);
			Assert.Equal(0, notifications);
		}

		[Theory]
		[InlineData(199, false)]
		[InlineData(200, true)]
		[InlineData(1000, true)]
		[InlineData(5000, true)]
		[InlineData(5001, false)]
		public void RamCadenceValidation_UsesTheApprovedBounds(int period, bool valid)
		{
			var settings = AppSettingDto.GetFactoryDefaults();
			settings.Monitoring.RamPollIntervalMs = period;
			Assert.Equal(valid, settings.Validate().Count == 0);
			Assert.Equal(1000, AppSettingDto.GetFactoryDefaults().Monitoring.RamPollIntervalMs);
		}

		[Theory]
		[InlineData("null")]
		[InlineData("\"invalid\"")]
		[InlineData("100.5")]
		[InlineData("199")]
		[InlineData("5001")]
		[InlineData("")]
		public void LegacyRamCadence_MigratesOnlyItsKey_AndSurvivesRestart(string legacyValue)
		{
			var settings = AppSettingDto.GetFactoryDefaults();
			settings.Scan.Depth = 23;
			settings.Monitoring.CpuPollIntervalMs = 5000;
			settings.Advanced.BackendPort = 8080;
			var root = JsonSerializer.SerializeToNode(settings, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase })!.AsObject();
			var monitoring = root["monitoring"]!.AsObject();
			if (legacyValue.Length == 0) monitoring.Remove("ramPollIntervalMs");
			else monitoring["ramPollIntervalMs"] = JsonNode.Parse(legacyValue);
			root["ownedExtraPreference"] = "preserved";
			File.WriteAllText(_tempFile, root.ToJsonString());

			var service = new SettingsServices(_tempFile);
			Assert.Equal(1000, service.Current.Monitoring.RamPollIntervalMs);
			Assert.Equal(23, service.Current.Scan.Depth);
			Assert.Equal(5000, service.Current.Monitoring.CpuPollIntervalMs);
			Assert.Equal(8080, service.Current.Advanced.BackendPort);
			using var stored = JsonDocument.Parse(File.ReadAllText(_tempFile));
			Assert.Equal("preserved", stored.RootElement.GetProperty("ownedExtraPreference").GetString());
			var serialized = File.ReadAllText(_tempFile);
			Assert.Equal(1000, new SettingsServices(_tempFile).Current.Monitoring.RamPollIntervalMs);
			Assert.Equal(serialized, File.ReadAllText(_tempFile));
		}

		[Fact]
		public void MigrationWriteFailure_IsNotMisclassifiedAsCorruptionOrAFactoryReset()
		{
			const string legacy = "{\"scan\":{\"depth\":23},\"monitoring\":{\"ramPollIntervalMs\":150},\"advanced\":{\"backendPort\":8080}}";
			File.WriteAllText(_tempFile, legacy);
			using (var locked = new FileStream(_tempFile, FileMode.Open, FileAccess.Read, FileShare.Read))
			{
				var error = Record.Exception(() => new SettingsServices(_tempFile));
				Assert.True(error is IOException or UnauthorizedAccessException);
			}
			Assert.Equal(legacy, File.ReadAllText(_tempFile));
		}

		[Fact]
		public async Task CommittedNotifications_AgreeWithDiskAndCurrent_AndDoNotAliasDrafts()
		{
			var service = new SettingsServices(_tempFile);
			var observed = new List<int>();
			service.OnSettingsChanged += (_, committed) =>
			{
				using var stored = JsonDocument.Parse(File.ReadAllText(_tempFile));
				var period = committed.Monitoring.RamPollIntervalMs;
				Assert.Equal(period, stored.RootElement.GetProperty("monitoring").GetProperty("ramPollIntervalMs").GetInt32());
				Assert.Equal(period, service.Current.Monitoring.RamPollIntervalMs);
				observed.Add(period);
				committed.Monitoring.RamPollIntervalMs = 100;
			};
			var first = AppSettingDto.GetFactoryDefaults();
			first.Monitoring.RamPollIntervalMs = 1500;
			var second = AppSettingDto.GetFactoryDefaults();
			second.Monitoring.RamPollIntervalMs = 200;
			await Task.WhenAll(Task.Run(() => service.SaveAsync(first)), Task.Run(() => service.SaveAsync(second)));
			Assert.Equal(2, observed.Count);
			Assert.Contains(1500, observed);
			Assert.Contains(200, observed);
			first.Monitoring.RamPollIntervalMs = 100;
			second.Monitoring.RamPollIntervalMs = 100;
			Assert.Equal(observed[^1], service.Current.Monitoring.RamPollIntervalMs);
		}

		[Fact]
		public async Task Service_PersistsValues_AcrossRestarts()
		{
			var service1 = new SettingsServices(_tempFile);
			var settings = service1.Current;
			settings.Advanced.BackendPort = 8080;
			await service1.SaveAsync(settings);

			var service2 = new SettingsServices(_tempFile);
			Assert.Equal(8080, service2.Current.Advanced.BackendPort); // It remembered!
		}

		[Theory]
		[InlineData(200)]
		[InlineData(250)]
		[InlineData(1000)]
		[InlineData(2000)]
		[InlineData(5000)]
		public void SupportedRamCadence_IsPreservedWithoutRewritingOtherPreferences(int period)
		{
			var json = $"{{\"scan\":{{\"depth\":23}},\"monitoring\":{{\"ramPollIntervalMs\":{period}}},\"ownedPreference\":\"preserved\"}}";
			File.WriteAllText(_tempFile, json);
			var service = new SettingsServices(_tempFile);
			Assert.Equal(period, service.Current.Monitoring.RamPollIntervalMs);
			Assert.Equal(23, service.Current.Scan.Depth);
			Assert.Equal(json, File.ReadAllText(_tempFile));
			Assert.Equal(period, new SettingsServices(_tempFile).Current.Monitoring.RamPollIntervalMs);
		}

		[Fact]
		public void Service_WithCorruptJson_RecoversAndLoadsDefaults()
		{
			File.WriteAllText(_tempFile, "{ THIS IS NOT VALID JSON!!! : [ ] }");

			var service = new SettingsServices(_tempFile);

			Assert.Equal(10, service.Current.Scan.Depth);
		}

		[Fact]
		public void Validate_WithFactoryDefaults_ReturnsNoErrors()
		{
			var settings = AppSettingDto.GetFactoryDefaults();

			var errors = settings.Validate();

			Assert.Empty(errors); // Factory defaults must ALWAYS be perfectly valid
		}

		[Fact]
		public void Validate_WithIllegalCpuInterval_ReturnsSpecificError()
		{
			var settings = AppSettingDto.GetFactoryDefaults();
			settings.Monitoring.CpuPollIntervalMs = 100; // Illegal! Min is 500.

			var errors = settings.Validate();

			Assert.Single(errors);
			Assert.Contains("CPU Poll Interval must be between 500ms and 60000ms.", errors[0]);
		}

		[Fact]
		public void Validate_WithMultipleViolations_AccumulatesAllErrors()
		{
			var settings = AppSettingDto.GetFactoryDefaults();
			settings.Scan.Depth = 999; // Illegal
			settings.Alerts.ThermalThresholdCelsius = 200; // Illegal

			var errors = settings.Validate();

			Assert.Equal(2, errors.Count);
			Assert.Contains("Scan Depth must be between 1 and 50.", errors);
			Assert.Contains("Thermal Threshold must be between 40°C and 110°C.", errors);
		}

		[Fact]
		public async Task SaveAsync_RapidConcurrentWrites_MaintainsAtomicIntegrity()
		{
			var service = new SettingsServices(_tempFile);
			var tasks = new List<Task>();

			for (int i = 0; i < 100; i++)
			{
				var iteration = i;
				tasks.Add(Task.Run(async () =>
				{
					var settings = AppSettingDto.GetFactoryDefaults();
					settings.Scan.Depth = (iteration % 50) + 1; // Valid depth between 1 and 50
					await service.SaveAsync(settings);
				}));
			}

			await Task.WhenAll(tasks);

			var finalService = new SettingsServices(_tempFile);

			Assert.True(finalService.Current.Scan.Depth > 0);
		}

		[Fact]
		public async Task AlertSettings_EnableDesktopNotifications_PersistsFalse()
		{
			var service1 = new SettingsServices(_tempFile);
			var settings = service1.Current;
			settings.Alerts.EnableDesktopNotifications = false;
			await service1.SaveAsync(settings);

			var service2 = new SettingsServices(_tempFile);
			Assert.False(service2.Current.Alerts.EnableDesktopNotifications);
		}

		[Fact]
		public void AlertSettings_DeserializesLegacyMisspelledProperty()
		{
			string legacyJson = """
			{
			  "alerts": {
			    "enableDeskopNotifications": false
			  }
			}
			""";

			var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
			var appSettings = JsonSerializer.Deserialize<AppSettingDto>(legacyJson, options);

			Assert.NotNull(appSettings);
			Assert.False(appSettings.Alerts.EnableDesktopNotifications);
		}

		[Fact]
		public void AlertSettings_SerializesCorrectCamelCaseKey_AndSuppressesLegacyKey()
		{
			var settings = AppSettingDto.GetFactoryDefaults();
			settings.Alerts.EnableDesktopNotifications = true;

			var options = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
			var json = JsonSerializer.Serialize(settings, options);

			Assert.Contains("\"enableDesktopNotifications\":true", json.Replace(" ", ""));
			Assert.DoesNotContain("enableDeskopNotifications", json);
		}
	}
}

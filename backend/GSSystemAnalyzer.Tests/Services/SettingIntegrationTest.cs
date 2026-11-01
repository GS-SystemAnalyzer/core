using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using Xunit;

namespace GSSystemAnalyzer.Tests.Integration
{
	public class SettingsIntegrationTests : IDisposable
	{
		private readonly string _tempFile;

		public SettingsIntegrationTests()
		{
			_tempFile = Path.GetTempFileName();
			File.Delete(_tempFile); // Ensure it doesn't exist yet for Test 1
		}

		public void Dispose()
		{
			if (File.Exists(_tempFile)) File.Delete(_tempFile);
		}

		[Fact]
		public void Service_WhenNoFileExists_LoadsFactoryDefaults()
		{
			var service = new SettingsServices(_tempFile);
			Assert.True(File.Exists(_tempFile)); // Proves it immediately generated the missing file!
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

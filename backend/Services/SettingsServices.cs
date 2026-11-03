using System.Text.Json;
using System.Text.Json.Nodes;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services
{
	public class SettingsServices : ISettingService
	{
		private readonly string _settingsFilePath;
		private static readonly JsonSerializerOptions _jsonOptions = new()
		{ WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
		private readonly ILogger<SettingsServices> _logger;
		private readonly object _fileLoack = new();

		public AppSettingDto Current { get; private set; } = AppSettingDto.GetFactoryDefaults();
		public string AppDataFolder { get; private set; }
		public event EventHandler<AppSettingDto>? OnSettingsChanged;


		public SettingsServices(string? testFilePath = null, ILogger<SettingsServices>? logger = null)
		{
			_logger = logger ?? Microsoft.Extensions.Logging.Abstractions.NullLogger<SettingsServices>.Instance;
			if (testFilePath != null)
			{
				_settingsFilePath = testFilePath;
				AppDataFolder = Path.GetDirectoryName(testFilePath) ?? string.Empty;
			}
			else
			{
				var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
				AppDataFolder = Path.Combine(appData, "GSAnalyzer");
				Directory.CreateDirectory(AppDataFolder);

				_settingsFilePath = Path.Combine(AppDataFolder, "appsettings.user.json");
			}

			Current = LoadAsync().GetAwaiter().GetResult();
		}

		public Task<AppSettingDto> LoadAsync()
		{
			lock (_fileLoack)
			{
				if (!File.Exists(_settingsFilePath))
				{
					CommitLocked(AppSettingDto.GetFactoryDefaults());
					return Task.FromResult(Copy(Current));
				}
				JsonObject root;
				AppSettingDto settings;
				bool migrated;
				try
				{
					root = JsonNode.Parse(File.ReadAllText(_settingsFilePath)) as JsonObject
						?? throw new JsonException("Settings must be a JSON object.");
					migrated = NormalizePersistedRamPeriod(root);
					settings = root.Deserialize<AppSettingDto>(_jsonOptions) ?? throw new JsonException("Settings are unavailable.");
				}
				catch (JsonException ex)
				{
					_logger.LogWarning(ex, "Corrupt config file detected, restoring defaults");
					CommitLocked(AppSettingDto.GetFactoryDefaults());
					return Task.FromResult(Copy(Current));
				}
				if (migrated) CommitLocked(settings, root.ToJsonString(_jsonOptions));
				else
				{
					Current = Copy(settings);
					OnSettingsChanged?.Invoke(this, Copy(Current));
				}
				return Task.FromResult(Copy(Current));
			}
		}

		private static bool NormalizePersistedRamPeriod(JsonObject root)
		{
			var monitoring = root["monitoring"] as JsonObject;
			if (monitoring == null)
			{
				monitoring = new JsonObject();
				root["monitoring"] = monitoring;
			}
			if (monitoring["ramPollIntervalMs"] is JsonValue value && value.TryGetValue<int>(out var period) &&
				period is >= MonitoringSettingDto.MinimumRamPollIntervalMs and <= MonitoringSettingDto.MaximumRamPollIntervalMs)
				return false;
			monitoring["ramPollIntervalMs"] = MonitoringSettingDto.DefaultRamPollIntervalMs;
			return true;
		}

		internal static AppSettingDto Copy(AppSettingDto settings) =>
			JsonSerializer.Deserialize<AppSettingDto>(JsonSerializer.Serialize(settings, _jsonOptions), _jsonOptions)!;

		public Task SaveAsync(AppSettingDto settings)
		{
			var snapshot = Copy(settings);
			if (snapshot.Monitoring.RamPollIntervalMs is < MonitoringSettingDto.MinimumRamPollIntervalMs or > MonitoringSettingDto.MaximumRamPollIntervalMs)
				throw new ArgumentOutOfRangeException(nameof(settings), $"RAM Poll Interval must be between {MonitoringSettingDto.MinimumRamPollIntervalMs}ms and {MonitoringSettingDto.MaximumRamPollIntervalMs}ms.");
			lock (_fileLoack) CommitLocked(snapshot);
			return Task.CompletedTask;
		}

		private void CommitLocked(AppSettingDto settings, string? migratedJson = null)
		{
			var snapshot = Copy(settings);
			var json = migratedJson ?? JsonSerializer.Serialize(snapshot, _jsonOptions);
			var tempPath = _settingsFilePath + "." + Guid.NewGuid().ToString("N") + ".tmp";
			try
			{
				File.WriteAllText(tempPath, json);
				int retries = 5;
				while (true)
				{
					try
					{
						File.Move(tempPath, _settingsFilePath, overwrite: true);
						break;
					}
					catch (Exception ex) when (ex is UnauthorizedAccessException || ex is IOException)
					{
						retries--;
						if (retries == 0) throw;
						Thread.Sleep(20);
					}
				}
			}
			finally
			{
				try { if (File.Exists(tempPath)) File.Delete(tempPath); }
				catch (IOException) { }
				catch (UnauthorizedAccessException) { }
			}
			Current = snapshot;
			OnSettingsChanged?.Invoke(this, Copy(snapshot));
		}
	}
}

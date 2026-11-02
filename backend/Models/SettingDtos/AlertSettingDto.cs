using System.Text.Json.Serialization;

namespace GSSystemAnalyzer.Models.SettingDtos
{
	public class AlertSettingDto
	{
		public int DiskThresholdPercent { get; set; } = 90;
		public int RamThresholdPercent { get; set; } = 85;
		public int RamMinimumFreeMb { get; set; } = 1024;
		public int CpuThresholdPercent { get; set; } = 95;
		public int ThermalThresholdCelsius { get; set; } = 85;
		public bool EnableDesktopNotifications { get; set; } = true;

		/// <summary>
		/// Legacy alias for backward compatibility with existing installations where
		/// appsettings.user.json contains the misspelled key.
		/// </summary>
		[JsonPropertyName("enableDeskopNotifications")]
		[JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
		public bool? EnableDeskopNotificationsLegacyFallback
		{
			get => null;
			set
			{
				if (value.HasValue)
				{
					EnableDesktopNotifications = value.Value;
				}
			}
		}
	}

}

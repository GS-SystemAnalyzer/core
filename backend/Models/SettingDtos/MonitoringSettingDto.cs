namespace GSSystemAnalyzer.Models.SettingDtos
{
	public class MonitoringSettingDto
	{
		public const int MinimumRamPollIntervalMs = 200;
		public const int MaximumRamPollIntervalMs = 5000;
		public const int DefaultRamPollIntervalMs = 1000;

		public int CpuPollIntervalMs { get; set; } = 1000;
		public int RamPollIntervalMs { get; set; } = DefaultRamPollIntervalMs;
		public int ThermalPollIntervalMs { get; set; } = 2000;
		public int NetworkPollIntervalMs { get; set; } = 1000;
		public int DiskIoPollIntervalMs { get; set; } = 1000;
		public string? PreferredNetworkInterfaceId { get; set; } = null;
		public int ScheduledScanIntervalMinutes { get; set; } = 15;
		public bool EnableScheduledScans { get; set; } = false;
	}
}

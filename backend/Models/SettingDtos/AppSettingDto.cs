namespace GSSystemAnalyzer.Models.SettingDtos
{
	public class AppSettingDto
	{
		public ScanSettingDto Scan { get; set; } = new();
		public AlertSettingDto Alerts { get; set; } = new();
		public MonitoringSettingDto Monitoring { get; set; } = new();
		public CacheSettingDto Cache { get; set; } = new();
		public AppearanceSettingDto Appearance { get; set; } = new();
		public AdvancedSettingDto Advanced { get; set; } = new();

		public static AppSettingDto GetFactoryDefaults() => new AppSettingDto();

		public List<string> Validate()
		{
			var errors = new List<string>();

			if (Scan.Depth < 1 || Scan.Depth > 50) errors.Add("Scan Depth must be between 1 and 50.");
			if (Monitoring.CpuPollIntervalMs < 500 || Monitoring.CpuPollIntervalMs > 60000) errors.Add("CPU Poll Interval must be between 500ms and 60000ms.");
			if (Monitoring.RamPollIntervalMs < 500 || Monitoring.RamPollIntervalMs > 60000) errors.Add("RAM Poll Interval must be between 500ms and 60000ms.");
			if (Monitoring.ThermalPollIntervalMs < 500 || Monitoring.ThermalPollIntervalMs > 60000) errors.Add("Thermal Poll Interval must be between 500ms and 60000ms.");
			if (Monitoring.NetworkPollIntervalMs < 500 || Monitoring.NetworkPollIntervalMs > 60000) errors.Add("Network Poll Interval must be between 500ms and 60000ms.");
			if (Monitoring.DiskIoPollIntervalMs < 500 || Monitoring.DiskIoPollIntervalMs > 60000) errors.Add("Disk I/O Poll Interval must be between 500ms and 60000ms.");
			if (Monitoring.ScheduledScanIntervalMinutes < 1 || Monitoring.ScheduledScanIntervalMinutes > 1440) errors.Add("Scheduled Scan Interval must be between 1 and 1440 minutes.");

			if (Alerts.DiskThresholdPercent < 1 || Alerts.DiskThresholdPercent > 100) errors.Add("Disk Threshold Percent must be between 1 and 100.");
			if (Alerts.CpuThresholdPercent < 1 || Alerts.CpuThresholdPercent > 100) errors.Add("CPU Threshold Percent must be between 1 and 100.");
			if (Alerts.RamThresholdPercent < 1 || Alerts.RamThresholdPercent > 100) errors.Add("RAM Threshold Percent must be between 1 and 100.");
			if (Alerts.RamMinimumFreeMb < 256 || Alerts.RamMinimumFreeMb > 16384) errors.Add("RAM Minimum Free MB must be between 256 and 16384.");
			if (Alerts.ThermalThresholdCelsius < 40 || Alerts.ThermalThresholdCelsius > 110) errors.Add("Thermal Threshold must be between 40°C and 110°C.");

			if (Cache.ScanCacheTtlMinutes < 1 || Cache.ScanCacheTtlMinutes > 1440) errors.Add("Scan Cache TTL must be between 1 and 1440 minutes.");
			if (Cache.MaxCachedNodes < 1000 || Cache.MaxCachedNodes > 500000) errors.Add("Max Cached Nodes must be between 1000 and 500000.");
			if (Advanced.BackendPort < 1024 || Advanced.BackendPort > 65535) errors.Add("Backend Port must be between 1024 and 65535.");
			if (Advanced.SignalrReconnectDelaysMs < 500 || Advanced.SignalrReconnectDelaysMs > 30000) errors.Add("SignalR Reconnect Delay must be between 500ms and 30000ms.");
			if (Advanced.MaxSignalrRetries < 1 || Advanced.MaxSignalrRetries > 100) errors.Add("Max SignalR Retries must be between 1 and 100.");

			return errors;
		}
	}
}

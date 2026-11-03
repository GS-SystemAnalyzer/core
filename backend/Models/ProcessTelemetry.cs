namespace GSSystemAnalyzer.Models
{
	public class ProcessTelemetry
	{
		public int ProcessId { get; set; }
		public string Name { get; set; } = string.Empty;
		public long WorkingSetBytes { get; set; }
		public long? PrivateWorkingSetBytes { get; set; }
		public long? CommitBytes { get; set; }
		public double RamMb => Math.Round(WorkingSetBytes / 1024.0 / 1024.0, 2);

		// Process Explorer fields
		public string User { get; set; } = "SYSTEM";
		public double CpuPercent { get; set; }
		public string Status { get; set; } = "RUNNING";
	}

	internal sealed record ProcessMemorySample(
		int ProcessId,
		string Name,
		long CreationTimeTicks,
		long CpuTimeTicks,
		long WorkingSetBytes,
		long? PrivateWorkingSetBytes,
		long? CommitBytes);
}

namespace GSSystemAnalyzer.Models
{
	public class StorageNode
	{
		public string Name { get; set; } = string.Empty;
		public string Path { get; set; } = string.Empty;
		public string Type { get; set; } = "File";
		public long SizeBytes { get; set; }
		public DateTime LastModified { get; set; }
		// Windows attribute tiers surfaced for the two-tier visibility UI; default false keeps older payloads safe.
		public bool IsHidden { get; set; }
		public bool IsSystem { get; set; }
	}
}

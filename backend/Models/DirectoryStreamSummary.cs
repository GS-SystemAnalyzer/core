namespace GSSystemAnalyzer.Models
{
	public class DirectoryStreamSummary
	{
		public string Path { get; set; } = string.Empty;
		public string ParentPath { get; set; } = string.Empty;
		public long OwnBytes { get; set; }
		public long RecursiveBytes { get; set; }
		public bool RecursiveBytesFinal { get; set; } = true;
	}
}

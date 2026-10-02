using System.Text.Json.Serialization;

namespace GSSystemAnalyzer.Models;

public class FileTypeEntry
{
	public int Count { get; set; }
	public long Bytes { get; set; }
	public long LargestFileBytes { get; set; }
	// Persisted: largest file's NAME only. The full path is rebuilt at read time from the
	// owning folder key (FileTypeScanner.BuildFromMemory); storing it would duplicate the key.
	public string LargestFileName { get; set; } = string.Empty;
	[JsonIgnore] public string LargestFilePath { get; set; } = string.Empty;
}
public class FileTypeExtensionEntry
{
	public string Ext { get; set; } = string.Empty;
	public int FileCount { get; set; }
	public long TotalBytes { get; set; }
	public string SizeFormatted { get; set; } = string.Empty;
	public double PercentOfDisk { get; set; }
}

public class FileTypeCategory
{
	public string Name { get; set; } = string.Empty;
	public long TotalBytes { get; set; }
	public string SizeFormatted { get; set; } = string.Empty;
	public int FileCount { get; set; }
	public double PercentOfDisk { get; set; }
	public List<FileTypeExtensionEntry> Extensions { get; set; } = new();
}

public class FileTypeScanResult
{
	public string Root { get; set; } = string.Empty;
	public long TotalScannedBytes { get; set; }
	public string TotalScannedFormatted { get; set; } = string.Empty;
	public DateTime ScannedAt { get; set; }
	public List<FileTypeCategory> Categories { get; set; } = new();
}

public class ExtensionBreakdownItem
{
	public string Ext { get; set; } = string.Empty;
	public string Category { get; set; } = string.Empty;
	public int FileCount { get; set; }
	public long TotalBytes { get; set; }
	public string SizeFormatted { get; set; } = string.Empty;
	public double PercentOfDisk { get; set; }
	public long AverageFileSizeBytes { get; set; }
	public string AverageSizeFormatted { get; set; } = string.Empty;
	public string LargestFilePath { get; set; } = string.Empty;
	public long LargestFileBytes { get; set; }
	public string LargestSizeFormatted { get; set; } = string.Empty;
}

public class ExtensionBreakdownResult
{
	public string Root { get; set; } = string.Empty;
	public List<ExtensionBreakdownItem> Extensions { get; set; } = new();
}

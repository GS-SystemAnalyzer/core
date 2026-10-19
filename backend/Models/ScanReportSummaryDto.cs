namespace GSSystemAnalyzer.Models;

public record ScanCategorySummaryDto(
	string Name,
	int FileCount,
	long TotalBytes
);

public record TopDirectorySummaryDto(
	string Path,
	int FileCount,
	long OwnBytes,
	long RecursiveBytes
);

public record ScanReportSummaryDto(
	string Root,
	DateTimeOffset ScannedAt,
	DateTimeOffset ExportedAt,
	long TotalBytes,
	long TotalFiles,
	long DirectoryNodeCount,
	IReadOnlyList<ScanCategorySummaryDto> Categories,
	IReadOnlyList<TopDirectorySummaryDto> TopDirectories
);

using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IScanExportService
{
	bool HasCachedScan(string root);
	long GetCachedNodeCount(string root);
	ScanReportSummaryDto? GetReportSummary(string root, bool redactPaths);
	Task ExportAsync(string root, string format, bool redactPaths, Stream outputStream, CancellationToken ct = default);
}


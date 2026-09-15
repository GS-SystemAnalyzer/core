namespace GSSystemAnalyzer.Interfaces;

public interface IScanExportService
{
	bool HasCachedScan(string root);
	long GetCachedNodeCount(string root);
	Task ExportAsync(string root, string format, bool redactPaths, Stream outputStream, CancellationToken ct = default);
}

using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IScanExportService
{
	bool HasCachedScan(string root);
	long GetCachedNodeCount(string root);

	/// <summary>
	/// Retrieves a bounded summary of the cached scan for client-side report generation,
	/// including top 100 directories sorted by recursive bytes, category breakdowns, and totals.
	/// </summary>
	/// <param name="root">The scan root directory or drive path.</param>
	/// <param name="redactPaths">When true, user profile paths are replaced with '~'.</param>
	/// <returns>A <see cref="ScanReportSummaryDto"/> if scan cache exists; otherwise, null.</returns>
	ScanReportSummaryDto? GetReportSummary(string root, bool redactPaths);

	/// <summary>
	/// Streams the cached scan tree in JSON or CSV format directly to the output stream.
	/// </summary>
	/// <param name="root">The scan root directory or drive path.</param>
	/// <param name="format">Export format: "json" or "csv".</param>
	/// <param name="redactPaths">When true, user profile paths are replaced with '~'.</param>
	/// <param name="outputStream">The destination stream.</param>
	/// <param name="ct">Cancellation token.</param>
	/// <exception cref="NotSupportedException">Thrown when format is "html". HTML reports are generated client-side via <see cref="GetReportSummary"/>.</exception>
	Task ExportAsync(string root, string format, bool redactPaths, Stream outputStream, CancellationToken ct = default);
}


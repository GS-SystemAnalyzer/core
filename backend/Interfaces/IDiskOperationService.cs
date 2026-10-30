using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IDiskOperationService
{
	DriveTelemetryDto GetDriveTelemetry(string driveLetter);
	IEnumerable<StorageNode> ScanDirectory(string path, Guid scanId);
	Task<DirectoryStreamSummary> StreamDirectoryAsync(
		string path,
		Guid scanId,
		Func<IReadOnlyList<StorageNode>, Task> onChunk,
		CancellationToken ct = default);

	/// <summary>
	/// Begins a new scan session: cancels any in-flight scan and returns the
	/// cancellation token that ScanDirectory / duplicate detection will observe.
	/// </summary>
	Guid BeginScan(Guid? scanId = null);

	void TriggerScanAbort(Guid? scanId = null);
}

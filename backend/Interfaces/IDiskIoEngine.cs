using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces
{
	public interface IDiskIoEngine
	{
		DiskIoSnapshotCollection GetCurrentSnapshot();
		DiskIoSnapshotCollection SampleMetrics();
	}
}

using System;
using System.Collections.Generic;

namespace GSSystemAnalyzer.Models
{
	public record DiskIoSnapshot(
		string Id,
		string Model,
		IReadOnlyList<string> DriveLetters,
		double ReadBytesPerSec,
		double WriteBytesPerSec,
		double ActiveTimePercent,
		double AvgQueueLength,
		long SessionReadBytes,
		long SessionWriteBytes);

	public record DiskIoSnapshotCollection(
		DateTimeOffset Timestamp,
		IReadOnlyList<DiskIoSnapshot> Disks);

	public record DiskIoRawSample(
		string Id,
		string Name,
		double ReadBytesPerSec,
		double WriteBytesPerSec,
		double ActiveTimePercent,
		double AvgQueueLength,
		string? Model = null,
		IReadOnlyList<string>? DriveLetters = null);
}

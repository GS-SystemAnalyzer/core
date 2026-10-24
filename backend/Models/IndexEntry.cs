namespace GSSystemAnalyzer.Models;

public readonly record struct IndexEntry(
	string Path,
	string ParentPath,
	bool IsDirectory,
	long SizeBytes,
	DateTime LastWriteUtc,
	FileAttributes Attributes
);

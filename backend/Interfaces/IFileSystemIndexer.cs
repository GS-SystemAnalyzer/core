using GSSystemAnalyzer.Models;

namespace GSSystemAnalyzer.Interfaces;

public interface IFileSystemIndexer
{
	Task<IReadOnlyDictionary<string, IndexEntry>> IndexRootAsync(string rootPath, Guid scanId, CancellationToken cancellationToken);
	bool TryGetIndex(string rootPath, out IReadOnlyDictionary<string, IndexEntry> index);
	void Invalidate(string? rootPath = null);
}

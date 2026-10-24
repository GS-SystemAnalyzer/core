namespace GSSystemAnalyzer.Models;

using System.IO;
using GSSystemAnalyzer.Models.SettingDtos;

public class ScanTraversalRules
{
	private readonly int _maxDepth;
	private readonly List<string> _normalizedExcludedPaths;
	private readonly bool _followSymlinks;
	private readonly bool _skipHiddenFiles;
	private readonly bool _skipSystemFiles;
	private readonly long? _maxFileSizeBytes;

	public ScanTraversalRules(ScanSettingDto settings)
	{
		_maxDepth = settings.Depth;
		_normalizedExcludedPaths = (settings.ExcludedPaths ?? new List<string>())
			.Where(p => !string.IsNullOrWhiteSpace(p))
			.Select(NormalizePath)
			.ToList();
		_followSymlinks = settings.FollowSymlinks;
		_skipHiddenFiles = settings.SkipHiddenFiles;
		_skipSystemFiles = settings.SkipSystemFiles;
		_maxFileSizeBytes = settings.MaxFileSizeMb.HasValue && settings.MaxFileSizeMb.Value > 0
			? (long)settings.MaxFileSizeMb.Value * 1024 * 1024
			: null;
	}

	public bool IsDirectorySkipped(string dirPath, FileAttributes attributes, int currentDepth)
	{
		if (currentDepth > _maxDepth) return true;

		if (!_followSymlinks && attributes.HasFlag(FileAttributes.ReparsePoint)) return true;

		if (_skipHiddenFiles && attributes.HasFlag(FileAttributes.Hidden)) return true;

		if (_skipSystemFiles && attributes.HasFlag(FileAttributes.System)) return true;

		return IsPathExcluded(dirPath);
	}

	public bool IsFileSkipped(string filePath, FileAttributes attributes, long sizeBytes)
	{
		if (!_followSymlinks && attributes.HasFlag(FileAttributes.ReparsePoint)) return true;

		if (_skipHiddenFiles && attributes.HasFlag(FileAttributes.Hidden)) return true;

		if (_skipSystemFiles && attributes.HasFlag(FileAttributes.System)) return true;

		if (_maxFileSizeBytes.HasValue && sizeBytes > _maxFileSizeBytes.Value) return true;

		return IsPathExcluded(filePath);
	}

	public bool IsPathExcluded(string rawPath)
	{
		if (string.IsNullOrWhiteSpace(rawPath) || _normalizedExcludedPaths.Count == 0) return false;

		var normalized = NormalizePath(rawPath);

		foreach (var excluded in _normalizedExcludedPaths)
		{
			if (normalized.Equals(excluded, StringComparison.OrdinalIgnoreCase))
			{
				return true;
			}

			if (normalized.StartsWith(excluded, StringComparison.OrdinalIgnoreCase) &&
				(excluded.EndsWith('/') || (normalized.Length > excluded.Length && normalized[excluded.Length] == '/')))
			{
				return true;
			}
		}

		return false;
	}

	private static string NormalizePath(string path)
	{
		return path.Replace('\\', '/').TrimEnd('/');
	}
}

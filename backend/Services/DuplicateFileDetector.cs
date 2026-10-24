namespace GSSystemAnalyzer.Services;

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;

public class DuplicateFileDetector : IDuplicateFileDetector
{
	private readonly ISettingService _settings;
	private readonly IDiskScannerEngine _scanner;
	private readonly IFileSystemIndexer? _indexer;

	public DuplicateFileDetector(
		ISettingService settings,
		IDiskScannerEngine scanner,
		IFileSystemIndexer? indexer = null)
	{
		_settings = settings;
		_scanner = scanner;
		_indexer = indexer;
	}

	public async Task<List<DuplicateGroup>> FindDuplicatesAsync(string rootPath, Guid scanId)
	{
		try
		{
			var cancellationToken = _scanner.GetScanToken(scanId);

			List<(string Path, long Size)> candidates;

			if (_indexer != null)
			{
				if (!_indexer.TryGetIndex(rootPath, out var index))
				{
					index = await _indexer.IndexRootAsync(rootPath, scanId, cancellationToken);
				}

				candidates = index.Values
					.Where(e => !e.IsDirectory && e.SizeBytes > 0)
					.Select(e => (e.Path, e.SizeBytes))
					.ToList();
			}
			else
			{
				candidates = SafeEnumerateFiles(rootPath, cancellationToken)
					.Where(f => f.Length > 0)
					.Select(f => (f.FullName, f.Length))
					.ToList();
			}

			// Pass 1: Size pre-filter — unique sizes cannot be duplicates and are dropped
			var sizeGroups = candidates
				.GroupBy(c => c.Size)
				.Where(g => g.Count() > 1)
				.ToList();

			if (sizeGroups.Count == 0)
			{
				return new List<DuplicateGroup>();
			}

			var parallelOptions = new ParallelOptions
			{
				CancellationToken = cancellationToken,
				MaxDegreeOfParallelism = Math.Max(1, Environment.ProcessorCount / 2)
			};

			// Pass 2: Partial hash — for each size-collision group, hash the first 4 KB
			var partialHashed = new ConcurrentBag<(string Path, long Size, string PartialHash, bool IsFull)>();
			var filesForPartial = sizeGroups.SelectMany(g => g).ToList();

			await Parallel.ForEachAsync(filesForPartial, parallelOptions, async (file, ct) =>
			{
				try
				{
					var (hash, isFull) = await ComputePartialHashAsync(file.Path, file.Size, ct);
					partialHashed.Add((file.Path, file.Size, hash, isFull));
				}
				catch (IOException) { }
				catch (UnauthorizedAccessException) { }
			});

			var partialGroups = partialHashed
				.GroupBy(item => (item.Size, item.PartialHash))
				.Where(g => g.Count() > 1)
				.ToList();

			if (partialGroups.Count == 0)
			{
				return new List<DuplicateGroup>();
			}

			// Pass 3: Full hash — only for partial-hash collisions, compute full SHA-256
			var fullHashed = new ConcurrentBag<(string Path, long Size, string FullHash)>();
			var filesForFull = partialGroups.SelectMany(g => g).ToList();

			await Parallel.ForEachAsync(filesForFull, parallelOptions, async (item, ct) =>
			{
				try
				{
					string fullHash = item.IsFull
						? item.PartialHash
						: await ComputeFullHashAsync(item.Path, ct);

					fullHashed.Add((item.Path, item.Size, fullHash));
				}
				catch (IOException) { }
				catch (UnauthorizedAccessException) { }
			});

			return fullHashed
				.GroupBy(item => (item.Size, item.FullHash))
				.Where(g => g.Count() > 1)
				.Select(g => new DuplicateGroup
				{
					FileSizeBytes = g.Key.Size,
					FileHash = g.Key.FullHash,
					FilePaths = g.Select(i => i.Path).ToList()
				})
				.OrderByDescending(d => d.WastedBytes)
				.ToList();
		}
		finally
		{
			_scanner.EndScanSession(scanId);
		}
	}

	private static async Task<(string Hash, bool IsFull)> ComputePartialHashAsync(string filePath, long size, CancellationToken ct)
	{
		const int bufferSize = 4096;
		int readTarget = (int)Math.Min(size, bufferSize);
		byte[] buffer = new byte[readTarget];
		int bytesRead;

		using (var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, bufferSize, useAsync: true))
		{
			bytesRead = await stream.ReadAsync(buffer.AsMemory(0, buffer.Length), ct);
		}

		byte[] hashBytes = SHA256.HashData(buffer.AsSpan(0, bytesRead));
		string hashString = Convert.ToHexString(hashBytes);

		return (hashString, size <= bufferSize);
	}

	private static async Task<string> ComputeFullHashAsync(string filePath, CancellationToken ct)
	{
		using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite, 81920, useAsync: true);
		byte[] hashBytes = await SHA256.HashDataAsync(stream, ct);
		return Convert.ToHexString(hashBytes);
	}

	private IEnumerable<FileInfo> SafeEnumerateFiles(string rootPath, CancellationToken token)
	{
		var config = _settings.Current.Scan;
		var rootDir = new DirectoryInfo(rootPath);

		var options = new EnumerationOptions
		{
			IgnoreInaccessible = true,
			RecurseSubdirectories = true,
			ReturnSpecialDirectories = false,
			AttributesToSkip = 0
		};

		if (config.SkipHiddenFiles) options.AttributesToSkip |= FileAttributes.Hidden;
		if (config.SkipSystemFiles) options.AttributesToSkip |= FileAttributes.System;

		var files = Enumerable.Empty<FileInfo>();

		try
		{
			files = rootDir.EnumerateFiles("*.*", options);
		}
		catch (UnauthorizedAccessException) { }
		catch (DirectoryNotFoundException) { }
		catch (Exception) { }

		foreach (var file in files)
		{
			token.ThrowIfCancellationRequested();

			string appDataSegment = $"{Path.DirectorySeparatorChar}AppData{Path.DirectorySeparatorChar}";
			if (!rootPath.Contains(appDataSegment, StringComparison.OrdinalIgnoreCase)
				&& file.FullName.Contains(appDataSegment, StringComparison.OrdinalIgnoreCase))
			{
				continue;
			}

			yield return file;
		}
	}
}

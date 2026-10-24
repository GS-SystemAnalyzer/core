using System;
using System.IO;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Engine;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;

namespace GSSystemAnalyzer.Services;

public class LargeFileHunterService : ILargeFileHunterService
{
	private readonly IFileSystemIndexer _indexer;
	private readonly ILogger<LargeFileHunterService> _logger;

	public LargeFileHunterService(IFileSystemIndexer indexer, ILogger<LargeFileHunterService> logger)
	{
		_indexer = indexer;
		_logger = logger;
	}

	public async Task<List<LargeFile>> GetTopLargeFilesAsync(string rootPath, int topN, CancellationToken cancellationToken = default)
	{
		var stopwatch = System.Diagnostics.Stopwatch.StartNew();

		if (!_indexer.TryGetIndex(rootPath, out var index))
		{
			index = await _indexer.IndexRootAsync(rootPath, Guid.NewGuid(), cancellationToken);
		}

		var topFiles = new PriorityQueue<LargeFile, long>();

		foreach (var entry in index.Values)
		{
			cancellationToken.ThrowIfCancellationRequested();

			if (entry.IsDirectory || entry.SizeBytes <= 0) continue;

			long size = entry.SizeBytes;

			if (topFiles.Count < topN)
			{
				topFiles.Enqueue(new LargeFile { Path = entry.Path, SizeBytes = size }, size);
			}
			else if (size > topFiles.Peek().SizeBytes)
			{
				topFiles.EnqueueDequeue(new LargeFile { Path = entry.Path, SizeBytes = size }, size);
			}
		}

		var result = new List<LargeFile>(topFiles.Count);
		while (topFiles.Count > 0)
		{
			result.Add(topFiles.Dequeue());
		}

		result.Reverse();

		foreach (var file in result)
		{
			file.SizeFormatted = FormatSize(file.SizeBytes);
		}

		stopwatch.Stop();
		_logger.LogDebug("Large file scan completed in {ElapsedMs}ms", stopwatch.ElapsedMilliseconds);

		return result;
	}

	private static string FormatSize(long bytes)
	{
		string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
		int counter = 0;
		decimal number = bytes;

		while (Math.Round(number / 1024) >= 1 && counter < suffixes.Length - 1)
		{
			number /= 1024;
			counter++;
		}

		return string.Format("{0:n1} {1}", number, suffixes[counter]);
	}
}

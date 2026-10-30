using System.Drawing;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;

namespace GSSystemAnalyzer.Services
{
	public class DiskOperationsService : IDiskOperationService
	{
		private readonly DiskScannerEngine _scanner;
		private readonly IHubContext<SystemHub> _hubContext;
		private readonly ILogger<DiskOperationsService> _logger;
		private readonly IScanDiffService _scanDiff;
		private readonly IScanCacheService? _cacheService;
		private readonly IFileTypeScanner? _fileTypeScanner;

		public DiskOperationsService(
			DiskScannerEngine scanner,
			IHubContext<SystemHub> hubContext,
			ILogger<DiskOperationsService> logger,
			IScanDiffService scanDiff,
			IScanCacheService? cacheService = null,
			IFileTypeScanner? fileTypeScanner = null)
		{
			_scanner = scanner;
			_hubContext = hubContext;
			_logger = logger;
			_scanDiff = scanDiff;
			_cacheService = cacheService;
			_fileTypeScanner = fileTypeScanner;
		}

		public DriveTelemetryDto GetDriveTelemetry(string driveLetter)
		{
			var drive = new DriveInfo(driveLetter);

			var total = drive.TotalSize;
			var free = drive.TotalFreeSpace;
			var used = total - free;

			return new DriveTelemetryDto
			{
				TotalBytes = total,
				FreeBytes = free,
				UsedBytes = used,
				PercentageFree = Math.Round((double)free / total * 100, 1)
			};
		}

		public IEnumerable<StorageNode> ScanDirectory(string path, Guid scanId)
		{
			try
			{
				// A hidden/system folder opened directly as the scan target is skipped per its toggle; drive roots are never gated.
				if (!IsDriveRoot(path) && _scanner.IsPathSkippedByFilter(path))
				{
					_logger.LogDebug("Scan target {Path} excluded by hidden/system filter", path);
					return new List<StorageNode>();
				}

				var items = _scanner.LoadDirectoryItems(path);
				PurgeDeadMemory(path, items);
				_scanner.CalculateMissingSizesAsync(items, scanId).GetAwaiter().GetResult();

				var nodes = items.Select(item =>
				{
					DateTime safeDate;
					try
					{
						safeDate = item.LastWriteTime;
					}
					catch
					{
						safeDate = DateTime.UtcNow;
					}

					long itemSize = 0;
					if (item is FileInfo f) itemSize = f.Length;
					else if (item is DirectoryInfo d)
					{
						if (_cacheService != null && _cacheService.TryGetNode(d.FullName, out var node) && node != null)
						{
							itemSize = node.RecursiveBytes;
						}
						else if (_scanner.DirectorySizeCache.TryGetValue(d.FullName, out var cachedSize))
						{
							itemSize = cachedSize.Size;
						}
					}


					return new StorageNode
					{
						Name = item.Name,
						Path = item.FullName,
						ParentPath = path,
						Type = item.Attributes.HasFlag(FileAttributes.Directory) ? "Directory" : "File",
						SizeBytes = itemSize,
						LastModified = safeDate,
						IsHidden = item.Attributes.HasFlag(FileAttributes.Hidden),
						IsSystem = item.Attributes.HasFlag(FileAttributes.System),
						OwnBytes = item is FileInfo ? itemSize : 0,
						RecursiveBytes = itemSize,
						RecursiveBytesFinal = true
					};
				}).ToList();

				var actualFolderSize = nodes.Sum(n => n.SizeBytes);

				var normalizedPath = Path.GetFullPath(path);
				_scanner.DirectorySizeCache.TryGetValue(normalizedPath, out var oldEntry);
				_scanner.DirectorySizeCache[normalizedPath] = new CacheEntry
				{
					Size = actualFolderSize,
					LastUpdated = DateTime.UtcNow,
					Extensions = oldEntry?.Extensions
				};

				if (_cacheService != null)
				{
					var rootNodeKey = ScanCacheService.NormalizePath(path);
					var rootMeta = new ScanRootMeta(
						DriveRoot: path,
						Depth: 5,
						ScannedAt: DateTimeOffset.UtcNow,
						TotalBytes: actualFolderSize,
						TotalFiles: nodes.Count,
						RootNodeKey: rootNodeKey
					);
					_cacheService.SetScanRoot(rootMeta);

					var directFiles = items.OfType<FileInfo>().Select(f => new CachedFileEntry(
						f.Name,
						string.IsNullOrEmpty(f.Extension) ? "(none)" : f.Extension.ToLowerInvariant(),
						f.Length,
						f.LastWriteTimeUtc
					)).ToList();

					var directSubDirs = items.OfType<DirectoryInfo>().Select(d => d.FullName).ToList();

					var rootDirNode = new CachedDirNode(
						Path: path,
						ChildDirectoryPaths: directSubDirs,
						Files: directFiles,
						OwnBytes: directFiles.Sum(f => f.Length),
						RecursiveBytes: actualFolderSize,
						CachedAt: DateTimeOffset.UtcNow,
						RecursiveBytesStale: false
					);
					_cacheService.SetNode(rootDirNode, path);
				}

				try
				{
					_fileTypeScanner?.Invalidate(path);
				}
				catch (Exception ex)
				{
					_logger.LogDebug(ex, "Failed to invalidate file types cache for {Path}", path);
				}

				Task.Run(() => _scanner.SaveMemoryToDisk());

				// Compute the scan diff + promote the baseline, but only for whole-drive scans —
				// browsing individual subfolders should not accumulate baselines or reset a drive's.
				if (IsDriveRoot(path))
				{
					try
					{
						_scanDiff.ComputeAndPromote(path);
					}
					catch (Exception ex)
					{
						_logger.LogWarning(ex, "Scan diff computation failed for {Path}", path);
					}
				}

				return nodes;
			}
			finally
			{
				_scanner.EndScanSession(scanId);
			}
		}

		public async Task<DirectoryStreamSummary> StreamDirectoryAsync(
			string path,
			Guid scanId,
			Func<IReadOnlyList<StorageNode>, Task> onChunk,
			CancellationToken ct = default)
		{
			var parentPath = Path.GetDirectoryName(path) ?? string.Empty;
			var summary = new DirectoryStreamSummary
			{
				Path = path,
				ParentPath = parentPath,
				RecursiveBytesFinal = true
			};

			try
			{
				if (!IsDriveRoot(path) && _scanner.IsPathSkippedByFilter(path))
				{
					_logger.LogDebug("Scan target {Path} excluded by hidden/system filter", path);
					return summary;
				}

				var scanToken = _scanner.GetScanToken(scanId);
				using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(scanToken, ct);
				var token = linkedCts.Token;

				var items = _scanner.LoadDirectoryItems(path);
				PurgeDeadMemory(path, items);

				long ownBytes = 0;
				var directFiles = new List<CachedFileEntry>();
				var immediateNodes = new List<StorageNode>();
				var cachedSubDirNodes = new List<StorageNode>();

				foreach (var item in items)
				{
					DateTime safeDate;
					try
					{
						safeDate = item.LastWriteTime;
					}
					catch
					{
						safeDate = DateTime.UtcNow;
					}

					if (item is FileInfo f)
					{
						ownBytes += f.Length;
						directFiles.Add(new CachedFileEntry(
							f.Name,
							string.IsNullOrEmpty(f.Extension) ? "(none)" : f.Extension.ToLowerInvariant(),
							f.Length,
							f.LastWriteTimeUtc
						));

						immediateNodes.Add(new StorageNode
						{
							Name = f.Name,
							Path = f.FullName,
							ParentPath = path,
							Type = "File",
							SizeBytes = f.Length,
							LastModified = safeDate,
							IsHidden = f.Attributes.HasFlag(FileAttributes.Hidden),
							IsSystem = f.Attributes.HasFlag(FileAttributes.System),
							OwnBytes = f.Length,
							RecursiveBytes = f.Length,
							RecursiveBytesFinal = true
						});
					}
					else if (item is DirectoryInfo d)
					{
						if (_cacheService != null && _cacheService.TryGetNode(d.FullName, out var cachedNode) && cachedNode != null)
						{
							cachedSubDirNodes.Add(new StorageNode
							{
								Name = d.Name,
								Path = d.FullName,
								ParentPath = path,
								Type = "Directory",
								SizeBytes = cachedNode.RecursiveBytes,
								LastModified = safeDate,
								IsHidden = d.Attributes.HasFlag(FileAttributes.Hidden),
								IsSystem = d.Attributes.HasFlag(FileAttributes.System),
								OwnBytes = cachedNode.OwnBytes,
								RecursiveBytes = cachedNode.RecursiveBytes,
								RecursiveBytesFinal = true
							});
						}
						else if (_scanner.DirectorySizeCache.TryGetValue(d.FullName, out var cachedSize))
						{
							cachedSubDirNodes.Add(new StorageNode
							{
								Name = d.Name,
								Path = d.FullName,
								ParentPath = path,
								Type = "Directory",
								SizeBytes = cachedSize.Size,
								LastModified = safeDate,
								IsHidden = d.Attributes.HasFlag(FileAttributes.Hidden),
								IsSystem = d.Attributes.HasFlag(FileAttributes.System),
								OwnBytes = 0,
								RecursiveBytes = cachedSize.Size,
								RecursiveBytesFinal = true
							});
						}
					}
				}

				summary.OwnBytes = ownBytes;

				await using (var channel = new CoalescingStreamChannel<StorageNode>(
					onChunk,
					TimeSpan.FromMilliseconds(100),
					100,
					token))
				{
					// Phase A: Stream immediate files and cached subdirectories without delay
					foreach (var node in immediateNodes)
					{
						channel.TryWrite(node);
					}
					foreach (var node in cachedSubDirNodes)
					{
						channel.TryWrite(node);
					}

					// Phase B: Stream uncached subdirectories as their subtree calculations complete in parallel
					await _scanner.CalculateMissingSizesAsync(items, scanId, onSubtreeCompleted: (dir, size) =>
					{
						DateTime dirDate;
						try
						{
							dirDate = dir.LastWriteTime;
						}
						catch
						{
							dirDate = DateTime.UtcNow;
						}

						var node = new StorageNode
						{
							Name = dir.Name,
							Path = dir.FullName,
							ParentPath = path,
							Type = "Directory",
							SizeBytes = size,
							LastModified = dirDate,
							IsHidden = dir.Attributes.HasFlag(FileAttributes.Hidden),
							IsSystem = dir.Attributes.HasFlag(FileAttributes.System),
							OwnBytes = 0,
							RecursiveBytes = size,
							RecursiveBytesFinal = true
						};
						channel.TryWrite(node);
					});

					channel.Complete();
				}

				// Finalize directory cache
				long totalFolderSize = ownBytes;
				foreach (var item in items.OfType<DirectoryInfo>())
				{
					if (_cacheService != null && _cacheService.TryGetNode(item.FullName, out var node) && node != null)
					{
						totalFolderSize += node.RecursiveBytes;
					}
					else if (_scanner.DirectorySizeCache.TryGetValue(item.FullName, out var cachedSize))
					{
						totalFolderSize += cachedSize.Size;
					}
				}

				summary.RecursiveBytes = totalFolderSize;

				var normalizedPath = Path.GetFullPath(path);
				_scanner.DirectorySizeCache.TryGetValue(normalizedPath, out var oldEntry);
				_scanner.DirectorySizeCache[normalizedPath] = new CacheEntry
				{
					Size = totalFolderSize,
					LastUpdated = DateTime.UtcNow,
					Extensions = oldEntry?.Extensions
				};

				if (_cacheService != null)
				{
					var rootNodeKey = ScanCacheService.NormalizePath(path);
					var rootMeta = new ScanRootMeta(
						DriveRoot: path,
						Depth: 5,
						ScannedAt: DateTimeOffset.UtcNow,
						TotalBytes: totalFolderSize,
						TotalFiles: items.Count,
						RootNodeKey: rootNodeKey
					);
					_cacheService.SetScanRoot(rootMeta);

					var directSubDirs = items.OfType<DirectoryInfo>().Select(d => d.FullName).ToList();
					var rootDirNode = new CachedDirNode(
						Path: path,
						ChildDirectoryPaths: directSubDirs,
						Files: directFiles,
						OwnBytes: ownBytes,
						RecursiveBytes: totalFolderSize,
						CachedAt: DateTimeOffset.UtcNow,
						RecursiveBytesStale: false
					);
					_cacheService.SetNode(rootDirNode, path);
				}

				try
				{
					_fileTypeScanner?.Invalidate(path);
				}
				catch (Exception ex)
				{
					_logger.LogDebug(ex, "Failed to invalidate file types cache for {Path}", path);
				}

				Task.Run(() => _scanner.SaveMemoryToDisk());

				if (IsDriveRoot(path))
				{
					try
					{
						_scanDiff.ComputeAndPromote(path);
					}
					catch (Exception ex)
					{
						_logger.LogWarning(ex, "Scan diff computation failed for {Path}", path);
					}
				}

				return summary;
			}
			finally
			{
				_scanner.EndScanSession(scanId);
			}
		}

		private void PurgeDeadMemory(string currentPath, List<FileSystemInfo> actualItems)
		{
			var memoryChanged = false;

			var actualPaths =
				new HashSet<string>(actualItems.Select(i => i.FullName), StringComparer.OrdinalIgnoreCase);

			var pathWithSlash = currentPath.EndsWith(Path.DirectorySeparatorChar.ToString())
				? currentPath
				: currentPath + Path.DirectorySeparatorChar;

			var keysToCheck = _scanner.DirectorySizeCache.Keys
				.Where(k => k.StartsWith(pathWithSlash, StringComparison.OrdinalIgnoreCase))
				.Where(k => k.Length >= pathWithSlash.Length && k.IndexOf(Path.DirectorySeparatorChar, pathWithSlash.Length) == -1)
				.ToList();

			foreach (var key in keysToCheck)
			{
				if (!actualPaths.Contains(key))
				{
					_scanner.DirectorySizeCache.TryRemove(key, out _);
					memoryChanged = true;
					_logger.LogDebug("Cache purged: removed ghost folder {Key}", key);
				}
			}

			if (memoryChanged)
			{
				Task.Run(() => _scanner.SaveMemoryToDisk());
			}
		}

		private static bool IsDriveRoot(string path)
		{
			var full = Path.GetFullPath(path);
			var root = Path.GetPathRoot(full);
			return !string.IsNullOrEmpty(root)
				&& string.Equals(
					full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
					root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
					StringComparison.OrdinalIgnoreCase);
		}

		public Guid BeginScan(Guid? scanId = null) => _scanner.BeginScanSession(scanId);

		public void TriggerScanAbort(Guid? scanId = null)
		{
			_scanner.TriggerScanAbort(scanId);
		}
	}
}

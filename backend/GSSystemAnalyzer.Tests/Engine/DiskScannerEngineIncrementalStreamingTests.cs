using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using GSSystemAnalyzer.Tests.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine
{
	public class DiskScannerEngineIncrementalStreamingTests : IDisposable
	{
		private readonly DiskScannerEngine _engine;
		private readonly string _root;
		private readonly string _tempCacheFile;
		private readonly Mock<IHubContext<SystemHub>> _hubMock;
		private readonly ScannerCacheTestScope _cacheScope = new();

		public DiskScannerEngineIncrementalStreamingTests()
		{
			_hubMock = new Mock<IHubContext<SystemHub>>();
			var clientsMock = new Mock<IHubClients>();
			var proxyMock = new Mock<IClientProxy>();
			_hubMock.Setup(h => h.Clients).Returns(clientsMock.Object);
			clientsMock.Setup(c => c.All).Returns(proxyMock.Object);
			proxyMock
				.Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
				.Returns(Task.CompletedTask);

			var settings = new Mock<ISettingService>();
			var defaults = AppSettingDto.GetFactoryDefaults();
			defaults.Scan.SkipHiddenFiles = false;
			defaults.Scan.SkipSystemFiles = false;
			settings.SetupGet(s => s.Current).Returns(defaults);

			_tempCacheFile = _cacheScope.CreateCachePath();
			_engine = new DiskScannerEngine(_hubMock.Object, settings.Object, NullLogger<DiskScannerEngine>.Instance,
				cacheFilePath: _tempCacheFile);

			_root = Path.Combine(Path.GetTempPath(), "gsa_stream_root_" + Guid.NewGuid().ToString("N"));
			Directory.CreateDirectory(_root);
		}

		public void Dispose()
		{
			_engine.Dispose();
			try { if (Directory.Exists(_root)) Directory.Delete(_root, true); } catch { }
			_cacheScope.Dispose();
		}

		[Fact]
		public async Task CoalescingStreamChannel_FlushesOnBatchSizeReached()
		{
			var batches = new ConcurrentQueue<IReadOnlyList<int>>();
			await using var channel = new CoalescingStreamChannel<int>(
				items =>
				{
					batches.Enqueue(items);
					return Task.CompletedTask;
				},
				TimeSpan.FromSeconds(5),
				maxBatchSize: 5);

			for (int i = 0; i < 5; i++)
			{
				channel.TryWrite(i);
			}

			// Allow consumer task to process
			for (int w = 0; w < 20 && batches.IsEmpty; w++)
			{
				await Task.Delay(50);
			}

			Assert.Single(batches);
			Assert.Equal(5, batches.First().Count);

		}

		[Fact]
		public async Task CoalescingStreamChannel_FlushesOnTimeout()
		{
			var batches = new ConcurrentQueue<IReadOnlyList<string>>();
			await using var channel = new CoalescingStreamChannel<string>(
				items =>
				{
					batches.Enqueue(items);
					return Task.CompletedTask;
				},
				TimeSpan.FromMilliseconds(50),
				maxBatchSize: 100);

			channel.TryWrite("Item1");
			channel.TryWrite("Item2");

			for (int w = 0; w < 20 && batches.IsEmpty; w++)
			{
				await Task.Delay(50);
			}

			Assert.Single(batches);
			Assert.Equal(2, batches.First().Count);

		}

		[Fact]
		public async Task CalculateMissingSizesAsync_InvokesOnSubtreeCompleted()
		{
			var subDirA = Directory.CreateDirectory(Path.Combine(_root, "DirA"));
			var subDirB = Directory.CreateDirectory(Path.Combine(_root, "DirB"));
			File.WriteAllBytes(Path.Combine(subDirA.FullName, "a.bin"), new byte[1024]);
			File.WriteAllBytes(Path.Combine(subDirB.FullName, "b.bin"), new byte[2048]);

			var items = new DirectoryInfo(_root).GetFileSystemInfos().ToList();
			var scanId = _engine.BeginScanSession();
			var completedDirs = new ConcurrentBag<(string Path, long Size)>();

			try
			{
				await _engine.CalculateMissingSizesAsync(items, scanId, (dir, size) =>
				{
					completedDirs.Add((dir.FullName, size));
				});
			}
			finally
			{
				_engine.EndScanSession(scanId);
			}

			Assert.Equal(2, completedDirs.Count);
			Assert.Contains(completedDirs, d => d.Path == subDirA.FullName && d.Size >= 1024);
			Assert.Contains(completedDirs, d => d.Path == subDirB.FullName && d.Size >= 2048);
		}

		[Fact]
		public async Task StreamDirectoryAsync_StreamsFilesAndFoldersIncrementally()
		{
			File.WriteAllBytes(Path.Combine(_root, "root_file.txt"), new byte[512]);
			var subDir = Directory.CreateDirectory(Path.Combine(_root, "SubFolder"));
			File.WriteAllBytes(Path.Combine(subDir.FullName, "child.dat"), new byte[4096]);

			var scanDiffMock = new Mock<IScanDiffService>();
			var service = new DiskOperationsService(
				_engine,
				_hubMock.Object,
				NullLogger<DiskOperationsService>.Instance,
				scanDiffMock.Object);

			var scanId = service.BeginScan();
			var streamedChunks = new List<IReadOnlyList<StorageNode>>();

			var summary = await service.StreamDirectoryAsync(
				_root,
				scanId,
				chunk =>
				{
					lock (streamedChunks)
					{
						streamedChunks.Add(chunk);
					}
					return Task.CompletedTask;
				});

			Assert.NotNull(summary);
			Assert.Equal(_root, summary.Path);
			Assert.True(summary.RecursiveBytesFinal);
			Assert.True(summary.RecursiveBytes >= 4608);
			var saved = JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(_tempCacheFile))!;
			Assert.Equal(summary.RecursiveBytes, saved[Path.GetFullPath(_root)].Size);

			var allStreamedNodes = streamedChunks.SelectMany(c => c).ToList();
			Assert.Contains(allStreamedNodes, n => n.Name == "root_file.txt" && n.Type == "File" && n.SizeBytes == 512);
			Assert.Contains(allStreamedNodes, n => n.Name == "SubFolder" && n.Type == "Directory" && n.SizeBytes >= 4096);
		}

		[Fact]
		public async Task StreamDirectoryAsync_StreamsUncachedDirectoriesInPhaseB_WhenScanCompletes()
		{
			var uncachedDir = Directory.CreateDirectory(Path.Combine(_root, "UncachedUsersFolder"));
			File.WriteAllBytes(Path.Combine(uncachedDir.FullName, "large_file.dat"), new byte[8192]);

			var scanDiffMock = new Mock<IScanDiffService>();
			var service = new DiskOperationsService(
				_engine,
				_hubMock.Object,
				NullLogger<DiskOperationsService>.Instance,
				scanDiffMock.Object);

			var scanId = service.BeginScan();
			var streamedChunks = new List<IReadOnlyList<StorageNode>>();

			await service.StreamDirectoryAsync(
				_root,
				scanId,
				chunk =>
				{
					lock (streamedChunks)
					{
						streamedChunks.Add(chunk);
					}
					return Task.CompletedTask;
				});

			var allStreamedNodes = streamedChunks.SelectMany(c => c).ToList();
			// Uncached folder must not appear provisionally with false recursive status
			Assert.DoesNotContain(allStreamedNodes, n => n.Name == "UncachedUsersFolder" && !n.RecursiveBytesFinal);
			// It must be emitted upon subtree scan completion with final recursive size
			var finalNode = Assert.Single(allStreamedNodes.Where(n => n.Name == "UncachedUsersFolder"));
			Assert.True(finalNode.RecursiveBytesFinal && finalNode.SizeBytes >= 8192);
		}
	}
}

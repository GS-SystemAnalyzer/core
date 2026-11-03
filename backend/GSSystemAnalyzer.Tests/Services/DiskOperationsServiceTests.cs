using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;
using Xunit.Abstractions;

namespace GSSystemAnalyzer.Tests.Services;

// Pins the attribute mapping: ScanDirectory stamps IsHidden/IsSystem onto each
// StorageNode from the entry's FileAttributes, independently for the two tiers.
public class DiskOperationsServiceTests : IDisposable
{
	private readonly string _tempRoot;
	private readonly string _tempCacheFile;
	private readonly AppSettingDto _appSettings;
	private readonly DiskScannerEngine _engine;
	private readonly DiskOperationsService _service;
	private readonly ScannerCacheTestScope _cacheScope = new();
	private readonly ITestOutputHelper _output;
	private readonly IHubContext<SystemHub> _hubContext;

	public DiskOperationsServiceTests(ITestOutputHelper output)
	{
		_output = output;
		_tempRoot = Path.Combine(Path.GetTempPath(), $"gs215-{Guid.NewGuid():N}");
		Directory.CreateDirectory(_tempRoot);

		CreateDir("normalDir");
		SetAttributes(CreateDir("hiddenDir"), FileAttributes.Hidden);
		SetAttributes(CreateDir("systemDir"), FileAttributes.System);
		SetAttributes(CreateDir("hiddenSystemDir"), FileAttributes.Hidden | FileAttributes.System);

		_appSettings = AppSettingDto.GetFactoryDefaults();

		var settingsMock = new Mock<ISettingService>();
		settingsMock.Setup(s => s.Current).Returns(_appSettings);

		var hubMock = new Mock<IHubContext<SystemHub>>();
		var clientsMock = new Mock<IHubClients>();
		var proxyMock = new Mock<IClientProxy>();
		hubMock.Setup(h => h.Clients).Returns(clientsMock.Object);
		clientsMock.Setup(c => c.All).Returns(proxyMock.Object);
		proxyMock
			.Setup(c => c.SendCoreAsync(It.IsAny<string>(), It.IsAny<object?[]>(), It.IsAny<CancellationToken>()))
			.Returns(Task.CompletedTask);
		_hubContext = hubMock.Object;

		_tempCacheFile = _cacheScope.CreateCachePath();
		_engine = new DiskScannerEngine(hubMock.Object, settingsMock.Object, NullLogger<DiskScannerEngine>.Instance,
			cacheFilePath: _tempCacheFile);

		_service = new DiskOperationsService(
			_engine,
			_hubContext,
			NullLogger<DiskOperationsService>.Instance,
			new Mock<IScanDiffService>().Object);
	}

	private string CreateDir(string name)
	{
		var path = Path.Combine(_tempRoot, name);
		Directory.CreateDirectory(path);
		return path;
	}

	private static string SetAttributes(string path, FileAttributes add)
	{
		File.SetAttributes(path, File.GetAttributes(path) | add);
		return path;
	}

	private void DeferCacheCleanup(string cacheFilePath)
	{
		_cacheScope.DeferCleanup(cacheFilePath);
		_output.WriteLine("Deferred cache cleanup for host {0}: {1}",
			Environment.ProcessId, Path.GetDirectoryName(cacheFilePath));
	}

	[Fact]
	public void ScanDirectory_PopulatesHiddenAndSystemFlags_FromAttributes()
	{
		// Both toggles OFF so every entry survives the listing and its flags can be inspected.
		_appSettings.Scan.SkipHiddenFiles = false;
		_appSettings.Scan.SkipSystemFiles = false;

		var scanId = _engine.BeginScanSession();
		var nodes = _service.ScanDirectory(_tempRoot, scanId)
			.ToDictionary(n => n.Name, StringComparer.OrdinalIgnoreCase);

		Assert.False(nodes["normalDir"].IsHidden);
		Assert.False(nodes["normalDir"].IsSystem);

		Assert.True(nodes["hiddenDir"].IsHidden);
		Assert.False(nodes["hiddenDir"].IsSystem);

		Assert.False(nodes["systemDir"].IsHidden);
		Assert.True(nodes["systemDir"].IsSystem);

		Assert.True(nodes["hiddenSystemDir"].IsHidden);
		Assert.True(nodes["hiddenSystemDir"].IsSystem);
	}

	[Fact]
	public void ScanDirectory_ReturnsOnlyAfterFinalCacheSave()
	{
		var target = Directory.CreateDirectory(Path.Combine(_tempRoot, "direct-files"));
		File.WriteAllBytes(Path.Combine(target.FullName, "payload.bin"), new byte[512]);
		Assert.Empty(target.GetDirectories());
		Assert.False(_engine.IsScanning);
		var writeLock = typeof(DiskScannerEngine)
			.GetField("_fileWriteLock", BindingFlags.Instance | BindingFlags.NonPublic)!
			.GetValue(_engine)!;

		try
		{
			// An inline save can reenter this lock; a detached worker cannot acquire it.
			lock (writeLock)
			{
				var id = _service.BeginScan();
				var nodes = _service.ScanDirectory(target.FullName, id).ToList();
				Assert.Equal(512, Assert.Single(nodes).SizeBytes);
				Assert.True(File.Exists(_tempCacheFile), "ScanDirectory returned before its final cache save.");
				var saved = JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(_tempCacheFile))!;
				Assert.Equal(512, saved[Path.GetFullPath(target.FullName)].Size);
				Assert.False(_engine.GetScanToken(id).CanBeCanceled);
			}
		}
		catch
		{
			DeferCacheCleanup(_tempCacheFile);
			throw;
		}
	}

	[Fact]
	public void PurgeDeadMemory_FinishesItsOwnSave_WithoutAFinalScanSave()
	{
		var target = Directory.CreateDirectory(Path.Combine(_tempRoot, "purge-only"));
		var ghost = Path.Combine(target.FullName, "gone");
		var peerModel = Path.Combine(_tempRoot, "peer-model");
		_engine.DirectorySizeCache[ghost] = new CacheEntry { Size = 4096 };
		_engine.DirectorySizeCache[peerModel] = new CacheEntry { Size = 123 };
		var writeLock = typeof(DiskScannerEngine)
			.GetField("_fileWriteLock", BindingFlags.Instance | BindingFlags.NonPublic)!
			.GetValue(_engine)!;
		var purge = typeof(DiskOperationsService)
			.GetMethod("PurgeDeadMemory", BindingFlags.Instance | BindingFlags.NonPublic)!;
		try
		{
			lock (writeLock)
			{
				purge.Invoke(_service, new object[] { target.FullName, new List<FileSystemInfo>() });
				Assert.False(_engine.DirectorySizeCache.ContainsKey(ghost));
				Assert.True(File.Exists(_tempCacheFile), "The purge returned before its own cache save.");
				var saved = JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(_tempCacheFile))!;
				Assert.False(saved.ContainsKey(ghost));
				Assert.Equal(123, Assert.Single(saved).Value.Size);
			}
		}
		catch
		{
			DeferCacheCleanup(_tempCacheFile);
			throw;
		}
	}

	[Theory]
	[InlineData(0, false)]
	[InlineData(0, true)]
	[InlineData(1000, false)]
	[InlineData(1000, true)]
	[InlineData(10000, false)]
	[InlineData(10000, true)]
	public async Task StreamDirectoryAsync_ReturnsPersistedTotals_WithAndWithoutGhostPurge(int cachedEntries, bool includeGhost)
	{
		var target = Directory.CreateDirectory(Path.Combine(_tempRoot, "stream-work"));
		File.WriteAllBytes(Path.Combine(target.FullName, "payload.bin"), new byte[512]);
		var stamp = DateTime.UtcNow;
		for (var i = 0; i < cachedEntries; i++)
		{
			_engine.DirectorySizeCache[Path.Combine(_tempRoot, "model", i.ToString())] = new CacheEntry
			{
				Size = i, CachedAtUtc = stamp, LastUpdated = stamp
			};
		}
		var ghost = Path.Combine(target.FullName, "gone");
		if (includeGhost) _engine.DirectorySizeCache[ghost] = new CacheEntry { Size = 4096 };

		var timer = Stopwatch.StartNew();
		TimeSpan? firstChunk = null;
		TimeSpan? finalized = null;
		var fileTypes = new Mock<IFileTypeScanner>();
		fileTypes.Setup(f => f.Invalidate(target.FullName)).Callback(() => finalized = timer.Elapsed);
		var service = new DiskOperationsService(_engine, _hubContext, NullLogger<DiskOperationsService>.Instance,
			new Mock<IScanDiffService>().Object, fileTypeScanner: fileTypes.Object);
		var id = service.BeginScan();
		var summary = await service.StreamDirectoryAsync(target.FullName, id, _ =>
		{
			firstChunk ??= timer.Elapsed;
			return Task.CompletedTask;
		});
		var returned = timer.Elapsed;
		Assert.NotNull(firstChunk);
		Assert.NotNull(finalized);
		Assert.Equal(512, summary.RecursiveBytes);
		var saved = JsonSerializer.Deserialize<Dictionary<string, CacheEntry>>(File.ReadAllText(_tempCacheFile))!;
		Assert.Equal(512, saved[Path.GetFullPath(target.FullName)].Size);
		Assert.False(saved.ContainsKey(ghost));
		Assert.False(_engine.GetScanToken(id).CanBeCanceled);

		var saveTimer = Stopwatch.StartNew();
		_engine.SaveMemoryToDisk();
		saveTimer.Stop();
		_output.WriteLine("entries={0}, ghost={1}, firstChunkMs={2:F3}, finalizedMs={3:F3}, returnedMs={4:F3}, separateSaveMs={5:F3}",
			cachedEntries, includeGhost, firstChunk.Value.TotalMilliseconds, finalized.Value.TotalMilliseconds,
			returned.TotalMilliseconds, saveTimer.Elapsed.TotalMilliseconds);
	}

	[Fact]
	public async Task StreamDirectoryAsync_CancellationDuringSave_WaitsForTheSaveAttempt()
	{
		var target = Directory.CreateDirectory(Path.Combine(_tempRoot, "save-cancel"));
		File.WriteAllBytes(Path.Combine(target.FullName, "payload.bin"), new byte[512]);
		var cacheFilePath = _cacheScope.CreateCachePath();
		Directory.CreateDirectory(Path.GetDirectoryName(cacheFilePath)!);
		using var blockedFile = new FileStream(cacheFilePath + ".tmp", FileMode.Create, FileAccess.ReadWrite, FileShare.None);
		using var releaseSave = new ManualResetEventSlim();
		var saveStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
		var logger = new Mock<ILogger<DiskScannerEngine>>();
		logger.Setup(l => l.Log(LogLevel.Error, It.IsAny<EventId>(), It.IsAny<It.IsAnyType>(),
			It.IsAny<Exception>(), It.IsAny<Func<It.IsAnyType, Exception?, string>>()))
			.Callback(new InvocationAction(_ =>
			{
				saveStarted.TrySetResult();
				releaseSave.Wait();
			}));
		var settings = new Mock<ISettingService>();
		settings.SetupGet(s => s.Current).Returns(_appSettings);
		using var engine = new DiskScannerEngine(_hubContext, settings.Object, logger.Object, cacheFilePath: cacheFilePath);
		var service = new DiskOperationsService(engine, _hubContext, NullLogger<DiskOperationsService>.Instance,
			new Mock<IScanDiffService>().Object);
		var id = service.BeginScan();
		var operation = service.StreamDirectoryAsync(target.FullName, id, _ => Task.CompletedTask);
		try
		{
			await saveStarted.Task.WaitAsync(TimeSpan.FromSeconds(10));
			Assert.False(operation.IsCompleted);
			Assert.True(engine.GetScanToken(id).CanBeCanceled);
			engine.TriggerScanAbort(id);
			Assert.True(engine.GetScanToken(id).IsCancellationRequested);
			Assert.False(operation.IsCompleted);
		}
		catch
		{
			DeferCacheCleanup(cacheFilePath);
			throw;
		}
		finally
		{
			releaseSave.Set();
			try
			{
				var summary = await operation;
				Assert.Equal(512, summary.RecursiveBytes);
				Assert.False(engine.GetScanToken(id).CanBeCanceled);
			}
			catch
			{
				DeferCacheCleanup(cacheFilePath);
				throw;
			}
		}
		logger.Verify(l => l.Log(LogLevel.Error, It.IsAny<EventId>(), It.IsAny<It.IsAnyType>(),
			It.IsAny<Exception>(), It.IsAny<Func<It.IsAnyType, Exception?, string>>()), Times.Once);
	}

	public void Dispose()
	{
		_engine.Dispose();
		try { Directory.Delete(_tempRoot, recursive: true); }
		catch (DirectoryNotFoundException) { }
		catch (IOException) { }
		_cacheScope.Dispose();
	}
}

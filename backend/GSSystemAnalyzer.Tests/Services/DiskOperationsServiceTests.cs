using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;
using GSSystemAnalyzer.Services;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Services;

// Pins the #215 attribute mapping: ScanDirectory stamps IsHidden/IsSystem onto each
// StorageNode from the entry's FileAttributes, independently for the two tiers.
public class DiskOperationsServiceTests : IDisposable
{
	private readonly string _tempRoot;
	private readonly string _tempCacheFile;
	private readonly AppSettingDto _appSettings;
	private readonly DiskScannerEngine _engine;
	private readonly DiskOperationsService _service;

	public DiskOperationsServiceTests()
	{
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

		_engine = new DiskScannerEngine(hubMock.Object, settingsMock.Object, NullLogger<DiskScannerEngine>.Instance);
		_engine.DirectorySizeCache.Clear();

		// Redirect the on-disk cache so the scan's SaveMemoryToDisk never touches the real %APPDATA% file.
		_tempCacheFile = Path.Combine(Path.GetTempPath(), $"gs215-cache-{Guid.NewGuid():N}.json");
		typeof(DiskScannerEngine)
			.GetField("_cacheFilePath", BindingFlags.Instance | BindingFlags.NonPublic)!
			.SetValue(_engine, _tempCacheFile);

		_service = new DiskOperationsService(
			_engine,
			hubMock.Object,
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

	public void Dispose()
	{
		_engine.Dispose();
		try { Directory.Delete(_tempRoot, recursive: true); }
		catch (DirectoryNotFoundException) { }
		catch (IOException) { }
		try { if (File.Exists(_tempCacheFile)) File.Delete(_tempCacheFile); }
		catch (IOException) { }
	}
}

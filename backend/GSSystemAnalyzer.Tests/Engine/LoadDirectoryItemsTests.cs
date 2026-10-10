using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Hubs;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models.SettingDtos;
using Microsoft.AspNetCore.SignalR;
using Microsoft.Extensions.Logging;
using Moq;
using Xunit;

namespace GSSystemAnalyzer.Tests.Engine;

public class LoadDirectoryItemsTests : IDisposable
{
	private readonly string _tempRoot;
	private readonly AppSettingDto _appSettings;
	private readonly DiskScannerEngine _engine;

	public LoadDirectoryItemsTests()
	{
		_tempRoot = Path.Combine(Path.GetTempPath(), $"gs214-{Guid.NewGuid():N}");
		Directory.CreateDirectory(_tempRoot);

		CreateDir("normalDir");
		SetAttributes(CreateDir("hiddenDir"), FileAttributes.Hidden);
		SetAttributes(CreateDir("systemDir"), FileAttributes.System);
		SetAttributes(CreateDir("hiddenSystemDir"), FileAttributes.Hidden | FileAttributes.System);
		CreateFile("normal.txt");
		SetAttributes(CreateFile("hidden.txt"), FileAttributes.Hidden);

		_appSettings = AppSettingDto.GetFactoryDefaults();

		var settingsMock = new Mock<ISettingService>();
		settingsMock.Setup(s => s.Current).Returns(_appSettings);
		var hubMock = new Mock<IHubContext<SystemHub>>();
		var loggerMock = new Mock<ILogger<DiskScannerEngine>>();

		_engine = new DiskScannerEngine(hubMock.Object, settingsMock.Object, loggerMock.Object);
	}

	private string CreateDir(string name)
	{
		var path = Path.Combine(_tempRoot, name);
		Directory.CreateDirectory(path);
		return path;
	}

	private string CreateFile(string name)
	{
		var path = Path.Combine(_tempRoot, name);
		File.WriteAllText(path, "x");
		return path;
	}

	private static string SetAttributes(string path, FileAttributes add)
	{
		File.SetAttributes(path, File.GetAttributes(path) | add);
		return path;
	}

	private static IEnumerable<string> Split(string csv) =>
		csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

	[Theory]
	[InlineData(null)]
	[InlineData("")]
	[InlineData("   ")]
	public void LoadDirectoryItems_InvalidPath_ReturnsEmptyList(string? path)
	{
		var result = _engine.LoadDirectoryItems(path!);

		Assert.Empty(result);
	}

	[Theory]
	[InlineData(true, true, "normalDir,normal.txt", "hiddenDir,systemDir,hiddenSystemDir,hidden.txt")]
	[InlineData(true, false, "normalDir,systemDir,normal.txt", "hiddenDir,hiddenSystemDir,hidden.txt")]
	[InlineData(false, true, "normalDir,hiddenDir,normal.txt,hidden.txt", "systemDir,hiddenSystemDir")]
	[InlineData(false, false, "normalDir,hiddenDir,systemDir,hiddenSystemDir,normal.txt,hidden.txt", "")]
	public void LoadDirectoryItems_HonoursSkipHiddenAndSkipSystem(
		bool skipHidden, bool skipSystem, string expectedPresent, string expectedAbsent)
	{
		_appSettings.Scan.SkipHiddenFiles = skipHidden;
		_appSettings.Scan.SkipSystemFiles = skipSystem;

		var names = _engine.LoadDirectoryItems(_tempRoot)
			.Select(i => i.Name)
			.ToHashSet(StringComparer.OrdinalIgnoreCase);

		foreach (var name in Split(expectedPresent))
			Assert.True(names.Contains(name), $"expected '{name}' to be listed");
		foreach (var name in Split(expectedAbsent))
			Assert.False(names.Contains(name), $"expected '{name}' to be filtered out");
	}

	[Theory]
	[InlineData("hiddenDir", true, false, true)]
	[InlineData("hiddenDir", false, true, false)]
	[InlineData("systemDir", false, true, true)]
	[InlineData("systemDir", true, false, false)]
	[InlineData("normalDir", true, true, false)]
	public void IsPathSkippedByFilter_HonoursToggles(string dirName, bool skipHidden, bool skipSystem, bool expectedSkipped)
	{
		_appSettings.Scan.SkipHiddenFiles = skipHidden;
		_appSettings.Scan.SkipSystemFiles = skipSystem;

		var skipped = _engine.IsPathSkippedByFilter(Path.Combine(_tempRoot, dirName));

		Assert.Equal(expectedSkipped, skipped);
	}

	[Fact]
	public void IsPathSkippedByFilter_MissingPath_ReturnsFalse()
	{
		var skipped = _engine.IsPathSkippedByFilter(Path.Combine(_tempRoot, "does-not-exist"));

		Assert.False(skipped);
	}

	public void Dispose()
	{
		_engine.Dispose();
		try
		{
			Directory.Delete(_tempRoot, recursive: true);
		}
		catch (DirectoryNotFoundException) { }
		catch (IOException) { }
	}
}

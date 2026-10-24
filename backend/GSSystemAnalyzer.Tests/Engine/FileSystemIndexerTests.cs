namespace GSSystemAnalyzer.Tests.Engine;

using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;
using GSSystemAnalyzer.Engine;
using GSSystemAnalyzer.Interfaces;
using GSSystemAnalyzer.Models;
using GSSystemAnalyzer.Models.SettingDtos;

public class FileSystemIndexerTests : IDisposable
{
	private readonly string _tempRoot;
	private readonly Mock<ISettingService> _mockSettings;

	public FileSystemIndexerTests()
	{
		_tempRoot = Path.Combine(Path.GetTempPath(), "gsa_indexer_" + Guid.NewGuid().ToString("N"));
		Directory.CreateDirectory(_tempRoot);

		_mockSettings = new Mock<ISettingService>();
		_mockSettings.Setup(s => s.Current).Returns(new AppSettingDto
		{
			Scan = new ScanSettingDto
			{
				Depth = 10,
				SkipHiddenFiles = true,
				SkipSystemFiles = true,
				FollowSymlinks = false,
				ExcludedPaths = new List<string> { "C:/Windows" }
			}
		});
	}

	public void Dispose()
	{
		if (Directory.Exists(_tempRoot))
		{
			try { Directory.Delete(_tempRoot, true); } catch { }
		}
	}

	[Fact]
	public void ScanTraversalRules_BoundaryAwareExclusion_MatchesChildAndExact_NotPrefixSibling()
	{
		var rules = new ScanTraversalRules(new ScanSettingDto
		{
			ExcludedPaths = new List<string> { "C:/Windows" }
		});

		Assert.True(rules.IsPathExcluded("C:/Windows"));
		Assert.True(rules.IsPathExcluded("C:\\Windows\\System32"));
		Assert.True(rules.IsPathExcluded("C:/windows/explorer.exe"));
		Assert.False(rules.IsPathExcluded("C:/WindowsApps"));
		Assert.False(rules.IsPathExcluded("C:/WindowsApps/package.dll"));
		Assert.False(rules.IsPathExcluded("C:/Users/Test"));
	}

	[Fact]
	public void ScanTraversalRules_HonoursHiddenAndSystemAndReparse()
	{
		var rules = new ScanTraversalRules(new ScanSettingDto
		{
			SkipHiddenFiles = true,
			SkipSystemFiles = true,
			FollowSymlinks = false,
			Depth = 2
		});

		Assert.True(rules.IsDirectorySkipped("C:/test", FileAttributes.Hidden, 1));
		Assert.True(rules.IsDirectorySkipped("C:/test", FileAttributes.System, 1));
		Assert.True(rules.IsDirectorySkipped("C:/test", FileAttributes.ReparsePoint, 1));
		Assert.True(rules.IsDirectorySkipped("C:/test", FileAttributes.Directory, 3)); // depth > 2
		Assert.False(rules.IsDirectorySkipped("C:/test", FileAttributes.Directory, 2));

		Assert.True(rules.IsFileSkipped("C:/test.txt", FileAttributes.Hidden, 100));
		Assert.True(rules.IsFileSkipped("C:/test.txt", FileAttributes.System, 100));
		Assert.True(rules.IsFileSkipped("C:/test.txt", FileAttributes.ReparsePoint, 100));
		Assert.False(rules.IsFileSkipped("C:/test.txt", FileAttributes.Normal, 100));
	}

	[Fact]
	public async Task IndexRootAsync_IndexesFilesAndDirectories_PopulatesIndex()
	{
		var subDir = Path.Combine(_tempRoot, "folderA");
		Directory.CreateDirectory(subDir);
		var file1 = Path.Combine(_tempRoot, "rootFile.txt");
		var file2 = Path.Combine(subDir, "nestedFile.txt");
		await File.WriteAllTextAsync(file1, "hello");
		await File.WriteAllTextAsync(file2, "world 123");

		var indexer = new FileSystemIndexer(_mockSettings.Object, NullLogger<FileSystemIndexer>.Instance);
		var index = await indexer.IndexRootAsync(_tempRoot, Guid.NewGuid(), CancellationToken.None);

		Assert.NotNull(index);
		Assert.True(index.ContainsKey(_tempRoot));
		Assert.True(index.ContainsKey(subDir));
		Assert.True(index.ContainsKey(file1));
		Assert.True(index.ContainsKey(file2));

		var fileEntry = index[file1];
		Assert.False(fileEntry.IsDirectory);
		Assert.Equal(5, fileEntry.SizeBytes);
		Assert.Equal(_tempRoot, fileEntry.ParentPath);

		Assert.True(indexer.TryGetIndex(_tempRoot, out var cachedIndex));
		Assert.Equal(index.Count, cachedIndex.Count);

		indexer.Invalidate(_tempRoot);
		Assert.False(indexer.TryGetIndex(_tempRoot, out _));
	}

	[Fact]
	public async Task IndexRootAsync_HandlesUnicodeAndNonBmpCharacters()
	{
		// Non-BMP Unicode character (emoji 🤡 and international characters)
		var unicodeDir = Path.Combine(_tempRoot, "Dir_🤡_日本語");
		Directory.CreateDirectory(unicodeDir);
		var unicodeFile = Path.Combine(unicodeDir, "File_🎉_accent_é.txt");
		await File.WriteAllTextAsync(unicodeFile, "unicode payload");

		var indexer = new FileSystemIndexer(_mockSettings.Object, NullLogger<FileSystemIndexer>.Instance);
		var index = await indexer.IndexRootAsync(_tempRoot, Guid.NewGuid(), CancellationToken.None);

		Assert.True(index.ContainsKey(unicodeDir));
		Assert.True(index.ContainsKey(unicodeFile));
		Assert.Equal(15, index[unicodeFile].SizeBytes);
	}

	[Fact]
	public async Task IndexRootAsync_CancellationStopsExecutionAndThrows()
	{
		var cts = new CancellationTokenSource();
		cts.Cancel();

		var indexer = new FileSystemIndexer(_mockSettings.Object, NullLogger<FileSystemIndexer>.Instance);
		await Assert.ThrowsAnyAsync<OperationCanceledException>(async () =>
		{
			await indexer.IndexRootAsync(_tempRoot, Guid.NewGuid(), cts.Token);
		});

		Assert.False(indexer.TryGetIndex(_tempRoot, out _));
	}
}
